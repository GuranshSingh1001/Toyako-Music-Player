import Foundation
import UIKit

struct LocalTrack: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let title: String
    let artist: String
    let album: String
    let genre: String
    let duration: TimeInterval
    let artworkData: Data?

    init(id: UUID = UUID(), url: URL, title: String, artist: String = "Unknown Artist", album: String = "Unknown Album", genre: String = "Unknown Genre", duration: TimeInterval = 0.0, artworkData: Data? = nil) {
        self.id = id
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.genre = genre
        self.duration = duration
        self.artworkData = artworkData
    }
}

struct AlbumGroup: Identifiable, Hashable {
    var id: String { "\(name)_\(artist)" }
    let name: String
    let artist: String
    let artworkData: Data?
    let tracks: [LocalTrack]
}

struct ArtistGroup: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let tracks: [LocalTrack]
}

struct Playlist: Identifiable, Codable {
    let id: UUID
    var name: String
    var trackURLs: [URL]

    init(id: UUID = UUID(), name: String, trackURLs: [URL] = []) {
        self.id = id
        self.name = name
        self.trackURLs = trackURLs
    }
}

struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    let time: TimeInterval
    let text: String
}
