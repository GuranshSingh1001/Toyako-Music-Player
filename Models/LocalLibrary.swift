import Foundation
import SwiftUI
import AVFoundation
import UIKit
import ImageIO
import CryptoKit

private struct LegacyFingerprint: Codable {
    let size: UInt64
    let modified: TimeInterval
}

@MainActor
class LocalLibrary:
    ObservableObject {

    private typealias FileFingerprint = ToyakoFileFingerprint

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
    private var cachedParserVersion: Int = 0
    private var albumArtworkSources: [String: URL] = [:]

    private var legacyPlaylistsCacheURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("playlists_cache.json")
    }

    private var legacyTracksCacheURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tracks_cache.bin")
    }

    private var legacyTracksJSONCacheURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tracks_cache.json")
    }

    private var legacyIndexManifestURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tracks_index_manifest.json")
    }

    private var artworkCacheDirectoryURL: URL {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ToyakoArtwork", isDirectory: true)
    }

    init() {
        loadUnifiedCache()

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
        let parserVersion = cachedParserVersion

        if cachedTracks.isEmpty {
            statusMessage = "Scanning..."
        }

        Task(priority: .utility) { [weak self] in
            // Let the cached library render first. The filesystem scan never
            // blocks the first SwiftUI frame.
            await Task.yield()

            let scan = await Self.runIncrementalScan(
                cachedTracks: cachedTracks,
                cachedFingerprints: fingerprints,
                cachedParserVersion: parserVersion
            )

            guard let self else { return }

            await MainActor.run {
                guard !scan.tracks.isEmpty || !cachedTracks.isEmpty else { return }

                let libraryChanged = scan.tracks != cachedTracks || scan.fingerprints != fingerprints

                if libraryChanged {
                    self.tracks = scan.tracks
                    self.cachedFingerprints = scan.fingerprints
                    self.cachedParserVersion = 2
                    self.rebuildGroups()
                    self.statusMessage = "Indexed \(scan.tracks.count) tracks"
                    self.saveUnifiedCache()
                }
            }
        }
    }

    nonisolated
    private static func runIncrementalScan(
        cachedTracks: [LocalTrack],
        cachedFingerprints: [String: FileFingerprint],
        cachedParserVersion: Int
    ) async -> (tracks: [LocalTrack], fingerprints: [String: FileFingerprint]) {
        let fileManager = FileManager.default

        guard let docs = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            return (cachedTracks, cachedFingerprints)
        }

        let audioExtensions: Set<String> = [
            "mp3", "m4a", "mp4", "wav", "wave", "flac",
            "aac", "aiff", "aif", "alac", "caf"
        ]

        var files: [(url: URL, fingerprint: FileFingerprint)] = []

        if let enumerator = fileManager.enumerator(
            at: docs,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .contentModificationDateKey
            ],
            options: [
                .skipsHiddenFiles,
                .skipsPackageDescendants
            ]
        ) {
            while let url = enumerator.nextObject() as? URL {
                guard audioExtensions.contains(
                    url.pathExtension.lowercased()
                ) else {
                    continue
                }

                guard let values = try? url.resourceValues(
                    forKeys: [
                        .isRegularFileKey,
                        .fileSizeKey,
                        .contentModificationDateKey
                    ]
                ),
                values.isRegularFile == true else {
                    continue
                }

                files.append(
                    (
                        url,
                        FileFingerprint(
                            size: UInt64(values.fileSize ?? 0),
                            modified:
                                values.contentModificationDate?
                                    .timeIntervalSinceReferenceDate ?? 0
                        )
                    )
                )
            }
        }

        let currentFingerprints = Dictionary(
            uniqueKeysWithValues: files.map {
                (
                    $0.url.standardizedFileURL.path,
                    $0.fingerprint
                )
            }
        )

        let cachedByPath = Dictionary(
            uniqueKeysWithValues: cachedTracks.map {
                (
                    $0.url.standardizedFileURL.path,
                    $0
                )
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
            return (
                cachedTracks,
                cachedFingerprints
            )
        }

        var result: [LocalTrack] = []
        result.reserveCapacity(files.count)

        var changed:
            [(Int, URL, LocalTrack?)] = []

        let metadataParserVersion = 2
        let needsParserMigration =
            cachedParserVersion < metadataParserVersion

        for (index, file) in files.enumerated() {
            let path =
                file.url.standardizedFileURL.path

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
                            title:
                                file.url
                                    .deletingPathExtension()
                                    .lastPathComponent
                        )
                )

                changed.append(
                    (
                        index,
                        file.url,
                        cachedByPath[path]
                    )
                )
            }
        }

        if !changed.isEmpty {

            // Avoid opening hundreds of AVAssets simultaneously on large
            // libraries. A small bounded pool keeps indexing responsive and
            // generally finishes faster than unbounded I/O contention.
            func parseEntry(
                _ entry:
                    (Int, URL, LocalTrack?)
            ) async -> (Int, LocalTrack) {

                let (
                    index,
                    url,
                    cached
                ) = entry

                let parsed =
                    await Self.parseAsset(
                        at: url
                    )

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
                            artworkData: nil
                        )
                    )
                }

                return (
                    index,
                    parsed
                )
            }

            let parsed =
                await withTaskGroup(
                    of: (Int, LocalTrack).self,
                    returning:
                        [Int: LocalTrack].self
                ) { group in

                    let concurrency =
                        min(
                            6,
                            changed.count
                        )

                    var next = 0

                    for _ in 0..<concurrency {
                        let entry =
                            changed[next]

                        next += 1

                        group.addTask {
                            await parseEntry(entry)
                        }
                    }

                    var values:
                        [Int: LocalTrack] = [:]

                    values.reserveCapacity(
                        changed.count
                    )

                    while let value =
                        await group.next() {

                        values[value.0] =
                            value.1

                        if next <
                            changed.count {

                            let entry =
                                changed[next]

                            next += 1

                            group.addTask {
                                await parseEntry(entry)
                            }
                        }
                    }

                    return values
                }

            for (index, track) in parsed {
                result[index] = track
            }
        }

        result.sort {
            $0.title.localizedCaseInsensitiveCompare(
                $1.title
            ) == .orderedAscending
        }

        return (
            result,
            currentFingerprints
        )
    }

    nonisolated
    private static func parseAsset(
        at url: URL
    ) async -> LocalTrack {

        // Indexing deliberately reads only text metadata + duration.
        // Album artwork is hydrated separately after the library is usable;
        // decoding/downsampling cover images must never be on the critical path.
        let asset =
            AVURLAsset(
                url: url,
                options: [
                    AVURLAssetPreferPreciseDurationAndTimingKey:
                        false
                ]
            )

        async let durationValue =
            asset.load(.duration)

        async let metadataValue =
            asset.load(.commonMetadata)

        let durationSeconds =
            (try? await durationValue)?.seconds ?? 0

        let duration =
            durationSeconds.isFinite
                ? max(0, durationSeconds)
                : 0

        let metadata =
            (try? await metadataValue) ?? []

        var title =
            url
                .deletingPathExtension()
                .lastPathComponent

        var artist =
            "Unknown Artist"

        var album =
            "Unknown Album"

        var genre =
            "Unknown Genre"

        // Match common keys as well as container-specific identifiers.
        // Artwork is intentionally excluded here; see hydrateArtwork().
        for item in metadata {

            let keys =
                metadataKeys(
                    for: item
                )

            if matchesMetadataKey(
                keys,
                aliases: [
                    "title",
                    "tit2",
                    "©nam"
                ]
            ),
            let value =
                await metadataStringValue(item),
            !value.isEmpty {

                title = value

            } else if matchesMetadataKey(
                keys,
                aliases: [
                    "artist",
                    "albumartist",
                    "album artist",
                    "tpe1",
                    "tpe2",
                    "©art",
                    "aart"
                ]
            ),
            let value =
                await metadataStringValue(item),
            !value.isEmpty {

                artist = value

            } else if matchesMetadataKey(
                keys,
                aliases: [
                    "album",
                    "albumname",
                    "talb",
                    "©alb"
                ]
            ),
            let value =
                await metadataStringValue(item),
            !value.isEmpty {

                album = value

            } else if matchesMetadataKey(
                keys,
                aliases: [
                    "genre",
                    "type",
                    "tcon",
                    "©gen"
                ]
            ),
            let value =
                await metadataStringValue(item),
            !value.isEmpty {

                genre = value
            }
        }

        return LocalTrack(
            url: url,
            title: title,
            artist: artist,
            album: album,
            genre: genre,
            duration: duration,
            artworkData: nil
        )
    }

    nonisolated
    private static func metadataKeys(
        for item: AVMetadataItem
    ) -> [String] {

        var keys: [String] = []

        if let commonKey =
            item.commonKey?.rawValue {

            keys.append(
                commonKey
            )
        }

        if let identifier =
            item.identifier?.rawValue {

            keys.append(
                identifier
            )
        }

        if let rawKey =
            item.key as? String {

            keys.append(
                rawKey
            )
        }

        // Some container-specific keys are bridged as non-String Foundation
        // objects. String(describing:) still gives us a useful identifier for
        // matching names such as TITLE / ARTIST / ALBUM.
        if let rawKey =
            item.key {

            keys.append(
                String(
                    describing:
                        rawKey
                )
            )
        }

        return Array(
            Set(
                keys.map {
                    $0
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )
                        .lowercased()
                }
            )
        )
    }

    nonisolated
    private static func matchesMetadataKey(
        _ keys: [String],
        aliases: [String]
    ) -> Bool {

        keys.contains { key in

            aliases.contains { alias in

                key == alias
                    || key.hasSuffix(
                        "/" + alias
                    )
                    || key.hasSuffix(
                        "." + alias
                    )
                    || key.contains(alias)
            }
        }
    }

    nonisolated
    private static func metadataStringValue(
        _ item: AVMetadataItem
    ) async -> String? {

        if let value =
            try? await item.load(.stringValue),
           !value
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
            .isEmpty {

            return value
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
        }

        if let value =
            try? await item.load(.value) {

            if let string =
                value as? String,
               !string
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .isEmpty {

                return string
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )
            }

            if let number =
                value as? NSNumber {

                return number.stringValue
            }
        }

        return nil
    }

    nonisolated
    private static func metadataDataValue(
        _ item: AVMetadataItem
    ) async -> Data? {

        if let data =
            try? await item.load(.dataValue) {

            return data
        }

        if let value =
            try? await item.load(.value),
           let data =
            value as? Data {

            return data
        }

        return nil
    }

    /// Warm the shared artwork cache for the currently playing track without
    /// mutating the published library. This prevents playback artwork from
    /// invalidating Home/Albums/Artists while still making the cover available.
    func refreshArtwork(
        for track: LocalTrack
    ) {

        let url =
            track.url

        Task(priority: .utility) {
            _ = await ArtworkStore.shared.data(
                for: url
            )
        }
    }

    // MARK: - Groups

    private static func albumArtworkKey(
        name: String,
        artist: String
    ) -> String {

        let normalizedName =
            name
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .lowercased()

        let normalizedArtist =
            artist
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .lowercased()

        return normalizedName
            + "\u{1F}"
            + normalizedArtist
    }

    /// Returns the canonical artwork source for an album. Every track in an
    /// album uses the same source as the album card, so the two can never show
    /// different embedded covers merely because individual files have slightly
    /// different artwork metadata.
    func artworkURL(
        for track: LocalTrack
    ) -> URL {

        albumArtworkSources[
            Self.albumArtworkKey(
                name: track.album,
                artist: track.artist
            )
        ] ?? track.url
    }

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
                    _,
                    trackList in

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

                    return AlbumGroup(
                        name: name,
                        artist: artist,
                        artworkURL:
                            trackList.first?.url,
                        tracks: trackList
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

        albumArtworkSources =
            Dictionary(
                uniqueKeysWithValues:
                    albumDictionary.compactMap {
                        _,
                        trackList in

                        guard let source =
                            trackList.first?.url
                        else {
                            return nil
                        }

                        let name =
                            trackList.first?.album
                            ??
                            "Unknown Album"

                        let artist =
                            trackList.first?.artist
                            ??
                            "Unknown Artist"

                        return (
                            Self.albumArtworkKey(
                                name: name,
                                artist: artist
                            ),
                            source
                        )
                    }
            )

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
                    _,
                    trackList in

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

        var number =
            2

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

        let value =
            playlists

        Task.detached(
            priority:
                .utility
        ) {

            ToyakoUnifiedCache.update {
                cache in

                cache.playlists =
                    value
            }
        }
    }

    // MARK: - Unified Binary Cache

    private func saveUnifiedCache() {

        let currentTracks =
            tracks

        let fingerprints =
            cachedFingerprints

        let playlists =
            playlists

        let parserVersion =
            cachedParserVersion

        Task.detached(
            priority:
                .utility
        ) {

            ToyakoUnifiedCache.update {
                cache in

                cache.tracks =
                    currentTracks

                cache.fingerprints =
                    fingerprints

                cache.playlists =
                    playlists

                cache.metadataParserVersion =
                    parserVersion
            }
        }
    }

    private func loadUnifiedCache() {

        if let cache =
            ToyakoUnifiedCache.load() {

            tracks =
                cache.tracks

            cachedFingerprints =
                cache.fingerprints

            playlists =
                cache.playlists

            cachedParserVersion =
                cache.metadataParserVersion

            statusMessage =
                "Indexed \(cache.tracks.count) tracks"

            // The unified cache is authoritative. Remove obsolete cache files
            // left by older Toyako builds after the first successful migration.
            for url in [
                legacyTracksCacheURL,
                legacyTracksJSONCacheURL,
                legacyIndexManifestURL,
                legacyPlaylistsCacheURL
            ] {

                try? FileManager.default
                    .removeItem(
                        at:
                            url
                    )
            }

            DispatchQueue.main.async {
                [weak self] in

                self?.rebuildGroups()
            }

            return
        }

        // One-time migration from all previous cache formats into ToyakoCache.bin.
        var migratedTracks:
            [LocalTrack] = []

        var migratedFingerprints:
            [String: FileFingerprint] = [:]

        var migratedPlaylists:
            [Playlist] = []

        if let data =
            try? Data(
                contentsOf:
                    legacyTracksCacheURL
            ),
           let decoded =
            Self.decodeBinaryCache(data) {

            migratedTracks =
                decoded.tracks

            migratedFingerprints =
                decoded.fingerprints

        } else if let data =
                    try? Data(
                        contentsOf:
                            legacyTracksJSONCacheURL
                    ),
                  let decoded =
                    try? JSONDecoder()
                        .decode(
                            [LocalTrack].self,
                            from:
                                data
                        ) {

            migratedTracks =
                decoded

            if let manifestData =
                try? Data(
                    contentsOf:
                        legacyIndexManifestURL
                ),
               let manifest =
                try? JSONDecoder()
                    .decode(
                        [String: LegacyFingerprint].self,
                        from:
                            manifestData
                    ) {

                migratedFingerprints =
                    manifest.mapValues {
                        FileFingerprint(
                            size:
                                $0.size,
                            modified:
                                $0.modified
                        )
                    }
            }
        }

        if let data =
            try? Data(
                contentsOf:
                    legacyPlaylistsCacheURL
            ),
           let decoded =
            try? JSONDecoder()
                .decode(
                    [Playlist].self,
                    from:
                        data
                ) {

            migratedPlaylists =
                decoded
        }

        guard
            !migratedTracks.isEmpty
                || !migratedPlaylists.isEmpty
        else {
            return
        }

        tracks =
            migratedTracks

        cachedFingerprints =
            migratedFingerprints

        playlists =
            migratedPlaylists

        cachedParserVersion =
            2

        statusMessage =
            "Indexed \(tracks.count) tracks"

        ToyakoUnifiedCache.update {
            cache in

            cache.tracks =
                migratedTracks

            cache.fingerprints =
                migratedFingerprints

            cache.playlists =
                migratedPlaylists

            cache.metadataParserVersion =
                2
        }

        for url in [
            legacyTracksCacheURL,
            legacyTracksJSONCacheURL,
            legacyIndexManifestURL,
            legacyPlaylistsCacheURL
        ] {

            try? FileManager.default
                .removeItem(
                    at:
                        url
                )
        }

        DispatchQueue.main.async {
            [weak self] in

            self?.rebuildGroups()
        }
    }

    nonisolated
    private static func encodeBinaryCache(
        tracks:
            [LocalTrack],
        fingerprints:
            [String: FileFingerprint]
    ) -> Data? {

        var data =
            Data()

        data.append(
            contentsOf:
                [
                    0x54,
                    0x4F,
                    0x59,
                    0x41,
                    0x4B,
                    0x4F,
                    0x42,
                    0x31
                ]
        )

        // TOYAKOB1
        append(
            UInt32(1),
            to:
                &data
        )

        append(
            UInt32(tracks.count),
            to:
                &data
        )

        for track in tracks {

            let path =
                track.url
                    .standardizedFileURL
                    .path

            let fingerprint =
                fingerprints[path]
                ??
                FileFingerprint(
                    size:
                        0,
                    modified:
                        0
                )

            appendUUID(
                track.id,
                to:
                    &data
            )

            appendString(
                path,
                to:
                    &data
            )

            appendString(
                track.title,
                to:
                    &data
            )

            appendString(
                track.artist,
                to:
                    &data
            )

            appendString(
                track.album,
                to:
                    &data
            )

            appendString(
                track.genre,
                to:
                    &data
            )

            append(
                track.duration,
                to:
                    &data
            )

            append(
                fingerprint.size,
                to:
                    &data
            )

            append(
                fingerprint.modified,
                to:
                    &data
            )
        }

        return data
    }

    nonisolated
    private static func decodeBinaryCache(
        _ data:
            Data
    ) -> (
        tracks:
            [LocalTrack],
        fingerprints:
            [String: FileFingerprint]
    )? {

        var reader =
            BinaryReader(
                data:
                    data
            )

        guard
            let magic =
                reader.readBytes(
                    count:
                        8
                ),
            magic ==
                [
                    0x54,
                    0x4F,
                    0x59,
                    0x41,
                    0x4B,
                    0x4F,
                    0x42,
                    0x31
                ],
            reader.readUInt32() == 1,
            let count =
                reader.readUInt32()
        else {
            return nil
        }

        var tracks:
            [LocalTrack] = []

        var fingerprints:
            [String: FileFingerprint] = [:]

        tracks.reserveCapacity(
            Int(count)
        )

        for _ in 0..<count {

            guard
                let id =
                    reader.readUUID(),
                let path =
                    reader.readString(),
                let title =
                    reader.readString(),
                let artist =
                    reader.readString(),
                let album =
                    reader.readString(),
                let genre =
                    reader.readString(),
                let duration =
                    reader.readDouble(),
                let size =
                    reader.readUInt64(),
                let modified =
                    reader.readDouble()
            else {
                return nil
            }

            let url =
                URL(
                    fileURLWithPath:
                        path
                )

            tracks.append(
                LocalTrack(
                    id:
                        id,
                    url:
                        url,
                    title:
                        title,
                    artist:
                        artist,
                    album:
                        album,
                    genre:
                        genre,
                    duration:
                        duration,
                    artworkData:
                        nil
                )
            )

            fingerprints[
                url
                    .standardizedFileURL
                    .path
            ] =
                FileFingerprint(
                    size:
                        size,
                    modified:
                        modified
                )
        }

        return (
            tracks,
            fingerprints
        )
    }

    nonisolated
    private static func append<T: FixedWidthInteger>(
        _ value:
            T,
        to data:
            inout Data
    ) {

        var little =
            value.littleEndian

        withUnsafeBytes(
            of:
                &little
        ) {

            data.append(
                contentsOf:
                    $0
            )
        }
    }

    nonisolated
    private static func append(
        _ value:
            Double,
        to data:
            inout Data
    ) {

        var bits =
            value.bitPattern.littleEndian

        withUnsafeBytes(
            of:
                &bits
        ) {

            data.append(
                contentsOf:
                    $0
            )
        }
    }

    nonisolated
    private static func appendUUID(
        _ uuid:
            UUID,
        to data:
            inout Data
    ) {

        var uuid =
            uuid

        withUnsafeBytes(
            of:
                &uuid
        ) {

            data.append(
                contentsOf:
                    $0
            )
        }
    }

    nonisolated
    private static func appendString(
        _ value:
            String,
        to data:
            inout Data
    ) {

        let bytes =
            Array(
                value.utf8
            )

        append(
            UInt32(bytes.count),
            to:
                &data
        )

        data.append(
            contentsOf:
                bytes
        )
    }

    private struct BinaryReader {

        let data:
            Data

        var offset:
            Int = 0

        mutating func readBytes(
            count:
                Int
        ) -> [UInt8]? {

            guard
                count >= 0,
                offset + count <=
                    data.count
            else {
                return nil
            }

            let result =
                Array(
                    data[
                        offset..<(offset + count)
                    ]
                )

            offset +=
                count

            return result
        }

        mutating func readUInt32()
            -> UInt32? {

            guard
                let bytes =
                    readBytes(
                        count:
                            4
                    )
            else {
                return nil
            }

            return bytes.withUnsafeBytes {
                $0.loadUnaligned(
                    as:
                        UInt32.self
                )
                .littleEndian
            }
        }

        mutating func readUInt64()
            -> UInt64? {

            guard
                let bytes =
                    readBytes(
                        count:
                            8
                    )
            else {
                return nil
            }

            return bytes.withUnsafeBytes {
                $0.loadUnaligned(
                    as:
                        UInt64.self
                )
                .littleEndian
            }
        }

        mutating func readDouble()
            -> Double? {

            guard
                let bits =
                    readUInt64()
            else {
                return nil
            }

            return Double(
                bitPattern:
                    bits
            )
        }

        mutating func readUUID()
            -> UUID? {

            guard
                let bytes =
                    readBytes(
                        count:
                            16
                    )
            else {
                return nil
            }

            return UUID(
                uuid: (
                    bytes[0],
                    bytes[1],
                    bytes[2],
                    bytes[3],
                    bytes[4],
                    bytes[5],
                    bytes[6],
                    bytes[7],
                    bytes[8],
                    bytes[9],
                    bytes[10],
                    bytes[11],
                    bytes[12],
                    bytes[13],
                    bytes[14],
                    bytes[15]
                )
            )
        }

        mutating func readString()
            -> String? {

            guard
                let count =
                    readUInt32(),
                count <=
                    UInt32(
                        data.count - offset
                    ),
                let bytes =
                    readBytes(
                        count:
                            Int(count)
                    )
            else {
                return nil
            }

            return String(
                bytes:
                    bytes,
                encoding:
                    .utf8
            )
        }
    }
}