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
            case "createPlaylist":
                if let name = object["name"] as? String {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        ToyakoUnifiedCache.update { cache in
                            cache.playlists.append(Playlist(name: trimmed))
                        }
                    }
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
        let cache = ToyakoUnifiedCache.load()
        let libraryTracks = manager.originalQueue.isEmpty ? manager.queue : manager.originalQueue
        let trackByPath = Dictionary(uniqueKeysWithValues: libraryTracks.map { ($0.url.standardizedFileURL.path, $0) })
        let playlistPayload: [[String: Any]] = (cache?.playlists ?? []).map { playlist in
            let resolved = playlist.trackURLs.compactMap { trackByPath[$0.standardizedFileURL.path] }
            let artworkURLs = Array(resolved.prefix(4)).map { "/api/artwork?id=\($0.id.uuidString)" }
            return [
                "id": playlist.id.uuidString,
                "name": playlist.name,
                "trackIDs": resolved.map { $0.id.uuidString },
                "trackCount": resolved.count,
                "duration": resolved.reduce(0) { $0 + $1.duration },
                "artworkURLs": artworkURLs
            ]
        }
        let recentPayload: [[String: Any]] = (cache?.recentlyPlayed ?? []).prefix(20).map { track in
            [
                "id": track.id.uuidString,
                "title": track.title,
                "artist": track.artist,
                "album": track.album,
                "duration": track.duration,
                "artworkURL": "/api/artwork?id=\(track.id.uuidString)"
            ]
        }
        return [
            "available": true,
            "playing": playbackTarget == .web ? remoteWebPlaying : manager.isPlaying,
            "position": playbackTarget == .web ? remoteWebPosition : manager.currentTime,
            "duration": track?.duration ?? 0,
            "playbackTarget": playbackTarget.rawValue,
            "playbackDeviceName": currentNativeOutputName(),
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
            "playlists": playlistPayload,
            "recentlyPlayed": recentPayload,
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
<meta name="theme-color" content="#0b1118">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<title>Toyako</title>
<style>
:root{color-scheme:dark;--bg:#090e14;--bg2:#050608;--panel:rgba(255,255,255,.085);--panel2:rgba(255,255,255,.12);--text:#fff;--secondary:rgba(255,255,255,.62);--tertiary:rgba(255,255,255,.4);--line:rgba(255,255,255,.12);--radius:22px}
*{box-sizing:border-box}html,body{margin:0;width:100%;height:100%;background:linear-gradient(180deg,#0c141d 0%,#07090c 62%,#030405 100%);color:var(--text);font-family:-apple-system,BlinkMacSystemFont,"SF Pro Display","SF Pro Text",system-ui,sans-serif;-webkit-font-smoothing:antialiased}button,input{font:inherit}button{border:0;color:inherit;background:none;cursor:pointer}.app{min-height:100dvh}.content{min-height:100dvh;overflow:auto}.page{padding:8px 28px 170px;max-width:1500px;margin:0 auto}.topbar{height:96px;display:grid;grid-template-columns:1fr auto 1fr;align-items:center;padding:0 16px;position:sticky;top:0;z-index:20;background:linear-gradient(180deg,rgba(10,15,21,.96),rgba(10,15,21,.75),transparent);backdrop-filter:blur(18px)}.top-title{font-size:31px;font-weight:760;letter-spacing:-.035em}.top-actions{display:flex;justify-content:flex-end;gap:10px}.circle{width:48px;height:48px;border-radius:50%;background:rgba(255,255,255,.09);border:1px solid var(--line);display:grid;place-items:center}.circle svg{width:23px;height:23px;fill:none;stroke:currentColor;stroke-width:1.9;stroke-linecap:round;stroke-linejoin:round}.seg{display:flex;align-items:center;gap:2px;padding:4px;background:rgba(255,255,255,.095);border:1px solid rgba(255,255,255,.13);border-radius:34px;box-shadow:0 8px 28px rgba(0,0,0,.25)}.seg button{padding:12px 20px;border-radius:28px;font-size:20px;font-weight:560;white-space:nowrap}.seg .seg-icon{width:48px;padding:12px}.seg .seg-icon svg{width:22px;height:22px;fill:none;stroke:currentColor;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round}.seg button.active{background:#0b0d10;font-weight:720}.hero-title{font-size:48px;line-height:1.02;letter-spacing:-.05em;margin:8px 0 22px}.library-sub{font-size:20px;color:var(--secondary);margin-bottom:28px}.actions{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:14px;margin-bottom:42px}.pill{height:70px;border-radius:36px;background:rgba(255,255,255,.105);border:1px solid var(--line);font-size:21px;font-weight:620}.section{margin-top:34px}.section-head{display:flex;align-items:center;justify-content:space-between;margin-bottom:18px}.section-title{font-size:27px;font-weight:740;letter-spacing:-.025em}.section-more{color:var(--secondary);font-size:15px}.horizontal{display:flex;gap:18px;overflow-x:auto;padding-bottom:8px;scrollbar-width:none}.horizontal::-webkit-scrollbar{display:none}.card{flex:0 0 248px;text-align:left;padding:12px;border-radius:24px;background:rgba(255,255,255,.09);border:1px solid var(--line);overflow:hidden}.card .art,.card .fallback{width:100%;aspect-ratio:1;border-radius:18px;object-fit:cover;background:rgba(255,255,255,.06)}.fallback{display:grid;place-items:center;font-size:42px;color:var(--secondary)}.card-title{font-size:20px;font-weight:650;margin-top:12px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.card-sub{font-size:16px;color:var(--secondary);margin-top:5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.grid{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:18px}.grid .card{width:auto}.list{display:flex;flex-direction:column;gap:8px}.row{display:grid;grid-template-columns:66px minmax(0,1fr) auto;align-items:center;gap:14px;padding:10px 14px;border-radius:18px;background:rgba(255,255,255,.075);border:1px solid rgba(255,255,255,.08);text-align:left}.row-art{width:58px;height:58px;border-radius:12px;object-fit:cover;background:rgba(255,255,255,.06)}.row-main{min-width:0}.row-title{font-size:17px;font-weight:650;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.row-sub{font-size:14px;color:var(--secondary);margin-top:4px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.row-tail{color:var(--secondary);font-size:14px}.empty{color:var(--secondary);padding:80px 20px;text-align:center;font-size:18px}.playlist-grid{display:grid;grid-template-columns:repeat(3,minmax(220px,320px));justify-content:center;gap:24px}.playlist-card{padding:14px;border-radius:24px;background:rgba(255,255,255,.09);border:1px solid var(--line);text-align:left}.playlist-cover{aspect-ratio:1;border-radius:17px;overflow:hidden;display:grid;grid-template-columns:1fr 1fr;background:#17191c}.playlist-cover img{width:100%;height:100%;object-fit:cover}.playlist-info{padding:12px 2px 4px}.playlist-name{font-size:21px;font-weight:650}.playlist-meta{display:flex;justify-content:space-between;color:var(--secondary);margin-top:12px;font-size:15px}.detail{display:grid;grid-template-columns:330px 1fr;gap:42px;align-items:start}.detail-sidebar{background:rgba(255,255,255,.055);border-radius:0 26px 26px 0;padding:20px 14px;min-height:600px}.detail-main{padding-top:20px}.detail-head{display:flex;gap:26px;align-items:center}.detail-avatar{width:240px;height:240px;border-radius:50%;object-fit:cover;background:rgba(255,255,255,.06);border:4px solid rgba(255,255,255,.8)}.detail-name{font-size:38px;font-weight:760;letter-spacing:-.04em}.detail-count{color:var(--secondary);font-size:18px;margin-top:10px}.detail-actions{display:flex;gap:12px;margin:28px 0}.detail-play{height:64px;border-radius:34px;background:#fff;color:#000;font-size:20px;font-weight:700;flex:0 1 440px}.detail-shuffle{height:64px;border-radius:34px;background:rgba(255,255,255,.1);font-size:20px;font-weight:650;flex:0 1 440px}.sidebar-search{height:52px;border-radius:16px;background:rgba(255,255,255,.08);padding:0 16px;color:var(--secondary);width:100%;outline:none}.artist-list{margin-top:14px}.artist-item{width:100%;display:flex;align-items:center;gap:14px;padding:11px 8px;border-radius:16px;text-align:left}.artist-item.active{background:rgba(255,255,255,.15)}.artist-icon{width:54px;height:54px;border-radius:50%;background:rgba(255,255,255,.09);display:grid;place-items:center;color:var(--secondary)}.artist-icon svg{width:24px;height:24px}.artist-copy{min-width:0}.artist-copy strong{display:block;font-size:18px}.artist-copy span{display:block;color:var(--secondary);font-size:14px;margin-top:3px}.mini{position:fixed;left:19%;right:19%;bottom:22px;height:78px;border-radius:40px;background:rgba(36,36,36,.88);border:1px solid rgba(255,255,255,.15);backdrop-filter:blur(30px);box-shadow:0 18px 55px rgba(0,0,0,.45);display:grid;grid-template-columns:minmax(260px,1fr) auto minmax(220px,1fr);align-items:center;padding:8px 14px;z-index:60}.mini-track{display:flex;align-items:center;gap:12px;min-width:0}.mini-art{width:58px;height:58px;border-radius:12px;object-fit:cover;background:rgba(255,255,255,.06)}.mini-text{min-width:0}.mini-title{font-size:17px;font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.mini-artist{font-size:14px;color:var(--secondary);margin-top:3px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.mini-controls{display:flex;align-items:center;gap:14px}.mini-controls .circle{background:transparent;border:0}.mini-extra{display:flex;align-items:center;justify-content:flex-end;gap:10px;color:var(--secondary);font-size:12px}.mini-device{max-width:160px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.progress{position:absolute;left:74px;right:74px;bottom:0;height:3px;background:rgba(255,255,255,.18);border-radius:99px;overflow:hidden}.progress i{display:block;height:100%;background:#fff;width:0}.now-playing{position:fixed;inset:0;background:#0b1118;z-index:100;display:none;overflow:auto}.now-playing.open{display:block}.np-backdrop{position:absolute;inset:0;background-position:center;background-size:cover;filter:blur(35px);transform:scale(1.12);opacity:.42}.np-shade{position:absolute;inset:0;background:linear-gradient(90deg,rgba(8,12,16,.92),rgba(8,12,16,.52),rgba(8,12,16,.35))}.np-inner{position:relative;min-height:100%;padding:18px 32px 40px;display:grid;grid-template-columns:460px 1fr;gap:48px;align-items:center}.np-art{width:100%;aspect-ratio:1;border-radius:18px;object-fit:cover;box-shadow:0 30px 90px rgba(0,0,0,.45)}.np-right{max-width:760px}.np-song{font-size:34px;font-weight:760;letter-spacing:-.04em}.np-artist{font-size:19px;color:var(--secondary);margin-top:6px}.np-format{font-size:14px;color:var(--secondary);margin-top:5px}.seek{margin-top:30px}.range{width:100%;accent-color:#fff}.times{display:flex;justify-content:space-between;color:var(--secondary);font-size:13px;margin-top:6px}.np-controls{display:flex;justify-content:center;align-items:center;gap:18px;margin-top:28px}.np-controls .circle{background:transparent;border:0}.play{width:62px;height:62px;border-radius:50%;background:#fff;color:#000;display:grid;place-items:center}.play svg{width:24px;height:24px;fill:currentColor}.np-volume{display:flex;gap:12px;align-items:center;margin-top:25px}.np-volume svg{width:20px;height:20px;fill:#fff}.lyrics{margin-top:30px;max-height:360px;overflow:auto;text-align:left;color:var(--secondary);line-height:1.55}.lyric{font-size:19px;padding:6px 0}.lyric.active{color:#fff;font-size:25px;font-weight:750}.np-output{display:flex;align-items:center;gap:10px;margin-top:22px;color:var(--secondary);font-size:14px}.np-output strong{color:#fff;font-weight:650}.output-icon{width:38px;height:38px;border-radius:50%;display:grid;place-items:center;background:rgba(255,255,255,.1);border:1px solid var(--line)}.output-icon svg{width:20px;height:20px;fill:none;stroke:currentColor;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round}.mobile-nav{display:none}
@media(max-width:1100px){.grid{grid-template-columns:repeat(4,minmax(0,1fr))}.mini{left:12%;right:12%}.detail{grid-template-columns:1fr}.detail-sidebar{display:none}.np-inner{grid-template-columns:minmax(280px,44vw) 1fr;gap:28px}.seg button{padding:11px 14px;font-size:17px}}
@media(max-width:760px){.topbar{height:78px;grid-template-columns:1fr auto}.top-title{font-size:24px}.seg{position:absolute;top:12px;left:50%;transform:translateX(-50%);width:max-content}.seg button{padding:9px 12px;font-size:13px}.top-actions{gap:6px}.top-actions .circle{width:42px;height:42px}.page{padding:8px 18px 145px}.hero-title{font-size:36px}.actions{grid-template-columns:1fr;gap:10px}.actions .pill{height:58px}.grid{grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}.card{padding:9px;border-radius:18px}.card-title{font-size:16px}.card-sub{font-size:13px}.section-title{font-size:23px}.mini{left:10px;right:10px;bottom:68px;height:68px;border-radius:20px;grid-template-columns:1fr auto;padding:6px 9px}.mini-art{width:52px;height:52px}.mini-controls{gap:2px}.mini-controls .optional{display:none}.mini-extra{display:none}.progress{left:62px;right:62px}.mobile-nav{position:fixed;display:flex;left:10px;right:10px;bottom:8px;height:54px;border-radius:18px;background:rgba(24,24,24,.92);border:1px solid var(--line);backdrop-filter:blur(28px);z-index:70;justify-content:space-around;padding:4px}.mobile-nav button{flex:1;color:var(--secondary);font-size:9px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:2px;border-radius:13px}.mobile-nav button.active{color:#fff;background:rgba(255,255,255,.1)}.mobile-nav svg{width:18px;height:18px;fill:none;stroke:currentColor;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round}.playlist-grid{grid-template-columns:1fr}.np-inner{display:flex;flex-direction:column;padding:18px 22px 30px;align-items:stretch}.np-art{width:min(82vw,420px);margin:26px auto 0}.np-right{max-width:none}.np-song{font-size:27px;margin-top:22px}.lyrics{max-height:240px}.np-output{margin-bottom:15px}}
</style>
</head>
<body>
<div class="app"><main class="content">
<header class="topbar"><div class="top-actions" style="justify-content:flex-start"><button class="circle" onclick="refresh()" aria-label="Refresh"><svg viewBox="0 0 24 24"><path d="M20 11a8 8 0 0 0-14.9-3M4 5v4h4M4 13a8 8 0 0 0 14.9 3M20 19v-4h-4"/></svg></button></div><nav class="seg" id="seg"><button class="seg-icon" aria-label="Library"><svg viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="16" rx="2"/><path d="M9 4v16"/></svg></button><button data-page="home" class="active" onclick="go('home')">Home</button><button data-page="tracks" onclick="go('tracks')">Tracks</button><button data-page="albums" onclick="go('albums')">Albums</button><button data-page="artists" onclick="go('artists')">Artists</button><button data-page="playlists" onclick="go('playlists')">Playlists</button></nav><div class="top-actions"><button class="circle" aria-label="Settings"><svg viewBox="0 0 24 24"><path d="M12 15.2a3.2 3.2 0 1 0 0-6.4 3.2 3.2 0 0 0 0 6.4Z"/><path d="m19.4 15 .1.1a2 2 0 0 1-2.8 2.8l-.1-.1a2 2 0 0 0-3.4 1.4v.2a2 2 0 0 1-4 0v-.2A2 2 0 0 0 5.8 17l-.1.1A2 2 0 0 1 2.9 14.3L3 14.2a2 2 0 0 0-1.4-3.4h-.2a2 2 0 0 1 0-4h.2A2 2 0 0 0 3 3.4l-.1-.1A2 2 0 0 1 5.7.5l.1.1a2 2 0 0 0 3.4-1.4V-1a2 2 0 0 1 4 0v.2a2 2 0 0 0 3.4 1.4l.1-.1a2 2 0 0 1 2.8 2.8l-.1.1a2 2 0 0 0 1.4 3.4h.2a2 2 0 0 1 0 4h-.2a2 2 0 0 0-1.4 3.4Z"/></svg></button><button class="circle" onclick="createPlaylist()" aria-label="Create playlist"><svg viewBox="0 0 24 24"><path d="M12 5v14M5 12h14"/></svg></button></div></header>
<div class="page" id="page"></div>
<nav class="mobile-nav"><button data-page="home" class="active" onclick="go('home')"><svg viewBox="0 0 24 24"><path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1V10Z"/></svg>Home</button><button data-page="tracks" onclick="go('tracks')"><svg viewBox="0 0 24 24"><path d="M9 18V5l11-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="17" cy="16" r="3"/></svg>Tracks</button><button data-page="albums" onclick="go('albums')"><svg viewBox="0 0 24 24"><rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="12" cy="12" r="4"/></svg>Albums</button><button data-page="artists" onclick="go('artists')"><svg viewBox="0 0 24 24"><circle cx="12" cy="8" r="3"/><path d="M5 21a7 7 0 0 1 14 0"/></svg>Artists</button><button data-page="playlists" onclick="go('playlists')"><svg viewBox="0 0 24 24"><rect x="3" y="3" width="18" height="18" rx="3"/><path d="M7 8h10M7 12h10M7 16h6"/></svg>Playlists</button></nav>
</main></div>
<div class="mini" onclick="openNowPlaying()"><div class="mini-track"><img class="mini-art" id="miniArt" src="" alt=""><div class="mini-text"><div class="mini-title" id="miniTitle">Nothing Playing</div><div class="mini-artist" id="miniArtist"></div></div></div><div class="mini-controls"><button class="circle optional" onclick="event.stopPropagation();cmd('previous')"><svg viewBox="0 0 24 24"><path d="M6 5v14h2V5H6Zm3 7 9 7V5l-9 7Z" fill="currentColor"/></svg></button><button class="play" id="miniPlay" onclick="event.stopPropagation();cmd('toggle')"><svg viewBox="0 0 24 24"><path id="miniPlayPath" d="M8 5v14l11-7L8 5Z"/></svg></button><button class="circle optional" onclick="event.stopPropagation();cmd('next')"><svg viewBox="0 0 24 24"><path d="M16 5v14h2V5h-2Zm-1 7L6 5v14l9-7Z" fill="currentColor"/></svg></button></div><div class="mini-extra"><span>Playing on</span><strong class="mini-device" id="miniDevice">This iPad</strong></div><div class="progress"><i id="miniProgress"></i></div></div>
<div class="now-playing" id="nowPlaying"><div class="np-backdrop" id="npBackdrop"></div><div class="np-shade"></div><div class="np-inner"><button class="circle" style="position:absolute;left:18px;top:18px;z-index:2" onclick="closeNowPlaying()"><svg viewBox="0 0 24 24"><path d="m6 6 12 12M18 6 6 18"/></svg></button><img class="np-art" id="npArt" src="" alt=""><div class="np-right"><div class="np-song" id="npTitle">Nothing Playing</div><div class="np-artist" id="npArtist"></div><div class="np-format" id="npFormat"></div><div class="seek"><input id="seek" class="range" type="range" min="0" max="1" value="0" step="0.01"><div class="times"><span id="elapsed">0:00</span><span id="remaining">-0:00</span></div></div><div class="np-controls"><button class="circle" onclick="cmd('shuffle',{value:true})"><svg viewBox="0 0 24 24"><path d="M16 3h5v5M20 4l-5 5M4 5h3a4 4 0 0 1 3.3 1.7l4.4 6.6A4 4 0 0 0 18 15h3M4 19h3a4 4 0 0 0 3.3-1.7l1.2-1.8M20 20l-4-4"/></svg></button><button class="circle" onclick="cmd('previous')"><svg viewBox="0 0 24 24"><path d="M6 5v14h2V5H6Zm3 7 9 7V5l-9 7Z" fill="currentColor"/></svg></button><button class="play" id="npPlay" onclick="cmd('toggle')"><svg viewBox="0 0 24 24"><path id="npPlayPath" d="M8 5v14l11-7L8 5Z"/></svg></button><button class="circle" onclick="cmd('next')"><svg viewBox="0 0 24 24"><path d="M16 5v14h2V5h-2Zm-1 7L6 5v14l9-7Z" fill="currentColor"/></svg></button><button class="circle" onclick="cmd('repeat',{value:'all'})"><svg viewBox="0 0 24 24"><path d="M7 7h10V4l4 4-4 4V9H7a3 3 0 0 0-3 3M17 17H7v3l-4-4 4-4v3h10a3 3 0 0 0 3-3"/></svg></button></div><div class="np-volume"><svg viewBox="0 0 24 24"><path d="M4 9v6h4l5 4V5L8 9H4Z"/><path d="M16 8.5a5 5 0 0 1 0 7M18.5 6a8.5 8.5 0 0 1 0 12" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg><input id="volume" class="range" type="range" min="0" max="1" value="1" step="0.01"></div><div class="np-output"><span class="output-icon"><svg viewBox="0 0 24 24"><path d="M5 17h14M7 13h10M9 9h6M12 5v12"/></svg></span><span>Playing on <strong id="npDevice">This iPad</strong></span></div><div class="lyrics" id="lyrics"></div></div></div></div>
<script>
let state=null,page='home',localPosition=0;
const $=id=>document.getElementById(id);const esc=s=>String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));const fmt=s=>{s=Math.max(0,Math.floor(s||0));return `${Math.floor(s/60)}:${String(s%60).padStart(2,'0')}`};
async function api(path,options={}){const r=await fetch(path,{cache:'no-store',...options});if(!r.ok)throw new Error(await r.text());return r.json()}
async function cmd(command,extra={}){try{await api('/api/command',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({command,...extra})});await refresh()}catch(e){console.error(e)}}
function go(p){page=p;renderPage();window.scrollTo({top:0,behavior:'smooth'})}
function setNav(){document.querySelectorAll('[data-page]').forEach(b=>b.classList.toggle('active',b.dataset.page===page));$('pageTitle').textContent=page==='playlists'?'All Playlists':page[0].toUpperCase()+page.slice(1)}
function tracks(){return state?.library||[]}
function albums(){const m=new Map();tracks().forEach(t=>{const k=t.album||'Unknown Album';if(!m.has(k))m.set(k,{name:k,artist:t.artist,track:t,tracks:[]});m.get(k).tracks.push(t)});return [...m.values()]}
function artists(){const m=new Map();tracks().forEach(t=>{const k=t.artist||'Unknown Artist';if(!m.has(k))m.set(k,{name:k,track:t,tracks:[]});m.get(k).tracks.push(t)});return [...m.values()]}
function art(t,cls='art'){return t?.artworkURL?`<img class="${cls}" src="${t.artworkURL}" loading="lazy" onerror="this.style.display='none'">`:`<div class="${cls==='row-art'?'row-art fallback':'fallback'}">♪</div>`}
function card(t,onclick){return `<button class="card" onclick="${onclick}">${art(t)}<div class="card-title">${esc(t.title||t.name)}</div><div class="card-sub">${esc(t.artist||'')}</div></button>`}
function trackRows(items){if(!items.length)return '<div class="empty">No tracks.</div>';return `<div class="list">${items.map((t,i)=>`<button class="row" onclick="cmd('playLibrary',{id:'${t.id}'})">${art(t,'row-art')}<div class="row-main"><div class="row-title">${esc(t.title)}</div><div class="row-sub">${esc(t.artist)}${t.album?' · '+esc(t.album):''}</div></div><div class="row-tail">${fmt(t.duration)}</div></button>`).join('')}</div>`}
function playlistCover(p){const imgs=(p.artworkURLs||[]).filter(Boolean).slice(0,4);if(!imgs.length)return '<div class="playlist-cover"><div class="fallback">♪</div></div>';return `<div class="playlist-cover">${imgs.map(u=>`<img src="${u}" loading="lazy">`).join('')}</div>`}
function playlistCard(p){return `<button class="playlist-card" onclick="goPlaylist('${esc(p.id)}')">${playlistCover(p)}<div class="playlist-info"><div class="playlist-name">${esc(p.name)}</div><div class="playlist-meta"><span>${p.trackCount} Tracks</span><span>${fmt(p.duration)}</span></div></div></button>`}
function home(){const ts=tracks(),recent=(state?.recentlyPlayed||[]).filter(t=>t.id!==state?.track?.id),current=state?.track?.id?ts.find(t=>t.id===state.track.id)||state.track:null,as=albums(),ars=artists(),ps=state?.playlists||[];let h=`<h1 class="hero-title">Home</h1><div class="library-sub">${ts.length} tracks ready to play offline.</div><div class="actions"><button class="pill" onclick="shuffleAll()">⇄ &nbsp; Shuffle All</button><button class="pill" onclick="alert('Import music on the iPad to add it to the library.')">＋ &nbsp; Import</button><button class="pill" onclick="createPlaylist()">☷ &nbsp; Playlist</button></div>`;if(current?.title)h+=`<div class="section"><div class="section-title">Continue Listening</div><button class="row" style="margin-top:18px" onclick="cmd('toggle')">${art(current,'row-art')}<div class="row-main"><div class="row-title">${esc(current.title)}</div><div class="row-sub">${esc(current.artist)}</div><div class="row-sub">${state?.playing?'Playing now':'Paused'}</div></div><div class="circle">${state?.playing?'Ⅱ':'▶'}</div></button></div>`;if(recent.length)h+=`<div class="section"><div class="section-title">Recently Played</div><div class="horizontal">${recent.slice(0,10).map(t=>card(t,`cmd('playLibrary',{id:'${t.id}'})`)).join('')}</div></div>`;if(as.length)h+=`<div class="section"><div class="section-head"><div class="section-title">Albums</div><button class="section-more" onclick="go('albums')">See All</button></div><div class="horizontal">${as.slice(0,10).map(a=>card({...a.track,title:a.name},`goAlbum('${esc(a.name)}')`)).join('')}</div></div>`;if(ars.length)h+=`<div class="section"><div class="section-head"><div class="section-title">Artists</div><button class="section-more" onclick="go('artists')">See All</button></div><div class="horizontal">${ars.slice(0,10).map(a=>card({...a.track,title:a.name,artist:''},`goArtist('${esc(a.name)}')`)).join('')}</div></div>`;if(ps.length)h+=`<div class="section"><div class="section-head"><div class="section-title">For You</div><button class="section-more" onclick="go('playlists')">See All</button></div><div class="playlist-grid">${ps.slice(0,3).map(playlistCard).join('')}</div></div>`;return h}
function renderPage(){setNav();let h='';if(page==='home')h=home();else if(page==='tracks')h=`<div class="section"><div class="section-title">Tracks</div>${trackRows(tracks())}</div>`;else if(page==='albums')h=`<div class="section"><div class="section-title">Albums</div><div class="grid">${albums().map(a=>card({...a.track,title:a.name},`goAlbum('${esc(a.name)}')`)).join('')}</div></div>`;else if(page==='artists')h=`<div class="section"><div class="section-title">Artists</div><div class="grid">${artists().map(a=>card({...a.track,title:a.name,artist:''},`goArtist('${esc(a.name)}')`)).join('')}</div></div>`;else h=`<div class="section"><div class="section-title">All Playlists</div><div class="playlist-grid" style="margin-top:24px">${(state?.playlists||[]).map(playlistCard).join('')||'<div class="empty">No playlists yet.</div>'}</div></div>`;$('page').innerHTML=h}
function goAlbum(name){const a=albums().find(x=>x.name===name);const items=a?.tracks||[];$('pageTitle').textContent=name;$('page').innerHTML=`<div class="section"><div class="section-title">${esc(name)}</div><div class="section" style="display:flex;gap:20px;align-items:center">${art(a?.track,'detail-avatar')}<div><div class="detail-name">${esc(name)}</div><div class="detail-count">${items.length} ${items.length===1?'Song':'Songs'} · ${fmt(items.reduce((s,t)=>s+(t.duration||0),0))}</div></div></div>${trackRows(items)}</div>`}
function goArtist(name){const a=artists().find(x=>x.name===name);const items=a?.tracks||[];$('pageTitle').textContent=name;$('page').innerHTML=`<div class="detail"><aside class="detail-sidebar"><div style="font-size:27px;font-weight:740;margin:10px 8px">Artists</div><input class="sidebar-search" placeholder="Search artists..." oninput="filterArtists(this.value)"><div class="artist-list" id="artistList">${artistSidebar(name)}</div></aside><section class="detail-main"><div class="detail-head"><div class="detail-avatar" style="border-color:rgba(255,255,255,.75)">${art(a?.track,'detail-avatar')}</div><div><div class="detail-name">${esc(name)}</div><div class="detail-count">${items.length} ${items.length===1?'Track':'Tracks'} · ${new Set(items.map(t=>t.album)).size} ${new Set(items.map(t=>t.album)).size===1?'Album':'Albums'}</div></div></div><div class="detail-actions"><button class="detail-play" onclick="${items[0]?`cmd('playLibrary',{id:'${items[0].id}'})`:''}">▶ &nbsp; Play</button><button class="detail-shuffle" onclick="${items[0]?`cmd('playLibrary',{id:'${items[Math.floor(Math.random()*items.length)].id}'})`:''}">⇄ &nbsp; Shuffle</button><button class="circle">•••</button></div><div class="section-title">Popular Tracks</div>${trackRows(items)}<div class="section"><div class="section-title">Albums</div><div class="horizontal">${[...new Set(items.map(t=>t.album))].map(n=>{const t=items.find(x=>x.album===n);return card({...t,title:n},`goAlbum('${esc(n)}')`)}).join('')}</div></div></section></div>`}
function artistSidebar(active){return artists().slice(0,80).map(a=>`<button class="artist-item ${a.name===active?'active':''}" onclick="goArtist('${esc(a.name)}')"><span class="artist-icon">${a.track?.artworkURL?`<img src="${a.track.artworkURL}" style="width:54px;height:54px;border-radius:50%;object-fit:cover">`:'●'}</span><span class="artist-copy"><strong>${esc(a.name)}</strong><span>${a.tracks.length} Track${a.tracks.length===1?'':'s'}</span></span></button>`).join('')}
function filterArtists(q){const list=artists().filter(a=>a.name.toLowerCase().includes(q.toLowerCase())).slice(0,80);$('artistList').innerHTML=list.map(a=>`<button class="artist-item" onclick="goArtist('${esc(a.name)}')"><span class="artist-icon">●</span><span class="artist-copy"><strong>${esc(a.name)}</strong><span>${a.tracks.length} Track${a.tracks.length===1?'':'s'}</span></span></button>`).join('')}
function goPlaylist(id){const p=(state?.playlists||[]).find(x=>x.id===id);if(!p)return;const items=tracks().filter(t=>(p.trackIDs||[]).includes(t.id));$('pageTitle').textContent=p.name;$('page').innerHTML=`<div class="section"><div style="display:flex;gap:28px;align-items:center">${playlistCover(p)}<div><div class="detail-name">${esc(p.name)}</div><div class="detail-count">${p.trackCount} Tracks · ${fmt(p.duration)}</div></div></div><div class="detail-actions"><button class="detail-play" onclick="${items[0]?`cmd('playLibrary',{id:'${items[0].id}'})`:''}">▶ &nbsp; Play</button><button class="detail-shuffle">⇄ &nbsp; Shuffle</button></div>${trackRows(items)}</div>`}
function shuffleAll(){const ts=tracks();if(ts.length)cmd('playLibrary',{id:ts[Math.floor(Math.random()*ts.length)].id})}
function createPlaylist(){const name=prompt('Playlist name');if(!name)return;cmd('createPlaylist',{name})}
function renderState(){const t=state?.track||{};const device=state?.playbackDeviceName||'This iPad';$('miniTitle').textContent=t.title||'Nothing Playing';$('miniArtist').textContent=t.artist||'';$('miniDevice').textContent=device;$('npTitle').textContent=t.title||'Nothing Playing';$('npArtist').textContent=t.artist||'';$('npFormat').textContent=t.audioInfo||'';$('npDevice').textContent=device;['miniArt','npArt'].forEach(id=>{const el=$(id);el.src=t.artworkURL||'';el.style.display=t.artworkURL?'block':'none'});$('npBackdrop').style.backgroundImage=t.artworkURL?`url('${t.artworkURL}')`:'';const path=state?.playing?'M7 5h4v14H7V5Zm6 0h4v14h-4V5Z':'M8 5v14l11-7L8 5Z';$('miniPlayPath').setAttribute('d',path);$('npPlayPath').setAttribute('d',path);localPosition=state?.position||0;$('seek').max=state?.duration||1;$('seek').value=localPosition;$('elapsed').textContent=fmt(localPosition);$('remaining').textContent='-'+fmt(Math.max(0,(state?.duration||0)-localPosition));$('volume').value=state?.volume??1;const pct=state?.duration?Math.min(100,(localPosition/state.duration)*100):0;$('miniProgress').style.width=pct+'%';$('lyrics').innerHTML=(state?.lyrics||[]).map((l,i)=>`<div class="lyric ${l.time<=localPosition&&(!state.lyrics[i+1]||localPosition<state.lyrics[i+1].time)?'active':''}">${esc(l.text)}</div>`).join('')}
function openNowPlaying(){$('nowPlaying').classList.add('open');renderState()}function closeNowPlaying(){$('nowPlaying').classList.remove('open')}
$('seek').addEventListener('input',e=>{localPosition=Number(e.target.value);$('elapsed').textContent=fmt(localPosition);$('remaining').textContent='-'+fmt(Math.max(0,(state?.duration||0)-localPosition))});$('seek').addEventListener('change',e=>cmd('seek',{position:Number(e.target.value)}));$('volume').addEventListener('change',e=>cmd('volume',{value:Number(e.target.value)}));
async function refresh(){try{state=await api('/api/state');renderState();renderPage()}catch(e){console.error(e)}}
setInterval(()=>{if(state?.playing){localPosition=Math.min(state.duration||0,localPosition+0.5);const pct=state?.duration?Math.min(100,(localPosition/state.duration)*100):0;$('miniProgress').style.width=pct+'%';$('seek').value=localPosition;$('elapsed').textContent=fmt(localPosition);$('remaining').textContent='-'+fmt(Math.max(0,(state?.duration||0)-localPosition))}},500);refresh();
</script></body></html>
"""#
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
