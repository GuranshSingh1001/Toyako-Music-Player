import Foundation
import OSLog

/// Lightweight persistent playback diagnostics.
///
/// The log is intentionally written to the app's Documents directory so it
/// can be retrieved from the iOS Files app. This captures the last playback
/// transitions even when the app terminates before a UI can display an error.
final class ToyakoPlaybackDiagnostics {
    static let shared = ToyakoPlaybackDiagnostics()

    private let queue = DispatchQueue(label: "com.toyako.playback-diagnostics")
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Toyako",
        category: "Playback"
    )

    private init() {}

    private var logURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ToyakoPlayback.log")
    }

    func log(_ message: String) {
        logger.info("\(message, privacy: .public)")

        let line = "\(Self.timestamp()) \(message)\n"
        queue.async { [logURL] in
            do {
                if !FileManager.default.fileExists(atPath: logURL.path) {
                    try Data(line.utf8).write(to: logURL, options: [.atomic])
                    return
                }

                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
                try handle.close()

                // Keep the file bounded so long-running playback does not
                // consume unbounded app storage.
                if let attributes = try? FileManager.default.attributesOfItem(atPath: logURL.path),
                   let size = attributes[.size] as? NSNumber,
                   size.intValue > 2_000_000 {
                    let data = try Data(contentsOf: logURL)
                    let tail = data.suffix(1_000_000)
                    try tail.write(to: logURL, options: [.atomic])
                }
            } catch {
                // Logging must never affect playback.
            }
        }
    }

    func clear() {
        queue.async { [logURL] in
            try? FileManager.default.removeItem(at: logURL)
        }
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
