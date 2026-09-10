import Foundation
import SwiftUI
import AVFoundation

@MainActor
class LocalLibrary:
    ObservableObject {

    private struct FileFingerprint: Codable, Equatable {
        let size: UInt64
        let modified: TimeInterval
    }

    @Published var tracks:
        [LocalTrack] = []

    @Published var albums:
        [AlbumGroup] = []

    @Published var artists:
        [ArtistGroup] = []

    @Published var playlists:
        [Playlist] = []

    @Published var statusMessage:
        String = "Scanning..."

    private var playlistsCacheURL:
        URL {
        FileManager.default
            .urls(
                for:
                    .documentDirectory,
                in:
                    .userDomainMask
            )[0]
            .appendingPathComponent(
                "playlists_cache.json"
            )
    }

    private var tracksCacheURL:
        URL {
        FileManager.default
            .urls(
                for:
                    .documentDirectory,
                in:
                    .userDomainMask
            )[0]
            .appendingPathComponent(
                "tracks_cache.json"
            )
    }

    private var indexManifestURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tracks_index_manifest.json")
    }

    init() {
        loadPlaylists()
        loadTracksFromCache()
        reloadFiles()
    }

    // MARK: - Scanning

    func reloadFiles() {
        let cachedTracks = tracks
        if cachedTracks.isEmpty {
            statusMessage = "Scanning..."
        }

        let manifestURL = indexManifestURL
        Task(priority: .utility) {
            let discovered = await Self.runIncrementalScan(
                cachedTracks: cachedTracks,
                manifestURL: manifestURL
            )

            await MainActor.run {
                guard !discovered.isEmpty || !cachedTracks.isEmpty else { return }
                self.tracks = discovered
                self.rebuildGroups()
                self.statusMessage = "Indexed \(discovered.count) songs"
                self.saveTracksToCache()
            }
        }
    }

    nonisolated
    private static func runIncrementalScan(
        cachedTracks: [LocalTrack],
        manifestURL: URL
    ) async -> [LocalTrack] {
        let fileManager = FileManager.default
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return cachedTracks
        }

        let audioExtensions: Set<String> = [
            "mp3", "m4a", "mp4", "wav", "wave", "flac", "aac", "aiff", "aif", "alac", "caf"
        ]

        var files: [(url: URL, fingerprint: FileFingerprint)] = []
        if let enumerator = fileManager.enumerator(
            at: docs,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            while let url = enumerator.nextObject() as? URL {
                guard audioExtensions.contains(url.pathExtension.lowercased()) else { continue }
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                      values.isRegularFile == true else { continue }
                files.append((
                    url,
                    FileFingerprint(
                        size: UInt64(values.fileSize ?? 0),
                        modified: values.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
                    )
                ))
            }
        }

        var oldManifest: [String: FileFingerprint] = [:]
        if let data = try? Data(contentsOf: manifestURL),
           let decoded = try? JSONDecoder().decode([String: FileFingerprint].self, from: data) {
            oldManifest = decoded
        }

        let currentManifest = Dictionary(uniqueKeysWithValues: files.map { ($0.url.standardizedFileURL.path, $0.fingerprint) })
        let cachedByPath = Dictionary(uniqueKeysWithValues: cachedTracks.map { ($0.url.standardizedFileURL.path, $0) })

        // Fast path: the library has not changed. Do not open a single AVAsset.
        if currentManifest == oldManifest,
           files.count == cachedTracks.count,
           !cachedTracks.isEmpty {
            return cachedTracks
        }

        var result: [LocalTrack] = []
        result.reserveCapacity(files.count)
        var changed: [(Int, URL, LocalTrack?)] = []

        for (index, file) in files.enumerated() {
            let path = file.url.standardizedFileURL.path
            if let cached = cachedByPath[path], oldManifest[path] == file.fingerprint {
                result.append(cached)
            } else {
                result.append(cachedByPath[path] ?? LocalTrack(url: file.url, title: file.url.deletingPathExtension().lastPathComponent))
                changed.append((index, file.url, cachedByPath[path]))
            }
        }

        if !changed.isEmpty {
            let parsed = await withTaskGroup(of: (Int, LocalTrack).self, returning: [Int: LocalTrack].self) { group in
                for (index, url, cached) in changed {
                    group.addTask {
                        let parsed = await Self.parseAsset(at: url)
                        if let cached {
                            return (index, LocalTrack(
                                id: cached.id,
                                url: parsed.url,
                                title: parsed.title,
                                artist: parsed.artist,
                                album: parsed.album,
                                genre: parsed.genre,
                                duration: parsed.duration,
                                artworkData: parsed.artworkData
                            ))
                        }
                        return (index, parsed)
                    }
                }

                var values: [Int: LocalTrack] = [:]
                for await (index, track) in group {
                    values[index] = track
                }
                return values
            }

            for (index, track) in parsed {
                result[index] = track
            }
        }

        result.sort {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }

        if let data = try? JSONEncoder().encode(currentManifest) {
            try? data.write(to: manifestURL, options: .atomic)
        }

        return result
    }

    nonisolated
    private static func parseAsset(at url: URL) async -> LocalTrack {
        let asset = AVURLAsset(
            url: url,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: false]
        )

        async let durationValue = asset.load(.duration)
        async let metadataValue = asset.load(.commonMetadata)

        let durationSeconds = (try? await durationValue)?.seconds ?? 0
        let duration = durationSeconds.isFinite ? max(0, durationSeconds) : 0
        let metadata = (try? await metadataValue) ?? []

        var title = url.deletingPathExtension().lastPathComponent
        var artist = "Unknown Artist"
        var album = "Unknown Album"
        var genre = "Unknown Genre"
        var artworkData: Data?

        // Only load the metadata values that are actually used. commonMetadata is
        // considerably cheaper than asking AVFoundation for the complete metadata set.
        for item in metadata {
            let key = item.commonKey?.rawValue ?? (item.key as? String) ?? ""

            if ["title", "TIT2", "©nam"].contains(key),
               let value = try? await item.load(.stringValue),
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                title = value
            } else if ["artist", "TPE1", "TPE2", "©ART", "aART"].contains(key),
                      let value = try? await item.load(.stringValue),
                      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                artist = value
            } else if ["albumName", "album", "TALB", "©alb"].contains(key),
                      let value = try? await item.load(.stringValue),
                      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                album = value
            } else if ["type", "genre", "TCON", "©gen"].contains(key),
                      let value = try? await item.load(.stringValue),
                      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                genre = value
            } else if ["artwork", "APIC", "covr"].contains(key) {
                artworkData = try? await item.load(.dataValue)
                if artworkData == nil, let value = try? await item.load(.value), let data = value as? Data {
                    artworkData = data
                }
            }
        }

        return LocalTrack(
            url: url,
            title: title,
            artist: artist,
            album: album,
            genre: genre,
            duration: duration,
            artworkData: artworkData
        )
    }

    /// Artwork is fetched only for the active track on a cached launch. This keeps
    /// startup fast without leaving Now Playing stuck with a blank cover.
    func refreshArtwork(for track: LocalTrack) {
        guard track.artworkData == nil else { return }
        let url = track.url

        Task(priority: .utility) {
            let refreshed = await Self.parseArtworkOnly(at: url)
            guard let artworkData = refreshed else { return }

            await MainActor.run {
                guard let index = self.tracks.firstIndex(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) else { return }
                let old = self.tracks[index]
                self.tracks[index] = LocalTrack(
                    id: old.id,
                    url: old.url,
                    title: old.title,
                    artist: old.artist,
                    album: old.album,
                    genre: old.genre,
                    duration: old.duration,
                    artworkData: artworkData
                )
                self.rebuildGroups()
            }
        }
    }

    nonisolated
    private static func parseArtworkOnly(at url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        let metadata = (try? await asset.load(.commonMetadata)) ?? []
        for item in metadata {
            let key = item.commonKey?.rawValue ?? (item.key as? String) ?? ""
            guard ["artwork", "APIC", "covr"].contains(key) else { continue }
            if let data = try? await item.load(.dataValue) { return data }
            if let value = try? await item.load(.value), let data = value as? Data { return data }
        }
        return nil
    }

    // MARK: - Groups

    private func rebuildGroups() {

        let albumDictionary =
            Dictionary(
                grouping:
                    tracks,
                by: {
                    let album =
                        $0.album
                            .trimmingCharacters(
                                in:
                                    .whitespacesAndNewlines
                            )
                            .lowercased()

                    let artist =
                        $0.artist
                            .trimmingCharacters(
                                in:
                                    .whitespacesAndNewlines
                            )
                            .lowercased()

                    return
                        "\(album)_\(artist)"
                }
            )

        albums =
            albumDictionary
            .map {
                _, trackList in

                let name =
                    trackList.first {
                        $0.album
                            != "Unknown Album"
                    }?
                    .album
                    ??
                    "Unknown Album"

                let artist =
                    trackList.first {
                        $0.artist
                            != "Unknown Artist"
                    }?
                    .artist
                    ??
                    "Unknown Artist"

                let artwork =
                    trackList.first {
                        $0.artworkData
                            != nil
                    }?
                    .artworkData

                return AlbumGroup(
                    name:
                        name,
                    artist:
                        artist,
                    artworkData:
                        artwork,
                    tracks:
                        trackList
                )
            }
            .sorted {
                $0.name
                    .localizedCaseInsensitiveCompare(
                        $1.name
                    )
                    ==
                    .orderedAscending
            }

        let artistDictionary =
            Dictionary(
                grouping:
                    tracks,
                by: {
                    $0.artist
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )
                        .lowercased()
                }
            )

        artists =
            artistDictionary
            .map {
                _, trackList in

                let name =
                    trackList.first {
                        $0.artist
                            != "Unknown Artist"
                    }?
                    .artist
                    ??
                    "Unknown Artist"

                return ArtistGroup(
                    name:
                        name,
                    tracks:
                        trackList
                )
            }
            .sorted {
                $0.name
                    .localizedCaseInsensitiveCompare(
                        $1.name
                    )
                    ==
                    .orderedAscending
            }
    }

    // MARK: - Import

    func importExternalURLs(
        _ urls:
            [URL]
    ) {

        guard !urls.isEmpty
        else {
            return
        }

        statusMessage =
            "Importing..."

        Task {
            let importedCount =
                await performImport(
                    urls:
                        urls
                )

            self.reloadFiles()

            if importedCount > 0 {
                self.statusMessage =
                    "Imported \(importedCount) "
                    + (
                        importedCount == 1
                        ? "file"
                        : "files"
                    )
            }
        }
    }

    nonisolated
    private func performImport(
        urls:
            [URL]
    ) async -> Int {

        let fileManager =
            FileManager.default

        guard let documents =
            fileManager.urls(
                for:
                    .documentDirectory,
                in:
                    .userDomainMask
            ).first
        else {
            return 0
        }

        var importedCount =
            0

        for sourceURL in urls {

            let accessing =
                sourceURL
                    .startAccessingSecurityScopedResource()

            defer {
                if accessing {
                    sourceURL
                        .stopAccessingSecurityScopedResource()
                }
            }

            do {
                let destination =
                    uniqueDestinationURL(
                        for:
                            sourceURL,
                        in:
                            documents,
                        fileManager:
                            fileManager
                    )

                try fileManager.copyItem(
                    at:
                        sourceURL,
                    to:
                        destination
                )

                importedCount += 1

            } catch {
                // Try a second path for providers that
                // return a temporary URL.
                do {
                    let data =
                        try Data(
                            contentsOf:
                                sourceURL
                        )

                    let destination =
                        uniqueDestinationURL(
                            for:
                                sourceURL,
                            in:
                                documents,
                            fileManager:
                                fileManager
                        )

                    try data.write(
                        to:
                            destination,
                        options:
                            .atomic
                    )

                    importedCount += 1

                } catch {
                    continue
                }
            }
        }

        return importedCount
    }

    nonisolated
    private func uniqueDestinationURL(
        for source:
            URL,
        in directory:
            URL,
        fileManager:
            FileManager
    ) -> URL {

        let base =
            source
                .deletingPathExtension()
                .lastPathComponent

        let ext =
            source
                .pathExtension

        var candidate =
            directory
                .appendingPathComponent(
                    source.lastPathComponent
                )

        var number = 2

        while fileManager.fileExists(
            atPath:
                candidate.path
        ) {

            let filename =
                ext.isEmpty
                ? "\(base) \(number)"
                : "\(base) \(number).\(ext)"

            candidate =
                directory
                    .appendingPathComponent(
                        filename
                    )

            number += 1
        }

        return candidate
    }

    // MARK: - Playlists

    func createPlaylist(
        name:
            String
    ) {
        let playlist =
            Playlist(
                name:
                    name,
                trackURLs:
                    []
            )

        playlists.append(
            playlist
        )

        savePlaylists()
    }

    func addTracksToPlaylist(
        playlistID:
            UUID,
        trackURLs:
            [URL]
    ) {

        guard let index =
            playlists.firstIndex(
                where:
                    {
                        $0.id ==
                            playlistID
                    }
            )
        else {
            return
        }

        for url in trackURLs {

            if !playlists[index]
                .trackURLs
                .contains(url) {

                playlists[index]
                    .trackURLs
                    .append(url)
            }
        }

        savePlaylists()
    }

    func removeTrackFromPlaylist(
        playlistID:
            UUID,
        trackURL:
            URL
    ) {

        guard let index =
            playlists.firstIndex(
                where:
                    {
                        $0.id ==
                            playlistID
                    }
            )
        else {
            return
        }

        playlists[index]
            .trackURLs
            .removeAll {
                $0 == trackURL
            }

        savePlaylists()
    }

    func renamePlaylist(
        id:
            UUID,
        newName:
            String
    ) {

        guard let index =
            playlists.firstIndex(
                where:
                    {
                        $0.id == id
                    }
            )
        else {
            return
        }

        playlists[index].name =
            newName

        savePlaylists()
    }

    private func savePlaylists() {

        guard let data =
            try? JSONEncoder()
                .encode(
                    playlists
                )
        else {
            return
        }

        try? data.write(
            to:
                playlistsCacheURL,
            options:
                .atomic
        )
    }

    private func loadPlaylists() {

        guard let data =
            try? Data(
                contentsOf:
                    playlistsCacheURL
            ),
              let decoded =
                try? JSONDecoder()
                    .decode(
                        [Playlist].self,
                        from:
                            data
                    )
        else {
            return
        }

        playlists =
            decoded
    }

    // MARK: - Cache

    private func saveTracksToCache() {

        let currentTracks =
            tracks

        let cacheURL =
            tracksCacheURL

        DispatchQueue.global(
            qos:
                .background
        ).async {

            if let data =
                try? JSONEncoder()
                    .encode(
                        currentTracks
                    ) {

                try? data.write(
                    to:
                        cacheURL,
                    options:
                        .atomic
                )
            }
        }
    }

    private func loadTracksFromCache() {

        guard let data =
            try? Data(
                contentsOf:
                    tracksCacheURL
            ),
              let decoded =
                try? JSONDecoder()
                    .decode(
                        [LocalTrack].self,
                        from:
                            data
                    )
        else {
            return
        }

        tracks =
            decoded

        rebuildGroups()

        statusMessage =
            "Indexed \(decoded.count) songs"
    }
}