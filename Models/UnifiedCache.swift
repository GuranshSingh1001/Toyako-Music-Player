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
    private static let backupFilename = "ToyakoCache.bin.bak"
    private static let lock = NSRecursiveLock()

    static var url: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
    }

    private static var backupURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(backupFilename)
    }

    private static let playbackFilename = "ToyakoPlayback.bin"
    private static let playbackBackupFilename = "ToyakoPlayback.bin.bak"

    private static var playbackURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(playbackFilename)
    }

    private static var playbackBackupURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(playbackBackupFilename)
    }

    static func loadPlaybackState() -> ToyakoPlaybackState? {
        lock.lock()
        defer { lock.unlock() }

        if let data = try? Data(contentsOf: playbackURL),
           let state = try? binaryDecoder.decode(ToyakoPlaybackState.self, from: data) {
            return state
        }

        guard let data = try? Data(contentsOf: playbackBackupURL),
              let state = try? binaryDecoder.decode(ToyakoPlaybackState.self, from: data) else {
            return nil
        }

        try? data.write(to: playbackURL, options: .atomic)
        return state
    }

    static func savePlaybackState(_ state: ToyakoPlaybackState) {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? binaryEncoder.encode(state) else { return }

        if let existingData = try? Data(contentsOf: playbackURL) {
            try? existingData.write(to: playbackBackupURL, options: .atomic)
        }
        try? data.write(to: playbackURL, options: .atomic)
    }

    static func load() -> ToyakoCacheEnvelope? {
        lock.lock()
        defer { lock.unlock() }

        if let envelope = loadUnlocked() {
            return envelope
        }

        // A failed decode must never be treated as an empty cache. Recover the
        // previous known-good snapshot instead of allowing the next write to
        // silently erase playlists, history, and playback metadata.
        guard FileManager.default.fileExists(atPath: url.path),
              let backup = loadBackupUnlocked() else {
            return nil
        }

        restoreBackupUnlocked()
        return backup
    }

    /// Atomically updates one or more sections of the single cache file.
    /// The lock prevents playback saves and library saves from overwriting each
    /// other when they happen close together. A corrupt existing cache is never
    /// replaced by a new empty envelope; the backup is used when available.
    static func update(_ mutate: (inout ToyakoCacheEnvelope) -> Void) {
        lock.lock()
        defer { lock.unlock() }

        let fileManager = FileManager.default
        let existingData = try? Data(contentsOf: url)
        let existingEnvelope = existingData.flatMap {
            try? binaryDecoder.decode(ToyakoCacheEnvelope.self, from: $0)
        }

        var envelope: ToyakoCacheEnvelope
        if let existingEnvelope {
            envelope = existingEnvelope
        } else if fileManager.fileExists(atPath: url.path),
                  let backup = loadBackupUnlocked() {
            envelope = backup
            restoreBackupUnlocked()
        } else if fileManager.fileExists(atPath: url.path) {
            // The file exists but neither it nor its backup can be decoded.
            // Do not write an empty envelope over it; that would turn a
            // recoverable failure into permanent data loss.
            return
        } else {
            envelope = ToyakoCacheEnvelope()
        }

        mutate(&envelope)
        envelope.version = ToyakoCacheEnvelope.currentVersion

        guard let data = try? binaryEncoder.encode(envelope) else { return }

        // Preserve the last known-good snapshot before replacing the live file.
        if let existingData {
            try? existingData.write(to: backupURL, options: .atomic)
        }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
    }

    static func replace(_ envelope: ToyakoCacheEnvelope) {
        lock.lock()
        defer { lock.unlock() }

        guard let data = try? binaryEncoder.encode(envelope) else { return }
        let existingData = try? Data(contentsOf: url)
        if let existingData {
            try? existingData.write(to: backupURL, options: .atomic)
        }
        try? data.write(to: url, options: .atomic)
    }

    private static func loadUnlocked() -> ToyakoCacheEnvelope? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? binaryDecoder.decode(ToyakoCacheEnvelope.self, from: data)
    }

    private static func loadBackupUnlocked() -> ToyakoCacheEnvelope? {
        guard let data = try? Data(contentsOf: backupURL) else { return nil }
        return try? binaryDecoder.decode(ToyakoCacheEnvelope.self, from: data)
    }

    private static func restoreBackupUnlocked() {
        guard let data = try? Data(contentsOf: backupURL) else { return }
        try? data.write(to: url, options: .atomic)
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
