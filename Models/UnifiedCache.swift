import Foundation

/// Single persistent binary cache for Toyako's library metadata, playlists,
/// playback state, and recently-played history. Artwork bytes are intentionally
/// kept in the dedicated artwork cache so opening the library never decodes a
/// large image blob just to restore metadata.
struct ToyakoFileFingerprint: Codable, Equatable {
    let size: UInt64
    let modified: TimeInterval
}

struct ToyakoPlaybackState: Codable {
    let queue: [LocalTrack]
    let originalQueue: [LocalTrack]
    let queueIndex: Int
    let currentTrackID: UUID?
    let position: TimeInterval
    let isPlaying: Bool
    let isShuffle: Bool
    let repeatMode: RepeatMode
}

struct ToyakoCacheEnvelope: Codable {
    static let currentVersion = 3

    var version: Int = ToyakoCacheEnvelope.currentVersion
    var metadataParserVersion: Int = 0
    var tracks: [LocalTrack] = []
    var fingerprints: [String: ToyakoFileFingerprint] = [:]
    var playlists: [Playlist] = []
    var playbackState: ToyakoPlaybackState?
    var recentlyPlayed: [LocalTrack] = []
}

enum ToyakoUnifiedCache {
    private static let filename = "ToyakoCache.bin"
    private static let lock = NSLock()

    static var url: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
    }

    static func load() -> ToyakoCacheEnvelope? {
        lock.lock()
        defer { lock.unlock() }
        return loadUnlocked()
    }

    /// Atomically updates one or more sections of the single cache file.
    /// The lock prevents playback saves and library saves from overwriting each
    /// other when they happen close together.
    static func update(_ mutate: (inout ToyakoCacheEnvelope) -> Void) {
        lock.lock()
        defer { lock.unlock() }

        var envelope = loadUnlocked() ?? ToyakoCacheEnvelope()
        mutate(&envelope)
        envelope.version = ToyakoCacheEnvelope.currentVersion

        guard let data = try? binaryEncoder.encode(envelope) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func replace(_ envelope: ToyakoCacheEnvelope) {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? binaryEncoder.encode(envelope) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func loadUnlocked() -> ToyakoCacheEnvelope? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? binaryDecoder.decode(ToyakoCacheEnvelope.self, from: data)
    }

    private static var binaryEncoder: PropertyListEncoder {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }

    private static var binaryDecoder: PropertyListDecoder {
        PropertyListDecoder()
    }
}
