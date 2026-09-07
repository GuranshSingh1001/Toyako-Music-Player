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
        let fileManager = FileManager.default
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            statusMessage = "Unable to access Documents folder"
            return
        }

        let audioExts = Set(["mp3", "m4a", "wav", "flac", "aac", "aiff", "alac"])
        var discovered: [LocalTrack] = []

        if let enumerator = fileManager.enumerator(
            at: docs,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let fileURL as URL in enumerator {
                if audioExts.contains(fileURL.pathExtension.lowercased()) {
                    let track = parseAsset(at: fileURL)
                    discovered.append(track)
                }
            }
        }

        discovered.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        tracks = discovered

        let albumDict = Dictionary(grouping: discovered, by: { "\($0.album)_\($0.artist)" })
        albums = albumDict.map { _, trackList in
            AlbumGroup(
                name: trackList.first?.album ?? "Unknown Album",
                artist: trackList.first?.artist ?? "Unknown Artist",
                artworkData: trackList.first?.artworkData,
                tracks: trackList
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let artistDict = Dictionary(grouping: discovered, by: { $0.artist })
        artists = artistDict.map { artistName, trackList in
            ArtistGroup(name: artistName, tracks: trackList)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        statusMessage = "Indexed \(discovered.count) songs"
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

    private func parseAsset(at url: URL) -> LocalTrack {
        let asset = AVURLAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)

        var title = url.deletingPathExtension().lastPathComponent
        var artist = "Unknown Artist"
        var album = "Unknown Album"
        var genre = "Unknown Genre"
        var artworkData: Data?

        for item in asset.commonMetadata {
            guard let key = item.commonKey?.rawValue else { continue }
            switch key {
            case "title":
                title = (item.value as? String) ?? title
            case "artist":
                artist = (item.value as? String) ?? artist
            case "albumName":
                album = (item.value as? String) ?? album
            case "type":
                genre = (item.value as? String) ?? genre
            case "artwork":
                if let data = item.dataValue {
                    artworkData = data
                }
            default:
                break
            }
        }

        return LocalTrack(
            url: url,
            title: title,
            artist: artist,
            album: album,
            genre: genre,
            duration: duration.isNaN ? 0.0 : duration,
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
