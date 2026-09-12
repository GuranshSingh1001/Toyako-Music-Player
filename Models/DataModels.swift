import Foundation
import UIKit
import CoreFoundation

enum RepeatMode: String, CaseIterable, Codable {
    case off
    case all
    case one
}

struct LocalTrack: Identifiable, Hashable, Codable {
    let id: UUID
    let url: URL
    let title: String
    let artist: String
    let album: String
    let genre: String
    let duration: TimeInterval
    var artworkData: Data?

    // Explicitly omit artworkData from the JSON keys to keep the file size tiny
    enum CodingKeys: String, CodingKey {
        case id, url, title, artist, album, genre, duration
    }

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

    // Custom Decoder: Loads text instantly, leaves artwork blank until background scan finishes
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.url = try container.decode(URL.self, forKey: .url)
        self.title = try container.decode(String.self, forKey: .title)
        self.artist = try container.decode(String.self, forKey: .artist)
        self.album = try container.decode(String.self, forKey: .album)
        self.genre = try container.decode(String.self, forKey: .genre)
        self.duration = try container.decode(TimeInterval.self, forKey: .duration)
        self.artworkData = nil 
    }

    // Custom Encoder: Skips encoding the massive image data array into the JSON file
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        try container.encode(title, forKey: .title)
        try container.encode(artist, forKey: .artist)
        try container.encode(album, forKey: .album)
        try container.encode(genre, forKey: .genre)
        try container.encode(duration, forKey: .duration)
    }
}

struct AlbumGroup: Identifiable, Hashable {
    var id: String { "\(name)_\(artist)" }
    let name: String
    let artist: String
    let artworkURL: URL?
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
    let romanized: String?

    init(time: TimeInterval, text: String) {
        self.time = time
        self.text = text
        self.romanized = text.toJapaneseRomaji()
    }
}

extension String {
    func toJapaneseRomaji() -> String? {
        guard self.range(of: #"[一-龯ぁ-んァ-ヶ]"#, options: .regularExpression) != nil else {
            return nil
        }

        let sanitized = self
            .replacingOccurrences(of: "、", with: ", ")
            .replacingOccurrences(of: "。", with: ". ")
            .replacingOccurrences(of: "　", with: " ")

        let cfText = sanitized as CFString
        let length = CFStringGetLength(cfText)
        guard length > 0 else { return nil }

        let localeIdentifier = CFLocaleCreateCanonicalLanguageIdentifierFromString(kCFAllocatorDefault, "ja" as CFString)
        guard let locale = CFLocaleCreate(kCFAllocatorDefault, localeIdentifier),
              let tokenizer = CFStringTokenizerCreate(
                  kCFAllocatorDefault,
                  cfText,
                  CFRangeMake(0, length),
                  kCFStringTokenizerUnitWordBoundary,
                  locale
              ) else {
            return nil
        }

        var words: [String] = []
        var tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)

        while !tokenType.isEmpty {
            if let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String {
                let cleaned = latin.trimmingCharacters(in: CharacterSet.whitespaces)
                if !cleaned.isEmpty {
                    words.append(cleaned)
                }
            } else {
                let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
                let sub = (CFStringCreateWithSubstring(kCFAllocatorDefault, cfText, range) as String)
                    .trimmingCharacters(in: CharacterSet.whitespaces)
                if !sub.isEmpty {
                    words.append(sub)
                }
            }
            tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }

        var result = words.joined(separator: " ")
        result = result.replacingOccurrences(of: " ,", with: ",")
        result = result.replacingOccurrences(of: " .", with: ".")
        result = result.replacingOccurrences(of: " !", with: "!")
        result = result.replacingOccurrences(of: " ?", with: "?")
        result = result.replacingOccurrences(of: " )", with: ")")
        result = result.replacingOccurrences(of: "( ", with: "(")
        result = result.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        return (result.isEmpty || result == self) ? nil : result
    }
}
