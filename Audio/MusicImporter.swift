import Foundation
import AVFoundation

@MainActor
class LocalLibrary: ObservableObject {
    @Published var tracks: [LocalTrack] = []
    @Published var albums: [AlbumGroup] = []
    @Published var artists: [ArtistGroup] = []
    @Published var playlists: [Playlist] = []
    @Published var statusMessage: String = "Scanning..."

    private let playlistStorageKey = "offline_music_playlists"

    init() {
        loadPlaylists()
    }

    func reloadFiles() {
        Task {
            statusMessage = "Scanning..."
            let fileManager = FileManager.default
            guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                statusMessage = "Unable to access Documents folder"
                return
            }

            let audioExts = Set(["mp3", "m4a", "wav", "flac", "aac", "aiff", "alac"])
            var discoveredURLs: [URL] = []

            if let enumerator = fileManager.enumerator(
                at: docs,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) {
                for case let fileURL as URL in enumerator {
                    if audioExts.contains(fileURL.pathExtension.lowercased()) {
                        discoveredURLs.append(fileURL)
                    }
                }
            }

            var discovered: [LocalTrack] = []
            for fileURL in discoveredURLs {
                let track = await parseAsset(at: fileURL)
                discovered.append(track)
            }

            discovered.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            self.tracks = discovered

            let albumDict = Dictionary(grouping: discovered, by: { "\($0.album)_\($0.artist)" })
            self.albums = albumDict.map { _, trackList in
                AlbumGroup(
                    name: trackList.first?.album ?? "Unknown Album",
                    artist: trackList.first?.artist ?? "Unknown Artist",
                    artworkData: trackList.first(where: { $0.artworkData != nil })?.artworkData,
                    tracks: trackList
                )
            }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            let artistDict = Dictionary(grouping: discovered, by: { $0.artist })
            self.artists = artistDict.map { artistName, trackList in
                ArtistGroup(name: artistName, tracks: trackList)
            }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            self.statusMessage = "Indexed \(discovered.count) songs"
        }
    }

    func importExternalURLs(_ urls: [URL]) {
        let fileManager = FileManager.default
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

        for url in urls {
            let hasAccess = url.startAccessingSecurityScopedResource()
            let dest = docs.appendingPathComponent(url.lastPathComponent)
            try? fileManager.removeItem(at: dest)
            try? fileManager.copyItem(at: url, to: dest)
            if hasAccess { url.stopAccessingSecurityScopedResource() }
        }
        reloadFiles()
    }

    private func parseAsset(at url: URL) async -> LocalTrack {
        let asset = AVURLAsset(url: url)

        let durationSeconds = (try? await asset.load(.duration).seconds) ?? 0.0
        let duration = durationSeconds.isNaN ? 0.0 : durationSeconds
        let allMetadata = (try? await asset.load(.metadata)) ?? []

        var title = url.deletingPathExtension().lastPathComponent
        var artist = "Unknown Artist"
        var album = "Unknown Album"
        var genre = "Unknown Genre"
        var artworkData: Data?

        for item in allMetadata {
            let keyString = item.commonKey?.rawValue ?? (item.key as? String) ?? ""

            // Title: common, ID3 (TIT2), iTunes (©nam)
            if keyString == "title" || keyString == "TIT2" || keyString == "©nam" {
                if let str = try? await item.load(.stringValue), !str.trimmingCharacters(in: .whitespaces).isEmpty {
                    title = str
                }
            }
            // Artist: common, ID3 (TPE1, TPE2), iTunes (©ART, aART)
            else if keyString == "artist" || keyString == "TPE1" || keyString == "TPE2" || keyString == "©ART" || keyString == "aART" {
                if let str = try? await item.load(.stringValue), !str.trimmingCharacters(in: .whitespaces).isEmpty {
                    artist = str
                }
            }
            // Album: common, ID3 (TALB), iTunes (©alb)
            else if keyString == "albumName" || keyString == "album" || keyString == "TALB" || keyString == "©alb" {
                if let str = try? await item.load(.stringValue), !str.trimmingCharacters(in: .whitespaces).isEmpty {
                    album = str
                }
            }
            // Genre: common, ID3 (TCON), iTunes (©gen)
            else if keyString == "type" || keyString == "genre" || keyString == "TCON" || keyString == "©gen" {
                if let str = try? await item.load(.stringValue), !str.trimmingCharacters(in: .whitespaces).isEmpty {
                    genre = str
                }
            }
            // Artwork: common, ID3 (APIC), iTunes (covr)
            else if keyString == "artwork" || keyString == "APIC" || keyString == "covr" {
                if let data = try? await item.load(.dataValue) {
                    artworkData = data
                } else if let rawVal = try? await item.load(.value) {
                    if let d = rawVal as? Data {
                        artworkData = d
                    } else if let dict = rawVal as? [String: Any], let d = dict["data"] as? Data {
                        artworkData = d
                    }
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

    func createPlaylist(name: String) {
        let newPlaylist = Playlist(name: name, trackURLs: [])
        playlists.append(newPlaylist)
        savePlaylists()
    }

    func addTracksToPlaylist(playlistID: UUID, trackURLs: [URL]) {
        if let idx = playlists.firstIndex(where: { $0.id == playlistID }) {
            for url in trackURLs {
                if !playlists[idx].trackURLs.contains(url) {
                    playlists[idx].trackURLs.append(url)
                }
            }
            savePlaylists()
        }
    }

    func removeTrackFromPlaylist(playlistID: UUID, trackURL: URL) {
        if let idx = playlists.firstIndex(where: { $0.id == playlistID }) {
            playlists[idx].trackURLs.removeAll { $0 == trackURL }
            savePlaylists()
        }
    }

    private func savePlaylists() {
        if let encoded = try? JSONEncoder().encode(playlists) {
            UserDefaults.standard.set(encoded, forKey: playlistStorageKey)
        }
    }

    private func loadPlaylists() {
        if let data = UserDefaults.standard.data(forKey: playlistStorageKey),
           let decoded = try? JSONDecoder().decode([Playlist].self, from: data) {
            playlists = decoded
        }
    }
}