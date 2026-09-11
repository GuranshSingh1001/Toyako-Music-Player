import Foundation
import SwiftUI
import AVFoundation
import UIKit
import ImageIO
import CryptoKit

@MainActor
class LocalLibrary:
    ObservableObject {

    private struct FileFingerprint: Equatable {
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

    private var cachedFingerprints: [String: FileFingerprint] = [:]

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
                "tracks_cache.bin"
            )
    }

    private var legacyTracksCacheURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tracks_cache.json")
    }

    private var legacyIndexManifestURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tracks_index_manifest.json")
    }

    private var artworkCacheDirectoryURL: URL {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ToyakoArtwork", isDirectory: true)
    }

    private var artworkHydrationTask: Task<Void, Never>?

    init() {
        loadPlaylists()
        loadTracksFromCache()

        // Never make the first rendered library screen wait for a filesystem scan.
        // The scan is intentionally deferred to the next run-loop turn and remains
        // on a utility task.
        DispatchQueue.main.async { [weak self] in
            self?.reloadFiles()
        }
    }

    // MARK: - Scanning

    func reloadFiles() {
        let cachedTracks = tracks
        let fingerprints = cachedFingerprints

        if cachedTracks.isEmpty {
            statusMessage = "Scanning..."
        }

        Task(priority: .utility) { [weak self] in
            // Let the cached library render first. The filesystem scan never
            // blocks the first SwiftUI frame.
            await Task.yield()

            let scan = await Self.runIncrementalScan(
                cachedTracks: cachedTracks,
                cachedFingerprints: fingerprints
            )

            guard let self else { return }

            await MainActor.run {
                guard !scan.tracks.isEmpty || !cachedTracks.isEmpty else { return }

                self.tracks = scan.tracks
                self.cachedFingerprints = scan.fingerprints
                self.rebuildGroups()
                self.statusMessage = "Indexed \(scan.tracks.count) songs"
                self.saveTracksToCache()
                self.scheduleArtworkHydration()
            }
        }
    }

    nonisolated
    private static func runIncrementalScan(
        cachedTracks: [LocalTrack],
        cachedFingerprints: [String: FileFingerprint]
    ) async -> (tracks: [LocalTrack], fingerprints: [String: FileFingerprint]) {
        let fileManager = FileManager.default
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return (cachedTracks, cachedFingerprints)
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
                guard let values = try? url.resourceValues(
                    forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
                ), values.isRegularFile == true else { continue }

                files.append((
                    url,
                    FileFingerprint(
                        size: UInt64(values.fileSize ?? 0),
                        modified: values.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
                    )
                ))
            }
        }

        let currentFingerprints = Dictionary(
            uniqueKeysWithValues: files.map {
                ($0.url.standardizedFileURL.path, $0.fingerprint)
            }
        )
        let cachedByPath = Dictionary(
            uniqueKeysWithValues: cachedTracks.map {
                ($0.url.standardizedFileURL.path, $0)
            }
        )

        let cacheNeedsMetadataRepair = cachedTracks.contains { track in
            track.title.isEmpty
                || track.artist == "Unknown Artist"
                || track.album == "Unknown Album"
                || track.duration <= 0
        }

        // Fast path: the binary cache already contains the exact file set and
        // fingerprints. No AVAsset is opened at all.
        if currentFingerprints == cachedFingerprints,
           files.count == cachedTracks.count,
           !cachedTracks.isEmpty,
           !cacheNeedsMetadataRepair {
            return (cachedTracks, cachedFingerprints)
        }

        var result: [LocalTrack] = []
        result.reserveCapacity(files.count)
        var changed: [(Int, URL, LocalTrack?)] = []

        let metadataParserVersion = 2
        let parserVersionKey = "Toyako.MetadataParserVersion"
        let needsParserMigration =
            UserDefaults.standard.integer(forKey: parserVersionKey) < metadataParserVersion

        for (index, file) in files.enumerated() {
            let path = file.url.standardizedFileURL.path

            if let cached = cachedByPath[path],
               !needsParserMigration,
               cachedFingerprints[path] == file.fingerprint,
               !cached.title.isEmpty,
               cached.artist != "Unknown Artist",
               cached.album != "Unknown Album",
               cached.duration > 0 {
                result.append(cached)
            } else {
                result.append(
                    cachedByPath[path]
                        ?? LocalTrack(
                            url: file.url,
                            title: file.url.deletingPathExtension().lastPathComponent
                        )
                )
                changed.append((index, file.url, cachedByPath[path]))
            }
        }

        if !changed.isEmpty {
            let parsed = await withTaskGroup(
                of: (Int, LocalTrack).self,
                returning: [Int: LocalTrack].self
            ) { group in
                for (index, url, cached) in changed {
                    group.addTask {
                        let parsed = await Self.parseAsset(at: url)

                        if let cached {
                            return (
                                index,
                                LocalTrack(
                                    id: cached.id,
                                    url: parsed.url,
                                    title: parsed.title,
                                    artist: parsed.artist,
                                    album: parsed.album,
                                    genre: parsed.genre,
                                    duration: parsed.duration,
                                    artworkData: parsed.artworkData
                                )
                            )
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

        UserDefaults.standard.set(
            metadataParserVersion,
            forKey: parserVersionKey
        )

        return (result, currentFingerprints)
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

        // AVFoundation does not expose every container's Vorbis/FLAC keys in
        // exactly the same way. In particular, relying on `item.key as? String`
        // misses some FLAC metadata identifiers. Match commonKey, identifier,
        // and raw key names, and accept the item's loaded value as a fallback
        // when stringValue is unavailable.
        for item in metadata {
            let keys = metadataKeys(for: item)

            if matchesMetadataKey(keys, aliases: ["title", "tit2", "©nam"]),
               let value = await metadataStringValue(item), !value.isEmpty {
                title = value
            } else if matchesMetadataKey(keys, aliases: ["artist", "albumartist", "album artist", "tpe1", "tpe2", "©art", "aart"]),
                      let value = await metadataStringValue(item), !value.isEmpty {
                artist = value
            } else if matchesMetadataKey(keys, aliases: ["album", "albumname", "talb", "©alb"]),
                      let value = await metadataStringValue(item), !value.isEmpty {
                album = value
            } else if matchesMetadataKey(keys, aliases: ["genre", "type", "tcon", "©gen"]),
                      let value = await metadataStringValue(item), !value.isEmpty {
                genre = value
            } else if matchesMetadataKey(keys, aliases: ["artwork", "picture", "cover", "apic", "covr"]),
                      let data = await metadataDataValue(item) {
                artworkData = downsampleArtwork(data)
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

    nonisolated
    private static func metadataKeys(for item: AVMetadataItem) -> [String] {
        var keys: [String] = []
        if let commonKey = item.commonKey?.rawValue { keys.append(commonKey) }
        if let identifier = item.identifier?.rawValue { keys.append(identifier) }
        if let rawKey = item.key as? String { keys.append(rawKey) }
        // Some container-specific keys are bridged as non-String Foundation
        // objects. String(describing:) still gives us a useful identifier for
        // matching names such as TITLE / ARTIST / ALBUM.
        if let rawKey = item.key { keys.append(String(describing: rawKey)) }
        return Array(Set(keys.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }))
    }

    nonisolated
    private static func matchesMetadataKey(_ keys: [String], aliases: [String]) -> Bool {
        keys.contains { key in
            aliases.contains { alias in
                key == alias || key.hasSuffix("/" + alias) || key.hasSuffix("." + alias)
                    || key.contains(alias)
            }
        }
    }

    nonisolated
    private static func metadataStringValue(_ item: AVMetadataItem) async -> String? {
        if let value = try? await item.load(.stringValue),
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let value = try? await item.load(.value) {
            if let string = value as? String,
               !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return string.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let number = value as? NSNumber {
                return number.stringValue
            }
        }
        return nil
    }

    nonisolated
    private static func metadataDataValue(_ item: AVMetadataItem) async -> Data? {
        if let data = try? await item.load(.dataValue) {
            return data
        }
        if let value = try? await item.load(.value), let data = value as? Data {
            return data
        }
        return nil
    }

    /// Artwork is fetched only for the active track on a cached launch. This keeps
    /// startup fast without leaving Now Playing stuck with a blank cover.
    func refreshArtwork(for track: LocalTrack) {
        guard track.artworkData == nil else { return }
        let url = track.url

        let cacheDirectory = artworkCacheDirectoryURL
        Task(priority: .utility) {
            let refreshed: Data?
            
            if let cached = Self.cachedArtwork(for: url, in: cacheDirectory) {
                refreshed = cached
            } else {
                refreshed = await Self.parseArtworkOnly(at: url)
            }

            guard let artworkData = refreshed else { return }
            let cacheFile = cacheDirectory.appendingPathComponent(Self.artworkFilename(for: url))
            try? artworkData.write(to: cacheFile, options: .atomic)

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
            guard matchesMetadataKey(metadataKeys(for: item), aliases: ["artwork", "picture", "cover", "apic", "covr"]) else { continue }
            if let data = await metadataDataValue(item) {
                return downsampleArtwork(data)
            }
        }
        return nil
    }

    // MARK: - Artwork Cache

    private func scheduleArtworkHydration() {
        let snapshot = tracks
        artworkHydrationTask?.cancel()

        let cacheDirectory = artworkCacheDirectoryURL
        artworkHydrationTask = Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, self != nil else { return }

            let results = await Self.hydrateArtwork(snapshot, cacheDirectory: cacheDirectory)
            guard !results.isEmpty, !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self else { return }
                var changed = false

                for (url, data) in results {
                    guard let index = self.tracks.firstIndex(where: {
                        $0.url.standardizedFileURL == url.standardizedFileURL
                    }) else { continue }

                    let old = self.tracks[index]
                    guard old.artworkData == nil else { continue }
                    self.tracks[index] = LocalTrack(
                        id: old.id, url: old.url, title: old.title, artist: old.artist,
                        album: old.album, genre: old.genre, duration: old.duration, artworkData: data
                    )
                    changed = true
                }

                if changed {
                    self.rebuildGroups()
                }
            }
        }
    }

    nonisolated
    private static func hydrateArtwork(
        _ tracks: [LocalTrack],
        cacheDirectory: URL
    ) async -> [(URL, Data)] {
        try? FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )

        return await withTaskGroup(of: (URL, Data)?.self, returning: [(URL, Data)].self) { group in
            var pending = 0
            var results: [(URL, Data)] = []

            func add(_ track: LocalTrack) {
                pending += 1
                group.addTask {
                    if let cached = cachedArtwork(for: track.url, in: cacheDirectory) {
                        return (track.url, cached)
                    }
                    guard let data = await parseArtworkOnly(at: track.url) else { return nil }
                    let file = cacheDirectory.appendingPathComponent(artworkFilename(for: track.url))
                    try? data.write(to: file, options: .atomic)
                    return (track.url, data)
                }
            }

            for track in tracks where track.artworkData == nil {
                add(track)
                if pending >= 4 {
                    if let result = await group.next(), let result { results.append(result) }
                    pending -= 1
                }
            }

            while pending > 0 {
                if let result = await group.next(), let result { results.append(result) }
                pending -= 1
            }

            return results
        }
    }

    nonisolated
    private static func artworkFilename(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.standardizedFileURL.path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".jpg"
    }

    nonisolated
    private static func cachedArtwork(for url: URL, in directory: URL) -> Data? {
        let file = directory.appendingPathComponent(artworkFilename(for: url))
        return try? Data(contentsOf: file)
    }

    nonisolated
    private static func downsampleArtwork(_ data: Data, maxPixel: Int = 512) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return data }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return data
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else {
            return data
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return data }
        return output as Data
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
        let currentTracks = tracks
        let fingerprints = cachedFingerprints
        let cacheURL = tracksCacheURL

        Task.detached(priority: .utility) {
            guard let data = Self.encodeBinaryCache(
                tracks: currentTracks,
                fingerprints: fingerprints
            ) else {
                return
            }

            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    private func loadTracksFromCache() {
        // New binary cache: a single compact read + decode.
        if let data = try? Data(contentsOf: tracksCacheURL),
           let decoded = Self.decodeBinaryCache(data) {
            tracks = decoded.tracks
            cachedFingerprints = decoded.fingerprints
            rebuildGroups()
            statusMessage = "Indexed \(decoded.tracks.count) songs"
            return
        }

        // One-time migration from the previous JSON cache. The old cache is
        // never used again after this succeeds.
        guard let data = try? Data(contentsOf: legacyTracksCacheURL),
              let decoded = try? JSONDecoder().decode([LocalTrack].self, from: data)
        else {
            return
        }

        var fingerprints: [String: FileFingerprint] = [:]
        if let manifestData = try? Data(contentsOf: legacyIndexManifestURL),
           let manifest = try? JSONDecoder().decode([String: LegacyFingerprint].self, from: manifestData) {
            fingerprints = manifest.mapValues {
                FileFingerprint(size: $0.size, modified: $0.modified)
            }
        }

        tracks = decoded
        cachedFingerprints = fingerprints
        rebuildGroups()
        statusMessage = "Indexed \(decoded.count) songs"

        // Immediately convert the old representation to the binary format.
        saveTracksToCache()

        try? FileManager.default.removeItem(at: legacyTracksCacheURL)
        try? FileManager.default.removeItem(at: legacyIndexManifestURL)
    }

    private struct LegacyFingerprint: Codable {
        let size: UInt64
        let modified: TimeInterval
    }

    nonisolated
    private static func encodeBinaryCache(
        tracks: [LocalTrack],
        fingerprints: [String: FileFingerprint]
    ) -> Data? {
        var data = Data()
        data.append(contentsOf: [0x54, 0x4F, 0x59, 0x41, 0x4B, 0x4F, 0x42, 0x31]) // TOYAKOB1
        append(UInt32(1), to: &data)
        append(UInt32(tracks.count), to: &data)

        for track in tracks {
            let path = track.url.standardizedFileURL.path
            let fingerprint = fingerprints[path] ?? FileFingerprint(size: 0, modified: 0)

            appendUUID(track.id, to: &data)
            appendString(path, to: &data)
            appendString(track.title, to: &data)
            appendString(track.artist, to: &data)
            appendString(track.album, to: &data)
            appendString(track.genre, to: &data)
            append(track.duration, to: &data)
            append(fingerprint.size, to: &data)
            append(fingerprint.modified, to: &data)
        }

        return data
    }

    nonisolated
    private static func decodeBinaryCache(
        _ data: Data
    ) -> (tracks: [LocalTrack], fingerprints: [String: FileFingerprint])? {
        var reader = BinaryReader(data: data)

        guard let magic = reader.readBytes(count: 8),
              magic == [0x54, 0x4F, 0x59, 0x41, 0x4B, 0x4F, 0x42, 0x31],
              reader.readUInt32() == 1,
              let count = reader.readUInt32()
        else {
            return nil
        }

        var tracks: [LocalTrack] = []
        var fingerprints: [String: FileFingerprint] = [:]
        tracks.reserveCapacity(Int(count))

        for _ in 0..<count {
            guard let id = reader.readUUID(),
                  let path = reader.readString(),
                  let title = reader.readString(),
                  let artist = reader.readString(),
                  let album = reader.readString(),
                  let genre = reader.readString(),
                  let duration = reader.readDouble(),
                  let size = reader.readUInt64(),
                  let modified = reader.readDouble()
            else {
                return nil
            }

            let url = URL(fileURLWithPath: path)
            tracks.append(
                LocalTrack(
                    id: id,
                    url: url,
                    title: title,
                    artist: artist,
                    album: album,
                    genre: genre,
                    duration: duration,
                    artworkData: nil
                )
            )
            fingerprints[url.standardizedFileURL.path] = FileFingerprint(
                size: size,
                modified: modified
            )
        }

        return (tracks, fingerprints)
    }

    nonisolated
    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    nonisolated
    private static func append(_ value: Double, to data: inout Data) {
        var bits = value.bitPattern.littleEndian
        withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
    }

    nonisolated
    private static func appendUUID(_ uuid: UUID, to data: inout Data) {
        var uuid = uuid
        withUnsafeBytes(of: &uuid) { data.append(contentsOf: $0) }
    }

    nonisolated
    private static func appendString(_ value: String, to data: inout Data) {
        let bytes = Array(value.utf8)
        append(UInt32(bytes.count), to: &data)
        data.append(contentsOf: bytes)
    }

    private struct BinaryReader {
        let data: Data
        var offset: Int = 0

        mutating func readBytes(count: Int) -> [UInt8]? {
            guard count >= 0, offset + count <= data.count else { return nil }
            let result = Array(data[offset..<(offset + count)])
            offset += count
            return result
        }

        mutating func readUInt32() -> UInt32? {
            guard let bytes = readBytes(count: 4) else { return nil }
            return bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
        }

        mutating func readUInt64() -> UInt64? {
            guard let bytes = readBytes(count: 8) else { return nil }
            return bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).littleEndian }
        }

        mutating func readDouble() -> Double? {
            guard let bits = readUInt64() else { return nil }
            return Double(bitPattern: bits)
        }

        mutating func readUUID() -> UUID? {
            guard let bytes = readBytes(count: 16) else { return nil }
            return UUID(uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3],
                bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11],
                bytes[12], bytes[13], bytes[14], bytes[15]
            ))
        }

        mutating func readString() -> String? {
            guard let count = readUInt32(),
                  count <= UInt32(data.count - offset),
                  let bytes = readBytes(count: Int(count))
            else {
                return nil
            }
            return String(bytes: bytes, encoding: .utf8)
        }
    }

}