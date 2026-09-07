import SwiftData
import Foundation

@Model final class Track {
    @Attribute(.unique) var id: UUID
    var fileURL: URL
    var title: String
    var artistName: String
    var albumTitle: String
    var duration: TimeInterval
    var isFavorite: Bool
    var trackNumber: Int
    
    init(fileURL: URL, title: String, artistName: String, albumTitle: String, duration: TimeInterval, trackNumber: Int = 1) {
        self.id = UUID()
        self.fileURL = fileURL
        self.title = title
        self.artistName = artistName
        self.albumTitle = albumTitle
        self.duration = duration
        self.isFavorite = false
        self.trackNumber = trackNumber
    }
}

@Model final class Album {
    @Attribute(.unique) var id: UUID
    var title: String
    var artistName: String
    @Attribute(.externalStorage) var artworkData: Data?
    
    init(title: String, artistName: String, artworkData: Data? = nil) {
        self.id = UUID()
        self.title = title
        self.artistName = artistName
        self.artworkData = artworkData
    }
}

@Model final class Playlist {
    @Attribute(.unique) var id: UUID
    var name: String
    var items: [Track]
    
    init(name: String, items: [Track] = []) {
        self.id = UUID()
        self.name = name
        self.items = items
    }
}
