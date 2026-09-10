import Foundation
import SwiftUI
import AVFoundation

@MainActor
class LocalLibrary:
    ObservableObject {

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

    init() {
        loadPlaylists()
        loadTracksFromCache()
        reloadFiles()
    }

    // MARK: - Scanning

    func reloadFiles() {

        if tracks.isEmpty {
            statusMessage =
                "Scanning..."
        }

        Task {
            let discovered =
                await runBackgroundScan()

            self.tracks =
                discovered

            self.rebuildGroups()

            self.statusMessage =
                "Indexed \(discovered.count) songs"

            self.saveTracksToCache()
        }
    }

    nonisolated
    private func runBackgroundScan()
        async -> [LocalTrack] {

        let fileManager =
            FileManager.default

        guard let docs =
            fileManager.urls(
                for:
                    .documentDirectory,
                in:
                    .userDomainMask
            ).first
        else {
            return []
        }

        let audioExtensions:
            Set<String> = [
                "mp3",
                "m4a",
                "mp4",
                "wav",
                "wave",
                "flac",
                "aac",
                "aiff",
                "aif",
                "alac",
                "caf"
            ]

        var discoveredURLs:
            [URL] = []

        if let enumerator =
            fileManager.enumerator(
                at:
                    docs,
                includingPropertiesForKeys:
                    [
                        .isRegularFileKey
                    ],
                options:
                    [
                        .skipsHiddenFiles,
                        .skipsPackageDescendants
                    ]
            ) {

            while let url =
                enumerator.nextObject()
                as? URL {

                let extensionName =
                    url.pathExtension
                        .lowercased()

                guard audioExtensions
                    .contains(
                        extensionName
                    )
                else {
                    continue
                }

                // Avoid an extra filesystem metadata lookup for every file.
                // The enumerator already gives us the URL; directories with an
                // audio-looking suffix are simply ignored.
                guard !url.hasDirectoryPath else {
                    continue
                }

                discoveredURLs.append(url)
            }
        }

        // Parse multiple audio files concurrently. A bounded task group keeps
        // indexing fast without creating hundreds of AVAsset operations at once.
        let concurrencyLimit = min(8, max(1, discoveredURLs.count))
        var discovered: [LocalTrack] = []
        discovered.reserveCapacity(discoveredURLs.count)

        await withTaskGroup(of: (Int, LocalTrack).self) { group in
            var nextIndex = 0

            for _ in 0..<concurrencyLimit {
                let index = nextIndex
                nextIndex += 1
                let url = discoveredURLs[index]
                group.addTask {
                    (index, await LocalLibrary.parseAsset(at: url))
                }
            }

            while let result = await group.next() {
                discovered.append(result.1)

                if nextIndex < discoveredURLs.count {
                    let index = nextIndex
                    nextIndex += 1
                    let url = discoveredURLs[index]
                    group.addTask {
                        (index, await LocalLibrary.parseAsset(at: url))
                    }
                }
            }
        }

        discovered.sort {
            $0.title
                .localizedCaseInsensitiveCompare(
                    $1.title
                )
                ==
                .orderedAscending
        }

        return discovered
    }

    nonisolated
    private static func parseAsset(
        at url:
            URL
    ) async -> LocalTrack {

        let asset =
            AVURLAsset(
                url: url,
                options: [
                    AVURLAssetPreferPreciseDurationAndTimingKey: false
                ]
            )

        async let durationValue = asset.load(.duration)
        async let metadataValue = asset.load(.metadata)

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

        var artworkData:
            Data?

        for item in metadata {

            let key =
                item.commonKey?
                    .rawValue
                ??
                (item.key as? String)
                ??
                ""

            if [
                "title",
                "TIT2",
                "©nam"
            ].contains(key) {

                if let value =
                    try? await item
                        .load(
                            .stringValue
                        ),
                   !value
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )
                    .isEmpty {

                    title =
                        value
                }

            } else if [
                "artist",
                "TPE1",
                "TPE2",
                "©ART",
                "aART"
            ].contains(key) {

                if let value =
                    try? await item
                        .load(
                            .stringValue
                        ),
                   !value
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )
                    .isEmpty {

                    artist =
                        value
                }

            } else if [
                "albumName",
                "album",
                "TALB",
                "©alb"
            ].contains(key) {

                if let value =
                    try? await item
                        .load(
                            .stringValue
                        ),
                   !value
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )
                    .isEmpty {

                    album =
                        value
                }

            } else if [
                "type",
                "genre",
                "TCON",
                "©gen"
            ].contains(key) {

                if let value =
                    try? await item
                        .load(
                            .stringValue
                        ),
                   !value
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )
                    .isEmpty {

                    genre =
                        value
                }

            } else if [
                "artwork",
                "APIC",
                "covr"
            ].contains(key) {

                if let data =
                    try? await item
                        .load(
                            .dataValue
                        ) {

                    artworkData =
                        data

                } else if let value =
                    try? await item
                        .load(
                            .value
                        ),
                          let data =
                            value as? Data {

                    artworkData =
                        data
                }
            }
        }

        return LocalTrack(
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
                artworkData
        )
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