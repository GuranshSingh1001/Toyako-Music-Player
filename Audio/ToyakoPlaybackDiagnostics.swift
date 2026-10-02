import Foundation
import OSLog

/// Persistent playback diagnostics intended to survive an app crash.
///
/// The most recent playback events are written synchronously to Documents so
/// the final breadcrumbs are much less likely to be lost when the process dies.
final class ToyakoPlaybackDiagnostics {
    static let shared = ToyakoPlaybackDiagnostics()

    private let lock = NSLock()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Toyako",
        category: "Playback"
    )

    private init() {
        installExceptionHandler()
        log("=== DIAGNOSTICS_SESSION_START app=\(Bundle.main.bundleIdentifier ?? "unknown") version=\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown") build=\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown") ===")
    }

    private var logURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ToyakoPlayback.log")
    }

    func log(_ message: String) {
        let line = "\(Self.timestamp()) [main=\(Thread.isMainThread)] \(message)\n"
        logger.info("\(message, privacy: .public)")

        // This is deliberately synchronous. Playback only emits a small
        // number of diagnostic events; losing the final event on a crash is
        // much more harmful than the tiny I/O cost of the breadcrumb.
        lock.lock()
        defer { lock.unlock() }

        do {
            let data = Data(line.utf8)
            if !FileManager.default.fileExists(atPath: logURL.path) {
                try data.write(to: logURL, options: [.atomic])
            } else {
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.synchronize()
                try handle.close()
            }
            trimIfNeeded()
        } catch {
            // Diagnostics must never change app behavior.
        }
    }

    func clear() {
        lock.lock()
        try? FileManager.default.removeItem(at: logURL)
        lock.unlock()
        log("=== DIAGNOSTICS_CLEARED ===")
    }

    private func trimIfNeeded() {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: logURL.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > 4_000_000 else { return }

        if let data = try? Data(contentsOf: logURL) {
            let tail = data.suffix(2_000_000)
            try? tail.write(to: logURL, options: [.atomic])
        }
    }

    private func installExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            ToyakoPlaybackDiagnostics.shared.log(
                "UNCAUGHT_EXCEPTION name=\(exception.name.rawValue) reason=\(exception.reason ?? "nil") stack=\(exception.callStackSymbols.joined(separator: " || "))"
            )
        }
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
