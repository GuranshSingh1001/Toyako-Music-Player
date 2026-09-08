import Foundation
import SwiftUI
import AVFoundation

@MainActor
class LocalLibrary: ObservableObject {
    @Published var tracks: [LocalTrack] = []
    @Published var albums: [AlbumGroup] = []
    @Published var artists: [ArtistGroup] = []
    @Published var playlists: [Playlist] = []
    @Published var statusMessage: String = "Scanning..."

    private var playlistsCacheURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("playlists_cache.json")
    }
    private var tracksCacheURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("tracks_cache.json")
    }

    init() {
        loadPlaylists()
        loadTracksFromCache()
        reloadFiles()
    }

    // MARK: - Scanning & Parsing
    func reloadFiles() {
        if tracks.isEmpty { statusMessage = "Scanning..." }
        
        Task {
            // Await the heavy lifting from the background thread helper
            let discovered = await runBackgroundScan()
            self.tracks = discovered
            self.rebuildGroups()
            self.statusMessage = "Indexed \(discovered.count) songs"
            self.saveTracksToCache()
        }
    }
    
    // Completely nonisolated to satisfy Swift 6 strict concurrency
    nonisolated private func runBackgroundScan() async -> [LocalTrack] {
        let fileManager = FileManager.default
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }

        let audioExts = Set(["mp3", "m4a", "wav", "flac", "aac", "aiff", "alac"])
        var discoveredURLs: [URL] = []

        if let enumerator = fileManager.enumerator(
            at: docs,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            while let fileURL = enumerator.nextObject() as? URL {
                if audioExts.contains(fileURL.pathExtension.lowercased()) {
                    discoveredURLs.append(fileURL)
                }
            }
        }

        var discovered: [LocalTrack] = []
        for fileURL in discoveredURLs {
            discovered.append(await parseAsset(at: fileURL))
        }

        discovered.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return discovered
    }

    nonisolated private func parseAsset(at url: URL) async -> LocalTrack {
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

            if keyString == "title" || keyString == "TIT2" || keyString == "©nam" {
                if let str = try? await item.load(.stringValue), !str.trimmingCharacters(in: .whitespaces).isEmpty { title = str }
            } else if keyString == "artist" || keyString == "TPE1" || keyString == "TPE2" || keyString == "©ART" || keyString == "aART" {
                if let str = try? await item.load(.stringValue), !str.trimmingCharacters(in: .whitespaces).isEmpty { artist = str }
            } else if keyString == "albumName" || keyString == "album" || keyString == "TALB" || keyString == "©alb" {
                if let str = try? await item.load(.stringValue), !str.trimmingCharacters(in: .whitespaces).isEmpty { album = str }
            } else if keyString == "type" || keyString == "genre" || keyString == "TCON" || keyString == "©gen" {
                if let str = try? await item.load(.stringValue), !str.trimmingCharacters(in: .whitespaces).isEmpty { genre = str }
            } else if keyString == "artwork" || keyString == "APIC" || keyString == "covr" {
                if let data = try? await item.load(.dataValue) { artworkData = data }
                else if let rawVal = try? await item.load(.value), let d = rawVal as? Data { artworkData = d }
            }
        }

        return LocalTrack(url: url, title: title, artist: artist, album: album, genre: genre, duration: duration, artworkData: artworkData)
    }

    private func rebuildGroups() {
        let albumDict = Dictionary(grouping: tracks, by: {
            "\($0.album.trimmingCharacters(in: .whitespaces).lowercased())_\($0.artist.trimmingCharacters(in: .whitespaces).lowercased())"
        })
        self.albums = albumDict.map { _, trackList in
            let preferredName = trackList.first(where: { $0.album != "Unknown Album" })?.album ?? "Unknown Album"
            let preferredArtist = trackList.first(where: { $0.artist != "Unknown Artist" })?.artist ?? "Unknown Artist"
            return AlbumGroup(name: preferredName, artist: preferredArtist, artworkData: trackList.first(where: { $0.artworkData != nil })?.artworkData, tracks: trackList)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let artistDict = Dictionary(grouping: tracks, by: {
            $0.artist.trimmingCharacters(in: .whitespaces).lowercased()
        })
        self.artists = artistDict.map { _, trackList in
            let preferredArtist = trackList.first(where: { $0.artist != "Unknown Artist" })?.artist ?? "Unknown Artist"
            return ArtistGroup(name: preferredArtist, tracks: trackList)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - File Importing
    func importExternalURLs(_ urls: [URL]) {
        Task {
            await performImport(urls: urls)
            self.reloadFiles()
        }
    }
    
    nonisolated private func performImport(urls: [URL]) async {
        let fileManager = FileManager.default
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

        for url in urls {
            let hasAccess = url.startAccessingSecurityScopedResource()
            let dest = docs.appendingPathComponent(url.lastPathComponent)
            
            if !fileManager.fileExists(atPath: dest.path) {
                try? fileManager.copyItem(at: url, to: dest)
            }
            if hasAccess { url.stopAccessingSecurityScopedResource() }
        }
    }

    // MARK: - Playlist Management
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

    func renamePlaylist(id: UUID, newName: String) {
        if let idx = playlists.firstIndex(where: { $0.id == id }) {
            playlists[idx].name = newName
            savePlaylists()
        }
    }

    private func savePlaylists() {
        if let encoded = try? JSONEncoder().encode(playlists) {
            try? encoded.write(to: playlistsCacheURL)
        }
    }

    private func loadPlaylists() {
        if let data = try? Data(contentsOf: playlistsCacheURL),
           let decoded = try? JSONDecoder().decode([Playlist].self, from: data) {
            playlists = decoded
        }
    }

    // MARK: - Persistent Library Caching
    private func saveTracksToCache() {
        let currentTracks = self.tracks
        let cacheURL = self.tracksCacheURL
        DispatchQueue.global(qos: .background).async {
            if let encoded = try? JSONEncoder().encode(currentTracks) {
                try? encoded.write(to: cacheURL)
            }
        }
    }

    private func loadTracksFromCache() {
        if let data = try? Data(contentsOf: tracksCacheURL),
           let decoded = try? JSONDecoder().decode([LocalTrack].self, from: data) {
            self.tracks = decoded
            self.rebuildGroups()
            self.statusMessage = "Indexed \(decoded.count) songs"
        }
    }
}
