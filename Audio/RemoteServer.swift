import Foundation
import AVFoundation
import Network
import UIKit
import Combine
import Darwin

extension Notification.Name {
    static let toyakoRemoteSystemVolume = Notification.Name("Toyako.RemoteSystemVolume")
}

/// Local-network remote control server for Toyako.
///
/// The iPad remains the playback source of truth. The browser receives the
/// current track, artwork, queue, lyrics and playback position and can send
/// playback commands back to the iPad.
final class RemoteServer: ObservableObject {
    enum PlaybackTarget: String { case ipad, web }

    @Published private(set) var isRunning = false
    @Published private(set) var address: String?
    @Published private(set) var port: UInt16 = 0
    @Published private(set) var lastError: String?
    @Published private(set) var playbackTarget: PlaybackTarget = .ipad
    @Published private(set) var remoteWebPosition: TimeInterval = 0
    @Published private(set) var remoteWebPlaying = false

    private var listener: NWListener?
    private weak var audioManager: AudioEngineManager?
    private let queue = DispatchQueue(label: "com.toyako.remote-server")
    // Keep the remote on one stable port so toggling it off/on does not change the URL.
    private let fixedPort: UInt16 = 8787
    private let enabledKey = "Toyako.RemoteServerEnabled"

    func attach(to manager: AudioEngineManager) {
        audioManager = manager
    }

    func autoStartIfEnabled() {
        guard UserDefaults.standard.bool(forKey: enabledKey) else { return }
        start()
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        if enabled {
            start()
        } else {
            stop()
        }
    }

    func start() {
        guard listener == nil else { return }
        lastError = nil

        do {
            guard let endpointPort = NWEndpoint.Port(rawValue: fixedPort) else {
                lastError = "Invalid remote port."
                return
            }
            let listener = try NWListener(using: .tcp, on: endpointPort)
            listener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        self?.port = listener.port?.rawValue ?? 0
                        self?.address = self?.localIPv4Address()
                        self?.lastError = nil
                    case .failed(let error):
                        self?.isRunning = false
                        self?.lastError = self?.friendlyNetworkError(error) ?? error.localizedDescription
                        self?.listener?.cancel()
                        self?.listener = nil
                    case .cancelled:
                        self?.isRunning = false
                        self?.port = 0
                    default:
                        break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }

            self.listener = listener
            listener.start(queue: queue)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        address = nil
        port = 0
    }

    private func friendlyNetworkError(_ error: Error) -> String {
        let nsError = error as NSError
        // NWError.posix(EACCES) and local-network privacy failures are surfaced
        // as opaque errors such as "-65555: NoAuth" on iPadOS.
        let description = error.localizedDescription
        if description.localizedCaseInsensitiveContains("NoAuth") ||
            description.localizedCaseInsensitiveContains("permission") ||
            nsError.code == -65555 {
            return "Local Network access is disabled. Enable Settings > Privacy & Security > Local Network > Toyako, then turn Remote Control on again."
        }
        return description
    }

    func toggle() {
        if isRunning { stop() } else { start() }
    }

    func handoffToWeb() {
        guard let manager = audioManager, manager.currentTrack != nil else { return }
        DispatchQueue.main.async {
            self.remoteWebPosition = manager.currentTime
            self.remoteWebPlaying = manager.isPlaying
            self.playbackTarget = .web
            manager.pauseFromRemote()
        }
    }

    func handoffToIPad(position: TimeInterval, playing: Bool) {
        guard let manager = audioManager, manager.currentTrack != nil else { return }
        DispatchQueue.main.async {
            manager.seek(to: position)
            self.remoteWebPosition = position
            self.remoteWebPlaying = playing
            self.playbackTarget = .ipad
            if playing { manager.playFromRemote() } else { manager.pauseFromRemote() }
        }
    }

    func togglePlayback() {
        if playbackTarget == .web {
            remoteWebPlaying.toggle()
        } else {
            audioManager?.togglePlayPause()
        }
    }

    func previousPlayback() {
        guard let manager = audioManager else { return }
        let wasWebPlaying = remoteWebPlaying
        manager.backward()
        if playbackTarget == .web {
            manager.pauseFromRemote()
            remoteWebPosition = manager.currentTime
            remoteWebPlaying = wasWebPlaying
        }
    }

    func nextPlayback() {
        guard let manager = audioManager else { return }
        let wasWebPlaying = remoteWebPlaying
        manager.forward()
        if playbackTarget == .web {
            manager.pauseFromRemote()
            remoteWebPosition = 0
            remoteWebPlaying = wasWebPlaying
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection else { return }
            if case .ready = state {
                self?.receiveRequest(from: connection)
            }
        }
        connection.start(queue: queue)
    }

    private func receiveRequest(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            if let error {
                self.sendError(connection, status: 400, message: error.localizedDescription)
                return
            }

            guard let data, let request = String(data: data, encoding: .utf8) else {
                if isComplete { self.sendError(connection, status: 400, message: "Invalid request") }
                return
            }

            // A browser request is normally contained in one TCP read. If the
            // headers/body are split, wait for the next chunk.
            if !request.contains("\r\n\r\n") && !isComplete {
                self.receiveRequest(from: connection)
                return
            }

            self.handleHTTP(request, connection: connection)
        }
    }

    private func handleHTTP(_ request: String, connection: NWConnection) {
        let parts = request.components(separatedBy: "\r\n\r\n")
        let header = parts.first ?? ""
        let body = parts.dropFirst().joined(separator: "\r\n\r\n")
        let requestLine = header.components(separatedBy: "\r\n").first ?? ""
        let tokens = requestLine.split(separator: " ")
        guard tokens.count >= 2 else {
            sendError(connection, status: 400, message: "Bad request")
            return
        }

        let method = String(tokens[0]).uppercased()
        let rawPath = String(tokens[1])
        let path = rawPath.components(separatedBy: "?").first ?? rawPath

        switch (method, path) {
        case ("GET", "/"):
            send(connection, status: 200, contentType: "text/html; charset=utf-8", body: Self.html)
        case ("GET", "/manifest.json"):
            send(connection, status: 200, contentType: "application/manifest+json; charset=utf-8", body: Self.manifest)
        case ("GET", "/sw.js"):
            send(connection, status: 200, contentType: "application/javascript; charset=utf-8", body: Self.serviceWorker)
        case ("GET", "/icon-192.png"):
            sendWebIcon(connection, resource: "WebIcon-192", status: 200)
        case ("GET", "/icon-512.png"):
            sendWebIcon(connection, resource: "WebIcon-512", status: 200)
        case ("GET", "/api/state"):
            sendJSON(connection, object: statePayload())
        case ("GET", "/api/media"):
            handleMediaRequest(rawPath: rawPath, request: request, connection: connection)
        case ("GET", "/api/artwork"):
            let requestedID = rawPath.components(separatedBy: "?").dropFirst().joined(separator: "?")
                .split(separator: "&").reduce(into: [String: String]()) { result, item in
                    let pair = item.split(separator: "=", maxSplits: 1).map(String.init)
                    if pair.count == 2 { result[pair[0]] = pair[1].removingPercentEncoding ?? pair[1] }
                }["id"]
            guard let manager = audioManager else {
                sendError(connection, status: 404, message: "No artwork")
                return
            }
            let candidates = manager.originalQueue + manager.queue + [manager.currentTrack].compactMap { $0 }
            guard let track = requestedID.flatMap({ id in candidates.first(where: { $0.id.uuidString == id }) }) ?? manager.currentTrack else {
                sendError(connection, status: 404, message: "No artwork")
                return
            }
            Task {
                var artwork = track.artworkData
                if artwork == nil {
                    artwork = await ArtworkStore.shared.data(for: track.url)
                }
                guard let artwork else {
                    self.sendError(connection, status: 404, message: "No artwork")
                    return
                }
                self.send(connection, status: 200, contentType: "image/jpeg", bodyData: self.normalizedJPEGData(artwork))
            }
        case ("POST", "/api/command"):
            handleCommand(body, connection: connection)
        case ("POST", "/api/settings"):
            handleSettings(body, connection: connection)
        default:
            sendError(connection, status: 404, message: "Not found")
        }
    }

    private func handleCommand(_ body: String, connection: NWConnection) {
        guard
            let data = body.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let command = object["command"] as? String,
            let manager = audioManager
        else {
            sendError(connection, status: 400, message: "Invalid command")
            return
        }

        DispatchQueue.main.async {
            switch command {
            case "play":
                if self.playbackTarget == .web { self.remoteWebPlaying = true } else { manager.playFromRemote() }
            case "pause":
                if self.playbackTarget == .web { self.remoteWebPlaying = false } else { manager.pauseFromRemote() }
            case "toggle":
                if self.playbackTarget == .web { self.remoteWebPlaying.toggle() } else { manager.togglePlayPause() }
            case "next":
                let wasWebPlaying = self.playbackTarget == .web ? self.remoteWebPlaying : false
                manager.forward()
                if self.playbackTarget == .web {
                    manager.pauseFromRemote()
                    self.remoteWebPosition = 0
                    self.remoteWebPlaying = wasWebPlaying
                }
            case "previous":
                let wasWebPlaying = self.playbackTarget == .web ? self.remoteWebPlaying : false
                manager.backward()
                if self.playbackTarget == .web {
                    manager.pauseFromRemote()
                    self.remoteWebPosition = manager.currentTime
                    self.remoteWebPlaying = wasWebPlaying
                }
            case "playLibrary":
                if let id = object["id"] as? String {
                    let pool = manager.originalQueue.isEmpty ? manager.queue : manager.originalQueue
                    if let index = pool.firstIndex(where: { $0.id.uuidString == id }) {
                        manager.startQueue(tracks: pool, startIndex: index)
                    }
                }
            case "playQueue":
                if let index = object["index"] as? Int {
                    let wasWebPlaying = self.playbackTarget == .web ? self.remoteWebPlaying : false
                    manager.playQueuedTrack(at: index)
                    if self.playbackTarget == .web {
                        manager.pauseFromRemote()
                        self.remoteWebPosition = 0
                        self.remoteWebPlaying = wasWebPlaying
                    }
                }
            case "seek":
                if let position = object["position"] as? Double {
                    if self.playbackTarget == .web { self.remoteWebPosition = max(0, position) }
                    else { manager.seek(to: position) }
                }
            case "handoffToWeb":
                self.playbackTarget = .web
                self.remoteWebPosition = manager.currentTime
                self.remoteWebPlaying = manager.isPlaying
                manager.pauseFromRemote()
            case "handoffToIPad":
                let position = (object["position"] as? Double) ?? self.remoteWebPosition
                let shouldPlay = (object["playing"] as? Bool) ?? self.remoteWebPlaying
                self.remoteWebPosition = position
                self.remoteWebPlaying = shouldPlay
                manager.seek(to: position)
                self.playbackTarget = .ipad
                if shouldPlay { manager.playFromRemote() } else { manager.pauseFromRemote() }
            case "remoteSync":
                if self.playbackTarget == .web {
                    if let position = object["position"] as? Double { self.remoteWebPosition = max(0, position) }
                    if let playing = object["playing"] as? Bool { self.remoteWebPlaying = playing }
                }
            case "volume":
                if let value = object["value"] as? Double {
                    // The Now Playing slider controls the iPad's actual output
                    // volume, not AVPlayer's per-player attenuation. Forward
                    // the request to the same MPVolumeView bridge used by the
                    // native Now Playing screen.
                    NotificationCenter.default.post(
                        name: .toyakoRemoteSystemVolume,
                        object: nil,
                        userInfo: ["value": Float(value)]
                    )
                }
            case "shuffle":
                if let value = object["value"] as? Bool, value != manager.isShuffle { manager.toggleShuffle() }
            case "repeat":
                if let value = object["value"] as? String, let mode = RepeatMode(rawValue: value), mode != manager.repeatMode {
                    manager.cycleRepeatMode(to: mode)
                }
            default:
                break
            }
        }
        sendJSON(connection, object: ["ok": true])
    }

    private func handleSettings(_ body: String, connection: NWConnection) {
        guard
            let data = body.data(using: .utf8),
            let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            sendError(connection, status: 400, message: "Invalid settings")
            return
        }

        let defaults = UserDefaults.standard
        let boolKeys = [
            ToyakoPreferences.showRomanizationKey,
            ToyakoPreferences.karaokeGlowKey,
            ToyakoPreferences.translationKey,
            ToyakoPreferences.showAudioInfoKey,
            ToyakoPreferences.bleedingEffectKey
        ]
        for key in boolKeys {
            if let value = values[key] as? Bool { defaults.set(value, forKey: key) }
        }
        if let value = values[ToyakoPreferences.lyricsFontScaleKey] as? Double {
            defaults.set(value, forKey: ToyakoPreferences.lyricsFontScaleKey)
        }
        if let value = values[ToyakoPreferences.lyricsLineSpacingKey] as? Double {
            defaults.set(value, forKey: ToyakoPreferences.lyricsLineSpacingKey)
        }
        if let value = values[ToyakoPreferences.lyricsAnimationStyleKey] as? String {
            defaults.set(value, forKey: ToyakoPreferences.lyricsAnimationStyleKey)
        }

        sendJSON(connection, object: ["ok": true])
    }

    private func handleMediaRequest(rawPath: String, request: String, connection: NWConnection) {
        guard let manager = audioManager, let track = manager.currentTrack else {
            sendError(connection, status: 404, message: "No track")
            return
        }

        let query = rawPath.components(separatedBy: "?").dropFirst().joined(separator: "?")
        let params = query.split(separator: "&").reduce(into: [String: String]()) { result, item in
            let pair = item.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { result[pair[0]] = pair[1].removingPercentEncoding ?? pair[1] }
        }
        if let requestedID = params["id"], requestedID != track.id.uuidString {
            sendError(connection, status: 404, message: "Track is no longer current")
            return
        }

        guard let handle = try? FileHandle(forReadingFrom: track.url) else {
            sendError(connection, status: 404, message: "Media file unavailable")
            return
        }
        defer { try? handle.close() }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: track.url.path),
              let fileSize = attributes[.size] as? NSNumber else {
            sendError(connection, status: 404, message: "Media file unavailable")
            return
        }
        let total = Int64(fileSize.int64Value)
        let rangeHeader = headerValue(in: request, name: "Range")
        var start: Int64 = 0
        var end: Int64 = max(0, total - 1)
        var status = 200
        if let rangeHeader, rangeHeader.hasPrefix("bytes=") {
            let value = String(rangeHeader.dropFirst(6)).split(separator: "-", maxSplits: 1).map(String.init)
            if let first = Int64(value.first ?? ""), first >= 0 {
                start = first
                if value.count > 1, let requestedEnd = Int64(value[1]), requestedEnd >= start { end = min(requestedEnd, total - 1) }
                else { end = total - 1 }
                status = 206
            }
        }
        guard total > 0, start < total, start <= end else {
            let header = "HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */\(total)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(header.utf8), completion: .contentProcessed { _ in connection.cancel() })
            return
        }

        let length = Int(end - start + 1)
        do {
            try handle.seek(toOffset: UInt64(start))
            let data = try handle.read(upToCount: length) ?? Data()
            let contentType = Self.mimeType(for: track.url.pathExtension)
            let reason = status == 206 ? "Partial Content" : "OK"
            var header = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(data.count)\r\nAccept-Ranges: bytes\r\nCache-Control: no-store\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n"
            if status == 206 { header += "Content-Range: bytes \(start)-\(start + Int64(data.count) - 1)/\(total)\r\n" }
            header += "\r\n"
            connection.send(content: Data(header.utf8) + data, completion: .contentProcessed { _ in connection.cancel() })
        } catch {
            sendError(connection, status: 500, message: "Could not read media")
        }
    }

    private func headerValue(in request: String, name: String) -> String? {
        for line in request.components(separatedBy: "\r\n").dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(name) == .orderedSame {
                return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "mp3": return "audio/mpeg"
        case "m4a", "mp4": return "audio/mp4"
        case "aac": return "audio/aac"
        case "wav": return "audio/wav"
        case "aiff", "aif": return "audio/aiff"
        case "flac": return "audio/flac"
        case "caf": return "audio/x-caf"
        case "opus": return "audio/ogg"
        case "ogg": return "audio/ogg"
        default: return "application/octet-stream"
        }
    }

    private func statePayload() -> [String: Any] {
        guard let manager = audioManager else { return ["available": false] }
        let track = manager.currentTrack
        let lyrics = manager.currentLyrics.map { line -> [String: Any] in
            var value: [String: Any] = [
                "time": line.time,
                "endTime": line.endTime,
                "text": line.text
            ]
            if let romanized = line.romanized { value["romanized"] = romanized }
            if !line.words.isEmpty {
                value["words"] = line.words.map { word in
                    [
                        "text": word.text,
                        "startTime": word.startTime,
                        "endTime": word.endTime,
                        "units": word.units.map { unit in
                            ["text": unit.text, "startTime": unit.startTime, "endTime": unit.endTime, "romanized": unit.romanized as Any]
                        }
                    ] as [String: Any]
                }
            }
            return value
        }

        let queue = manager.queue.map { item in
            ["id": item.id.uuidString, "title": item.title, "artist": item.artist, "album": item.album]
        }

        let defaults = UserDefaults.standard
        return [
            "available": true,
            "playing": playbackTarget == .web ? remoteWebPlaying : manager.isPlaying,
            "position": playbackTarget == .web ? remoteWebPosition : manager.currentTime,
            "duration": track?.duration ?? 0,
            "playbackTarget": playbackTarget.rawValue,
            "playbackDeviceName": playbackTarget == .web ? "Web Remote" : currentNativeOutputName(),
            "volume": AVAudioSession.sharedInstance().outputVolume,
            "shuffle": manager.isShuffle,
            "repeat": manager.repeatMode.rawValue,
            "track": [
                "id": track?.id.uuidString ?? "",
                "title": track?.title ?? "Nothing Playing",
                "artist": track?.artist ?? "",
                "album": track?.album ?? "",
                "audioInfo": track.flatMap { audioFormatSummary(for: $0) } ?? "",
                "artworkURL": track == nil ? NSNull() : "/api/artwork"
            ],
            "queue": queue,
            "library": manager.originalQueue.isEmpty ? queue : manager.originalQueue.map { item in
                [
                    "id": item.id.uuidString,
                    "title": item.title,
                    "artist": item.artist,
                    "album": item.album,
                    "duration": item.duration,
                    "artworkURL": "/api/artwork?id=\(item.id.uuidString)"
                ] as [String: Any]
            },
            "lyrics": lyrics,
            "lyricsSource": manager.selectedLyricsSourceID as Any,
            "settings": [
                ToyakoPreferences.showRomanizationKey: defaults.bool(forKey: ToyakoPreferences.showRomanizationKey),
                ToyakoPreferences.karaokeGlowKey: defaults.bool(forKey: ToyakoPreferences.karaokeGlowKey),
                ToyakoPreferences.translationKey: defaults.bool(forKey: ToyakoPreferences.translationKey),
                ToyakoPreferences.showAudioInfoKey: defaults.bool(forKey: ToyakoPreferences.showAudioInfoKey),
                ToyakoPreferences.bleedingEffectKey: defaults.bool(forKey: ToyakoPreferences.bleedingEffectKey),
                ToyakoPreferences.lyricsFontScaleKey: defaults.double(forKey: ToyakoPreferences.lyricsFontScaleKey),
                ToyakoPreferences.lyricsLineSpacingKey: defaults.double(forKey: ToyakoPreferences.lyricsLineSpacingKey),
                ToyakoPreferences.lyricsAnimationStyleKey: defaults.string(forKey: ToyakoPreferences.lyricsAnimationStyleKey) ?? LyricsAnimationStyle.dynamic.rawValue
            ]
        ]
    }

    private func currentNativeOutputName() -> String {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        return outputs.first?.portName ?? "This iPad"
    }

    private func audioFormatSummary(for track: LocalTrack) -> String? {
        guard let file = try? AVAudioFile(forReading: track.url) else { return nil }
        let format = file.fileFormat
        guard format.sampleRate > 0 else { return nil }
        let extensionName = track.url.pathExtension.uppercased()
        let sampleRate = String(format: "%.1f kHz", format.sampleRate / 1000.0)
        let channels = format.channelCount > 1 ? "Stereo" : "Mono"
        return [extensionName, sampleRate, channels].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func sendWebIcon(_ connection: NWConnection, resource: String, status: Int) {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "png"),
              let data = try? Data(contentsOf: url) else {
            sendError(connection, status: 404, message: "Icon not found")
            return
        }
        send(connection, status: status, contentType: "image/png", bodyData: data)
    }

    private func sendJSON(_ connection: NWConnection, object: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: []) else {
            sendError(connection, status: 500, message: "Could not encode response")
            return
        }
        send(connection, status: 200, contentType: "application/json; charset=utf-8", bodyData: data)
    }

    private func sendError(_ connection: NWConnection, status: Int, message: String) {
        sendJSONStatus(connection, status: status, object: ["error": message])
    }

    private func sendJSONStatus(_ connection: NWConnection, status: Int, object: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: []) else {
            connection.cancel(); return
        }
        send(connection, status: status, contentType: "application/json; charset=utf-8", bodyData: data)
    }

    private func send(_ connection: NWConnection, status: Int, contentType: String, body: String) {
        send(connection, status: status, contentType: contentType, bodyData: Data(body.utf8))
    }

    private func send(_ connection: NWConnection, status: Int, contentType: String, bodyData: Data) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 404: reason = "Not Found"
        default: reason = "Server Error"
        }
        let header = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(bodyData.count)\r\nCache-Control: no-store\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + bodyData, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func normalizedJPEGData(_ data: Data) -> Data {
        guard let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.88) else { return data }
        return jpeg
    }

    private func localIPv4Address() -> String? {
        var address: String?
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
        defer { freeifaddrs(interfaces) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let flags = Int32(interface.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let addr = interface.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                address = String(cString: host)
                break
            }
        }
        return address
    }

    static let html = #"""
<!doctype html>
<html lang="en">
<head>
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#000000">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<title>Toyako</title>
<style>
:root{color-scheme:dark;--bg:#000;--panel:rgba(255,255,255,.065);--panel2:rgba(255,255,255,.09);--text:#fff;--secondary:rgba(255,255,255,.62);--tertiary:rgba(255,255,255,.38);--accent:#fff;--line:rgba(255,255,255,.12);--radius:18px}
*{box-sizing:border-box}html,body{margin:0;width:100%;height:100%;background:var(--bg);color:var(--text);font-family:-apple-system,BlinkMacSystemFont,"SF Pro Display","SF Pro Text",system-ui,sans-serif;-webkit-font-smoothing:antialiased;-webkit-text-size-adjust:100%;touch-action:manipulation}body{overflow:hidden}button,input{font:inherit}button{color:inherit;border:0;background:none;-webkit-tap-highlight-color:transparent}
.app{height:100dvh;display:grid;grid-template-columns:250px minmax(0,1fr);background:#000}.sidebar{padding:24px 14px 18px;display:flex;flex-direction:column;border-right:1px solid var(--line);background:rgba(10,10,10,.92);backdrop-filter:blur(28px)}.brand{display:flex;align-items:center;gap:11px;padding:4px 10px 25px;font-size:22px;font-weight:760;letter-spacing:-.04em}.brand img{width:30px;height:30px;border-radius:8px}.nav{display:flex;flex-direction:column;gap:5px}.nav button{height:46px;border-radius:12px;display:flex;align-items:center;gap:13px;padding:0 14px;color:var(--secondary);font-weight:600;text-align:left;cursor:pointer}.nav button.active{background:rgba(255,255,255,.11);color:#fff}.nav svg{width:21px;height:21px;stroke:currentColor;fill:none;stroke-width:1.9;stroke-linecap:round;stroke-linejoin:round}.sidebar-spacer{flex:1}.settings{display:flex;align-items:center;gap:13px;padding:12px 14px;color:var(--secondary);cursor:pointer}.content{min-width:0;min-height:0;display:flex;flex-direction:column;position:relative;overflow:hidden}.topbar{height:64px;display:flex;align-items:center;justify-content:space-between;padding:0 28px;flex:0 0 auto}.top-title{font-size:29px;font-weight:760;letter-spacing:-.04em}.top-actions{display:flex;gap:7px}.circle{width:40px;height:40px;border-radius:50%;background:var(--panel);display:grid;place-items:center;cursor:pointer}.circle:active,.play:active,.nav button:active,.card:active{transform:scale(.96)}.circle svg{width:20px;height:20px;fill:none;stroke:currentColor;stroke-width:1.9;stroke-linecap:round;stroke-linejoin:round}
.page{flex:1;min-height:0;overflow:auto;padding:8px 28px 150px}.page::-webkit-scrollbar{display:none}.hero{border-radius:24px;min-height:210px;padding:28px;background:linear-gradient(135deg,rgba(255,255,255,.13),rgba(255,255,255,.035));border:1px solid var(--line);display:flex;align-items:flex-end;margin-bottom:30px}.hero h1{font-size:clamp(32px,4vw,52px);line-height:1;margin:0 0 9px;letter-spacing:-.055em}.hero p{margin:0;color:var(--secondary);font-size:16px}.actions{display:flex;gap:10px;margin-top:20px}.pill{padding:10px 16px;border-radius:999px;background:#fff;color:#000;font-weight:700;cursor:pointer}.pill.secondary{background:rgba(255,255,255,.1);color:#fff;border:1px solid var(--line)}.section{margin:0 0 32px}.section-head{display:flex;align-items:center;justify-content:space-between;margin:0 0 13px}.section-title{font-size:22px;font-weight:720;letter-spacing:-.025em}.section-more{font-size:14px;color:var(--secondary);cursor:pointer}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:16px}.card{min-width:0;padding:12px;border-radius:var(--radius);background:var(--panel);border:1px solid rgba(255,255,255,.07);cursor:pointer;text-align:left}.art{width:100%;aspect-ratio:1;border-radius:12px;object-fit:cover;background:rgba(255,255,255,.06);display:block}.fallback{width:100%;aspect-ratio:1;border-radius:12px;background:rgba(255,255,255,.06);display:grid;place-items:center;color:var(--tertiary);font-size:38px}.card-title{font-size:14px;font-weight:650;margin-top:9px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.card-sub{font-size:12px;color:var(--secondary);margin-top:3px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.list{display:flex;flex-direction:column;gap:7px}.row{display:grid;grid-template-columns:52px minmax(0,1fr) auto;gap:13px;align-items:center;padding:8px 10px;border-radius:13px;cursor:pointer}.row:hover{background:rgba(255,255,255,.055)}.row-art{width:52px;height:52px;border-radius:9px;object-fit:cover;background:rgba(255,255,255,.06)}.row-main{min-width:0}.row-title{font-size:15px;font-weight:620;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.row-sub{font-size:13px;color:var(--secondary);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-top:3px}.row-tail{color:var(--tertiary);font-size:12px}.empty{padding:50px 20px;text-align:center;color:var(--secondary)}
.mini{position:absolute;left:22px;right:22px;bottom:16px;height:76px;border-radius:20px;background:rgba(27,27,27,.86);border:1px solid var(--line);backdrop-filter:blur(30px);box-shadow:0 18px 55px rgba(0,0,0,.42);display:grid;grid-template-columns:minmax(170px,1fr) minmax(260px,1.2fr) minmax(170px,1fr);align-items:center;padding:8px 12px;z-index:30}.mini-track{display:flex;align-items:center;gap:10px;min-width:0}.mini-art{width:58px;height:58px;border-radius:11px;object-fit:cover;background:rgba(255,255,255,.06)}.mini-text{min-width:0}.mini-title{font-size:14px;font-weight:650;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.mini-artist{font-size:12px;color:var(--secondary);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-top:2px}.mini-controls{display:flex;align-items:center;justify-content:center;gap:8px}.mini-controls .circle{background:transparent}.play{width:48px;height:48px;border-radius:50%;background:#fff;color:#000;display:grid;place-items:center;cursor:pointer}.play svg{width:21px;height:21px;fill:currentColor}.mini-extra{display:flex;justify-content:flex-end;align-items:center;gap:7px}.progress{position:absolute;left:16px;right:16px;bottom:0;height:2px;background:rgba(255,255,255,.16);border-radius:999px;overflow:hidden}.progress i{display:block;height:100%;background:#fff;width:0}
.mobile-nav{display:none}.now-playing{position:fixed;inset:0;background:#000;z-index:100;display:none;overflow:auto}.now-playing.open{display:block}.np-inner{min-height:100%;padding:18px 24px 35px;display:flex;flex-direction:column}.np-top{display:flex;justify-content:space-between;align-items:center}.np-title{font-size:16px;font-weight:650}.np-art{width:min(76vw,560px);aspect-ratio:1;margin:clamp(28px,7vh,70px) auto 24px;border-radius:22px;object-fit:cover;box-shadow:0 25px 70px rgba(0,0,0,.45);background:rgba(255,255,255,.06)}.np-info{width:min(760px,100%);margin:0 auto}.np-song{font-size:clamp(24px,4vw,34px);font-weight:760;letter-spacing:-.04em;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.np-artist{font-size:17px;color:var(--secondary);margin-top:5px}.seek{width:100%;margin-top:25px}.range{width:100%;accent-color:#fff}.times{display:flex;justify-content:space-between;color:var(--secondary);font-size:12px;margin-top:5px}.np-controls{display:flex;justify-content:center;align-items:center;gap:20px;margin-top:24px}.np-controls .circle{background:transparent;width:46px;height:46px}.np-controls .play{width:60px;height:60px}.np-volume{display:flex;gap:10px;align-items:center;margin-top:25px}.np-volume svg{width:20px;height:20px;fill:#fff}.lyrics{margin:30px auto 0;width:min(760px,100%);color:var(--secondary);line-height:1.5;text-align:center}.lyric.active{color:#fff;font-size:22px;font-weight:700}.lyric{padding:7px 0}
@media(max-width:900px){.app{display:block}.sidebar{display:none}.content{height:100dvh}.topbar{padding:0 18px}.top-title{font-size:25px}.page{padding:5px 18px 170px}.mini{left:12px;right:12px;bottom:70px;height:68px;grid-template-columns:1fr auto;padding:6px 9px;border-radius:18px}.mini-track{min-width:0}.mini-art{width:54px;height:54px}.mini-controls{gap:1px}.mini-controls .optional{display:none}.mini-extra{display:none}.mobile-nav{position:absolute;display:flex;left:12px;right:12px;bottom:8px;height:56px;border-radius:18px;background:rgba(24,24,24,.9);border:1px solid var(--line);backdrop-filter:blur(28px);z-index:40;justify-content:space-around;padding:4px}.mobile-nav button{flex:1;color:var(--secondary);font-size:10px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:2px;border-radius:13px}.mobile-nav button.active{color:#fff;background:rgba(255,255,255,.1)}.mobile-nav svg{width:19px;height:19px;fill:none;stroke:currentColor;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round}.grid{grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}.hero{min-height:180px;padding:22px;border-radius:20px}.section-title{font-size:20px}.np-art{width:min(82vw,420px);margin-top:35px}}
@media(min-width:901px){.page{padding-bottom:125px}}
</style>
</head>
<body>
<div class="app">
<aside class="sidebar">
  <div class="brand"><img src="/icon-192.png" alt="">Toyako</div>
  <nav class="nav">
    <button data-page="home" class="active" onclick="go('home')"><svg viewBox="0 0 24 24"><path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1V10Z"/></svg>Home</button>
    <button data-page="tracks" onclick="go('tracks')"><svg viewBox="0 0 24 24"><path d="M9 18V5l11-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="17" cy="16" r="3"/></svg>Tracks</button>
    <button data-page="albums" onclick="go('albums')"><svg viewBox="0 0 24 24"><rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="12" cy="12" r="4"/></svg>Albums</button>
    <button data-page="artists" onclick="go('artists')"><svg viewBox="0 0 24 24"><circle cx="12" cy="8" r="3"/><path d="M5 21a7 7 0 0 1 14 0"/></svg>Artists</button>
    <button data-page="playlists" onclick="go('playlists')"><svg viewBox="0 0 24 24"><rect x="3" y="3" width="18" height="18" rx="3"/><path d="M7 8h10M7 12h10M7 16h6"/></svg>Playlists</button>
  </nav>
  <div class="sidebar-spacer"></div><div class="settings" onclick="alert('Settings are managed on the iPad.')"><span>⚙</span>Settings</div>
</aside>
<main class="content">
  <header class="topbar"><div class="top-title" id="pageTitle">Home</div><div class="top-actions"><button class="circle" onclick="refresh()" aria-label="Refresh"><svg viewBox="0 0 24 24"><path d="M20 11a8 8 0 0 0-14.9-3M4 5v4h4M4 13a8 8 0 0 0 14.9 3M20 19v-4h-4"/></svg></button><button class="circle" onclick="openNowPlaying()" aria-label="Now Playing"><svg viewBox="0 0 24 24"><path d="M6 3h12v18H6z"/><path d="M9 7h6M9 11h6M9 15h4"/></svg></button></div></header>
  <section class="page" id="page"></section>
  <div class="mini" onclick="openNowPlaying()">
    <div class="mini-track"><img class="mini-art" id="miniArt" src="" alt=""><div class="mini-text"><div class="mini-title" id="miniTitle">Nothing Playing</div><div class="mini-artist" id="miniArtist"></div></div></div>
    <div class="mini-controls"><button class="circle optional" onclick="event.stopPropagation();cmd('previous')"><svg viewBox="0 0 24 24"><path d="M6 5v14h2V5H6Zm3 7 9 7V5l-9 7Z" fill="currentColor"/></svg></button><button class="play" id="miniPlay" onclick="event.stopPropagation();cmd('toggle')"><svg viewBox="0 0 24 24"><path id="miniPlayPath" d="M8 5v14l11-7L8 5Z"/></svg></button><button class="circle optional" onclick="event.stopPropagation();cmd('next')"><svg viewBox="0 0 24 24"><path d="M16 5v14h2V5h-2Zm-1 7L6 5v14l9-7Z" fill="currentColor"/></svg></button></div>
    <div class="mini-extra"><button class="circle" onclick="event.stopPropagation();cmd('toggle')"><svg viewBox="0 0 24 24"><path d="M4 9v6h4l5 4V5L8 9H4Z"/><path d="M16 8.5a5 5 0 0 1 0 7M18.5 6a8.5 8.5 0 0 1 0 12"/></svg></button></div><div class="progress"><i id="miniProgress"></i></div>
  </div>
  <nav class="mobile-nav">
    <button data-page="home" class="active" onclick="go('home')"><svg viewBox="0 0 24 24"><path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1V10Z"/></svg>Home</button>
    <button data-page="tracks" onclick="go('tracks')"><svg viewBox="0 0 24 24"><path d="M9 18V5l11-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="17" cy="16" r="3"/></svg>Tracks</button>
    <button data-page="albums" onclick="go('albums')"><svg viewBox="0 0 24 24"><rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="12" cy="12" r="4"/></svg>Albums</button>
    <button data-page="artists" onclick="go('artists')"><svg viewBox="0 0 24 24"><circle cx="12" cy="8" r="3"/><path d="M5 21a7 7 0 0 1 14 0"/></svg>Artists</button>
    <button data-page="playlists" onclick="go('playlists')"><svg viewBox="0 0 24 24"><rect x="3" y="3" width="18" height="18" rx="3"/><path d="M7 8h10M7 12h10M7 16h6"/></svg>Playlists</button>
  </nav>
</main></div>
<div class="now-playing" id="nowPlaying"><div class="np-inner"><div class="np-top"><button class="circle" onclick="closeNowPlaying()"><svg viewBox="0 0 24 24"><path d="m6 6 12 12M18 6 6 18"/></svg></button><div class="np-title">Now Playing</div><button class="circle" onclick="cmd('toggle')"><svg viewBox="0 0 24 24"><path d="M6 3h12v18H6z"/></svg></button></div><img class="np-art" id="npArt" src="" alt=""><div class="np-info"><div class="np-song" id="npTitle">Nothing Playing</div><div class="np-artist" id="npArtist"></div><div class="seek"><input id="seek" class="range" type="range" min="0" max="1" value="0" step="0.01"><div class="times"><span id="elapsed">0:00</span><span id="remaining">-0:00</span></div></div><div class="np-controls"><button class="circle" onclick="cmd('shuffle')"><svg viewBox="0 0 24 24"><path d="M16 3h5v5M20 4l-5 5M4 5h3a4 4 0 0 1 3.3 1.7l4.4 6.6A4 4 0 0 0 18 15h3M4 19h3a4 4 0 0 0 3.3-1.7l1.2-1.8M20 20l-4-4"/></svg></button><button class="circle" onclick="cmd('previous')"><svg viewBox="0 0 24 24"><path d="M6 5v14h2V5H6Zm3 7 9 7V5l-9 7Z" fill="currentColor"/></svg></button><button class="play" id="npPlay" onclick="cmd('toggle')"><svg viewBox="0 0 24 24"><path id="npPlayPath" d="M8 5v14l11-7L8 5Z"/></svg></button><button class="circle" onclick="cmd('next')"><svg viewBox="0 0 24 24"><path d="M16 5v14h2V5h-2Zm-1 7L6 5v14l9-7Z" fill="currentColor"/></svg></button><button class="circle" onclick="cmd('repeat')"><svg viewBox="0 0 24 24"><path d="M7 7h10V4l4 4-4 4V9H7a3 3 0 0 0-3 3M17 17H7v3l-4-4 4-4v3h10a3 3 0 0 0 3-3"/></svg></button></div><div class="np-volume"><svg viewBox="0 0 24 24"><path d="M4 9v6h4l5 4V5L8 9H4Z"/><path d="M16 8.5a5 5 0 0 1 0 7M18.5 6a8.5 8.5 0 0 1 0 12" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg><input id="volume" class="range" type="range" min="0" max="1" value="1" step="0.01"><svg viewBox="0 0 24 24"><path d="M4 9v6h4l5 4V5L8 9H4Z"/><path d="M16 8.5a5 5 0 0 1 0 7M18.5 6a8.5 8.5 0 0 1 0 12" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg></div><div class="lyrics" id="lyrics"></div></div></div></div>
<script>
let state=null,page='home',localPosition=0,lastTick=Date.now();
const $=id=>document.getElementById(id); const esc=s=>String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
const fmt=s=>{s=Math.max(0,Math.floor(s||0));return `${Math.floor(s/60)}:${String(s%60).padStart(2,'0')}`};
async function api(path,options={}){const r=await fetch(path,{cache:'no-store',...options});if(!r.ok)throw new Error(await r.text());return r.json()}
async function cmd(command,extra={}){try{await api('/api/command',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({command,...extra})});await refresh()}catch(e){console.error(e)}}
function art(url){return url?`<img class="art" src="${url}" loading="lazy" onerror="this.style.display='none';this.nextElementSibling.style.display='grid'">`:'<img class="art" style="display:none"><div class="fallback">♪</div>'}
function trackArt(t,cls=''){if(!t?.artworkURL)return `<div class="${cls||'fallback'}">♪</div>`;return `<img class="${cls||'art'}" src="${t.artworkURL}" loading="lazy" onerror="this.replaceWith(Object.assign(document.createElement('div'),{className:'fallback',textContent:'♪'}))">`}
function go(p){page=p;renderPage()}
function setNav(){document.querySelectorAll('[data-page]').forEach(b=>b.classList.toggle('active',b.dataset.page===page));$('pageTitle').textContent=page[0].toUpperCase()+page.slice(1)}
function tracks(){return state?.library?.length?state.library:(state?.queue||[])}
function albums(){const m=new Map();tracks().forEach(t=>{const k=t.album||'Unknown Album';if(!m.has(k))m.set(k,{name:k,artist:t.artist,track:t})});return [...m.values()]}
function artists(){const m=new Map();tracks().forEach(t=>{const k=t.artist||'Unknown Artist';if(!m.has(k))m.set(k,{name:k,track:t})});return [...m.values()]}
function card(t,onclick){return `<button class="card" onclick="${onclick}">${trackArt(t)}<div class="card-title">${esc(t.title||t.name)}</div><div class="card-sub">${esc(t.artist||'')}</div></button>`}
function trackRows(items){if(!items.length)return '<div class="empty">Your library is empty.</div>';return `<div class="list">${items.map((t,i)=>`<button class="row" onclick="cmd('playLibrary',{id:'${t.id}'})">${trackArt(t,'row-art')}<div class="row-main"><div class="row-title">${esc(t.title)}</div><div class="row-sub">${esc(t.artist)}${t.album?' · '+esc(t.album):''}</div></div><div class="row-tail">${fmt(t.duration)}</div></button>`).join('')}</div>`}
function renderPage(){setNav();const ts=tracks(),as=albums(),ars=artists();let h='';if(page==='home'){h=`<div class="hero"><div><h1>Your Library</h1><p>${ts.length?`${ts.length} ${ts.length===1?'track':'tracks'} ready to play offline.`:'Import music on your iPad to start building your offline library.'}</p><div class="actions"><button class="pill" onclick="${ts.length?'cmd(\'playLibrary\',{id:\''+(ts[0]?.id||'')+'\'})':'alert(\'Import music on the iPad first.\')'}">${ts.length?'Play':'Import Audio'}</button><button class="pill secondary" onclick="${ts.length?'shuffleAll()':'go(\'tracks\')'}">${ts.length?'Shuffle All':'Browse Tracks'}</button></div></div></div>`;if(ts.length)h+=`<div class="section"><div class="section-head"><div class="section-title">Recently Added</div><button class="section-more" onclick="go('tracks')">See All</button></div><div class="grid">${ts.slice(0,8).map(t=>card(t,`cmd('playLibrary',{id:'${t.id}'})`)).join('')}</div></div>`;if(as.length)h+=`<div class="section"><div class="section-head"><div class="section-title">Albums</div><button class="section-more" onclick="go('albums')">See All</button></div><div class="grid">${as.slice(0,8).map(a=>card({...a.track,title:a.name},`goAlbum('${esc(a.name)}')`)).join('')}</div></div>`;if(ars.length)h+=`<div class="section"><div class="section-head"><div class="section-title">Artists</div><button class="section-more" onclick="go('artists')">See All</button></div><div class="grid">${ars.slice(0,8).map(a=>card({...a.track,title:a.name,artist:''},`goArtist('${esc(a.name)}')`)).join('')}</div></div>`}else if(page==='tracks'){h=trackRows(ts)}else if(page==='albums'){h=as.length?`<div class="grid">${as.map(a=>card({...a.track,title:a.name},`goAlbum('${esc(a.name)}')`)).join('')}</div>`:'<div class="empty">No albums yet.</div>'}else if(page==='artists'){h=ars.length?`<div class="grid">${ars.map(a=>card({...a.track,title:a.name,artist:''},`goArtist('${esc(a.name)}')`)).join('')}</div>`:'<div class="empty">No artists yet.</div>'}else{h='<div class="empty">Playlists are managed on the iPad in this controller-only remote.</div>'}$('page').innerHTML=h}
function goAlbum(name){const items=tracks().filter(t=>(t.album||'Unknown Album')===name);$('pageTitle').textContent=name;$('page').innerHTML=`<div class="section"><div class="section-head"><div class="section-title">${esc(name)}</div><button class="section-more" onclick="go('albums')">Albums</button></div>${trackRows(items)}</div>`}
function goArtist(name){const items=tracks().filter(t=>(t.artist||'Unknown Artist')===name);$('pageTitle').textContent=name;$('page').innerHTML=`<div class="section"><div class="section-head"><div class="section-title">${esc(name)}</div><button class="section-more" onclick="go('artists')">Artists</button></div>${trackRows(items)}</div>`}
function shuffleAll(){const ts=tracks();if(ts.length)cmd('playLibrary',{id:ts[Math.floor(Math.random()*ts.length)].id})}
function renderState(){const t=state?.track||{};$('miniTitle').textContent=t.title||'Nothing Playing';$('miniArtist').textContent=t.artist||'';$('npTitle').textContent=t.title||'Nothing Playing';$('npArtist').textContent=t.artist||'';['miniArt','npArt'].forEach(id=>{const el=$(id);el.src=t.artworkURL||'';el.style.display=t.artworkURL?'block':'none'});const path=state?.playing?'M7 5h4v14H7V5Zm6 0h4v14h-4V5Z':'M8 5v14l11-7L8 5Z';$('miniPlayPath').setAttribute('d',path);$('npPlayPath').setAttribute('d',path);localPosition=state?.position||0;$('seek').max=state?.duration||1;$('seek').value=localPosition;$('elapsed').textContent=fmt(localPosition);$('remaining').textContent='-'+fmt(Math.max(0,(state?.duration||0)-localPosition));$('volume').value=state?.volume??1;const pct=state?.duration?Math.min(100,(localPosition/state.duration)*100):0;$('miniProgress').style.width=pct+'%';$('lyrics').innerHTML=(state?.lyrics||[]).map(l=>`<div class="lyric ${l.time<=localPosition&&(!state.lyrics[l.lyricsIndex+1]||localPosition<state.lyrics[l.lyricsIndex+1]?.time)?'active':''}">${esc(l.text)}</div>`).join('');}
function openNowPlaying(){ $('nowPlaying').classList.add('open'); renderState() }function closeNowPlaying(){$('nowPlaying').classList.remove('open')}
$('seek').addEventListener('input',e=>{localPosition=Number(e.target.value);$('elapsed').textContent=fmt(localPosition);$('remaining').textContent='-'+fmt(Math.max(0,(state?.duration||0)-localPosition))});$('seek').addEventListener('change',e=>cmd('seek',{position:Number(e.target.value)}));$('volume').addEventListener('change',e=>cmd('volume',{value:Number(e.target.value)}));
async function refresh(){try{state=await api('/api/state');renderState();renderPage()}catch(e){console.error(e)}}
setInterval(()=>{if(state?.playing){localPosition=Math.min(state.duration||0,localPosition+0.5);renderState()}},500);refresh();
</script></body></html>
"""
    static let manifest = #"""
{
  "name": "Toyako Remote",
  "short_name": "Toyako",
  "description": "Remote control for the Toyako music player",
  "start_url": "/",
  "scope": "/",
  "display": "standalone",
  "background_color": "#08090b",
  "theme_color": "#0b0d10",
  "orientation": "any",
  "prefer_related_applications": false,
  "icons": [
    {"src":"/icon-192.png","sizes":"192x192","type":"image/png","purpose":"any maskable"},
    {"src":"/icon-512.png","sizes":"512x512","type":"image/png","purpose":"any maskable"}
  ]
}
"""#

    static let serviceWorker = #"""
const CACHE = 'toyako-remote-v1';
const APP_SHELL = ['/', '/manifest.json', '/icon-192.png', '/icon-512.png'];

self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(APP_SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys => Promise.all(keys.filter(key => key !== CACHE).map(key => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  if (url.pathname.startsWith('/api/')) return;
  event.respondWith(
    caches.match(event.request).then(cached => cached || fetch(event.request).then(response => {
      const copy = response.clone();
      caches.open(CACHE).then(cache => cache.put(event.request, copy));
      return response;
    }))
  );
});
"""#

}
