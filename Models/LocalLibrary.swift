import Foundation
import SwiftUI

class LocalLibrary: ObservableObject {
    @Published var tracks: [LocalTrack] = []
    @Published var playlists: [Playlist] = []
    @Published var albums: [AlbumGroup] = []
    @Published var artists: [ArtistGroup] = []

    private let tracksCacheKey = "CachedLibraryTracks"
    private let playlistsCacheKey = "CachedLibraryPlaylists"

    init() {
        // Load data instantly from local cache on startup
        loadFromCache()
        
        // Automatically trigger a silent background scan upon opening
        reloadFiles()
    }

    private func loadFromCache() {
        // 1. Load Tracks
        if let trackData = UserDefaults.standard.data(forKey: tracksCacheKey),
           let decodedTracks = try? JSONDecoder().decode([LocalTrack].self, from: trackData) {
            self.tracks = decodedTracks
            self.rebuildGroups()
        }

        // 2. Load Playlists
        if let playlistData = UserDefaults.standard.data(forKey: playlistsCacheKey),
           let decodedPlaylists = try? JSONDecoder().decode([Playlist].self, from: playlistData) {
            self.playlists = decodedPlaylists
        }
    }

    private func saveToCache() {
        if let encodedTracks = try? JSONEncoder().encode(tracks) {
            UserDefaults.standard.set(encodedTracks, forKey: tracksCacheKey)
        }
        if let encodedPlaylists = try? JSONEncoder().encode(playlists) {
            UserDefaults.standard.set(encodedPlaylists, forKey: playlistsCacheKey)
        }
    }

    /// Scans the file system for tracks in the background without blocking the UI
    func reloadFiles() {
        DispatchQueue.global(qos: .userInitiated).async {
            let scannedTracks = MusicImporter.importFiles() // Uses your existing importer logic

            DispatchQueue.main.async {
                self.tracks = scannedTracks
                self.rebuildGroups()
                self.saveToCache()
            }
        }
    }

    private func rebuildGroups() {
        // Group tracks by Album
        let groupedAlbums = Dictionary(grouping: tracks, by: { $0.album })
        self.albums = groupedAlbums.map { key, value in
            AlbumGroup(
                name: key,
                artist: value.first?.artist ?? "Unknown Artist",
                artworkData: value.first?.artworkData,
                tracks: value.sorted { $0.title < $1.title }
            )
        }.sorted { $0.name < $1.name }

        // Group tracks by Artist
        let groupedArtists = Dictionary(grouping: tracks, by: { $0.artist })
        self.artists = groupedArtists.map { key, value in
            ArtistGroup(
                name: key,
                tracks: value.sorted { $0.title < $1.title }
            )
        }.sorted { $0.name < $1.name }
    }

    // Playlist Management Methods
    func createPlaylist(name: String) {
        let newPlaylist = Playlist(name: name, trackURLs: [])
        playlists.append(newPlaylist)
        saveToCache()
    }

    func addTracksToPlaylist(playlistID: UUID, trackURLs: [URL]) {
        if let index = playlists.firstIndex(where: { $0.id == playlistID }) {
            playlists[index].trackURLs = trackURLs
            saveToCache()
        }
    }

    func removeTrackFromPlaylist(playlistID: UUID, trackURL: URL) {
        if let index = playlists.firstIndex(where: { $0.id == playlistID }) {
            playlists[index].trackURLs.removeAll { $0 == trackURL }
            saveToCache()
        }
    }
}
