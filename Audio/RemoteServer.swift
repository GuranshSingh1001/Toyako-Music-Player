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
    @Published private(set) var isRunning = false
    @Published private(set) var address: String?
    @Published private(set) var port: UInt16 = 0
    @Published private(set) var lastError: String?

    private var listener: NWListener?
    private weak var audioManager: AudioEngineManager?

    private let libraryLock = NSLock()
    private var libraryTracks: [LocalTrack] = []
    private var libraryAlbums: [AlbumGroup] = []
    private var libraryArtists: [ArtistGroup] = []
    private var libraryPlaylists: [Playlist] = []
    private let queue = DispatchQueue(label: "com.toyako.remote-server")
    // Keep the remote on one stable port so toggling it off/on does not change the URL.
    private let fixedPort: UInt16 = 8787
    private let enabledKey = "Toyako.RemoteServerEnabled"

    func attach(to manager: AudioEngineManager) {
        audioManager = manager
    }

    /// Updates the read-only library snapshot used by the Web Remote.
    /// Playback remains entirely on the iPad; this snapshot is only for
    /// browsing and sending normal playback commands back to Toyako.
    func updateLibrarySnapshot(
        tracks: [LocalTrack],
        albums: [AlbumGroup],
        artists: [ArtistGroup],
        playlists: [Playlist]
    ) {
        libraryLock.lock()
        libraryTracks = tracks
        libraryAlbums = albums
        libraryArtists = artists
        libraryPlaylists = playlists
        libraryLock.unlock()
    }

    private func librarySnapshot() -> (tracks: [LocalTrack], albums: [AlbumGroup], artists: [ArtistGroup], playlists: [Playlist]) {
        libraryLock.lock()
        defer { libraryLock.unlock() }
        return (libraryTracks, libraryAlbums, libraryArtists, libraryPlaylists)
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
            // Bonjour advertising is intentionally optional. LiveContainer
            // hosts guest apps and does not apply guest entitlements exactly
            // like a normally installed app, so requiring service registration
            // can prevent the TCP server from starting there. The web remote
            // uses the LAN address shown in Settings, which works without
            // Bonjour.
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
        case ("GET", "/api/library"):
            sendJSON(connection, object: libraryPayload())
        case ("GET", "/api/artwork"):
            handleArtworkRequest(rawPath: rawPath, connection: connection)
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
                manager.playFromRemote()
            case "pause":
                manager.pauseFromRemote()
            case "toggle":
                manager.togglePlayPause()
            case "next":
                manager.forward()
            case "previous":
                manager.backward()
            case "playQueue":
                if let index = object["index"] as? Int {
                    manager.playQueuedTrack(at: index)
                }
            case "playTrack":
                if let idString = object["id"] as? String,
                   let id = UUID(uuidString: idString) {
                    let snapshot = self.librarySnapshot()
                    if let index = snapshot.tracks.firstIndex(where: { $0.id == id }) {
                        manager.startQueue(tracks: snapshot.tracks, startIndex: index)
                    }
                }
            case "playTrackSet":
                if let ids = object["ids"] as? [String] {
                    let snapshot = self.librarySnapshot()
                    let wanted = ids.compactMap { UUID(uuidString: $0) }
                    let selected = wanted.compactMap { id in snapshot.tracks.first(where: { $0.id == id }) }
                    if let first = selected.first {
                        manager.startQueue(tracks: selected, startIndex: 0)
                    }
                }
            case "seek":
                if let position = object["position"] as? Double { manager.seek(to: position) }
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
            "playing": manager.isPlaying,
            "position": manager.currentTime,
            "duration": track?.duration ?? 0,
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

    private func handleArtworkRequest(rawPath: String, connection: NWConnection) {
        let idString = queryValue(rawPath, key: "id")
        let snapshot = librarySnapshot()
        let track: LocalTrack?
        if let idString, let id = UUID(uuidString: idString) {
            track = snapshot.tracks.first(where: { $0.id == id })
                ?? audioManager?.currentTrack
        } else {
            track = audioManager?.currentTrack
        }

        guard let track else {
            sendError(connection, status: 404, message: "No artwork")
            return
        }
        Task {
            var artwork = track.artworkData
            if artwork == nil { artwork = await ArtworkStore.shared.data(for: track.url) }
            guard let artwork else {
                self.sendError(connection, status: 404, message: "No artwork")
                return
            }
            self.send(connection, status: 200, contentType: "image/jpeg", bodyData: self.normalizedJPEGData(artwork))
        }
    }

    private func queryValue(_ rawPath: String, key: String) -> String? {
        guard let query = rawPath.split(separator: "?", maxSplits: 1).dropFirst().first else { return nil }
        for pair in query.split(separator: "&") {
            let bits = pair.split(separator: "=", maxSplits: 1)
            guard bits.count == 2, String(bits[0]) == key else { continue }
            return String(bits[1]).removingPercentEncoding
        }
        return nil
    }

    private func libraryPayload() -> [String: Any] {
        let snapshot = librarySnapshot()
        let trackPayload: [[String: Any]] = snapshot.tracks.map { track in
            [
                "id": track.id.uuidString,
                "title": track.title,
                "artist": track.artist,
                "album": track.album,
                "genre": track.genre,
                "duration": track.duration,
                "artworkURL": "/api/artwork?id=\(track.id.uuidString)"
            ]
        }
        let albumPayload: [[String: Any]] = snapshot.albums.map { album in
            let tracks = album.tracks.map(\.id.uuidString)
            return [
                "id": Data("\(album.name)\u{1F}\(album.artist)".utf8).base64EncodedString(),
                "name": album.name,
                "artist": album.artist,
                "trackIDs": tracks,
                "artworkURL": album.tracks.first.map { "/api/artwork?id=\($0.id.uuidString)" } as Any
            ]
        }
        let artistPayload: [[String: Any]] = snapshot.artists.map { artist in
            let tracks = artist.tracks.map(\.id.uuidString)
            return [
                "id": Data(artist.name.utf8).base64EncodedString(),
                "name": artist.name,
                "trackIDs": tracks,
                "artworkURL": artist.tracks.first.map { "/api/artwork?id=\($0.id.uuidString)" } as Any
            ]
        }
        let playlistPayload: [[String: Any]] = snapshot.playlists.map { playlist in
            let trackIDs = playlist.trackURLs.compactMap { url in snapshot.tracks.first(where: { $0.url == url })?.id.uuidString }
            return [
                "id": playlist.id.uuidString,
                "name": playlist.name,
                "trackIDs": trackIDs,
                "artworkURL": trackIDs.first.map { "/api/artwork?id=\($0)" } as Any
            ]
        }
        return [
            "tracks": trackPayload,
            "albums": albumPayload,
            "artists": artistPayload,
            "playlists": playlistPayload
        ]
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
<meta name="theme-color" content="#0b0d10">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="Toyako">
<link rel="manifest" href="/manifest.json"><link rel="icon" type="image/png" href="/icon-192.png">
<title>Toyako</title>
<style>
:root{color-scheme:dark;--bg:#08090b;--card:rgba(255,255,255,.075);--line:rgba(255,255,255,.12);--muted:rgba(255,255,255,.62);--accent:#fff}
*{box-sizing:border-box}html,body{margin:0;min-height:100%;background:var(--bg);color:#fff;font-family:-apple-system,BlinkMacSystemFont,"SF Pro Display","SF Pro Text",system-ui,sans-serif;-webkit-font-smoothing:antialiased}body{overflow-x:hidden}
button,input{font:inherit}button{color:inherit}.app{min-height:100vh;min-height:100dvh;padding:18px clamp(16px,4vw,52px) 110px}.top{display:flex;align-items:center;gap:18px;position:sticky;top:0;z-index:20;padding:4px 0 14px;background:linear-gradient(var(--bg) 75%,transparent);backdrop-filter:blur(10px)}.brand{font-size:25px;font-weight:800;letter-spacing:-.04em}.nav{display:flex;gap:6px;overflow:auto;scrollbar-width:none}.nav::-webkit-scrollbar{display:none}.nav button{border:0;background:transparent;padding:9px 12px;border-radius:999px;color:var(--muted);font-weight:650;white-space:nowrap;cursor:pointer}.nav button.active{background:#fff;color:#111}.page{max-width:1500px;margin:0 auto}.hero{display:grid;grid-template-columns:minmax(220px,34%) 1fr;gap:32px;align-items:center;min-height:340px}.hero-art{width:min(100%,430px);aspect-ratio:1;object-fit:cover;border-radius:22px;box-shadow:0 24px 70px rgba(0,0,0,.35)}.eyebrow{color:var(--muted);font-size:13px;font-weight:700;text-transform:uppercase;letter-spacing:.12em}.hero h1{font-size:clamp(32px,5vw,66px);line-height:.98;letter-spacing:-.055em;margin:8px 0}.hero p{color:var(--muted);font-size:17px}.sections{display:grid;gap:34px}.section-head{display:flex;align-items:end;justify-content:space-between;gap:12px;margin-bottom:13px}.section-head h2{margin:0;font-size:23px;letter-spacing:-.035em}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(155px,1fr));gap:16px}.card{border:1px solid var(--line);background:var(--card);border-radius:17px;padding:11px;text-align:left;cursor:pointer;min-width:0;transition:transform .15s,background .15s}.card:active{transform:scale(.98)}.card:hover{background:rgba(255,255,255,.105)}.cover{width:100%;aspect-ratio:1;object-fit:cover;border-radius:12px;background:rgba(255,255,255,.06);display:grid;place-items:center;color:rgba(255,255,255,.25);font-size:42px}.card-title{margin-top:10px;font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.card-sub{margin-top:4px;color:var(--muted);font-size:13px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.list{display:grid;gap:6px}.row{display:grid;grid-template-columns:52px 1fr auto;gap:13px;align-items:center;padding:9px;border:0;background:transparent;border-radius:13px;text-align:left;cursor:pointer}.row:hover{background:rgba(255,255,255,.07)}.row-cover{width:52px;height:52px;object-fit:cover;border-radius:9px;background:rgba(255,255,255,.06)}.row-title{font-weight:650;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.row-sub{color:var(--muted);font-size:13px;margin-top:3px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.duration{color:var(--muted);font-size:12px;font-variant-numeric:tabular-nums}.detail{display:grid;gap:24px}.detail-head{display:flex;gap:22px;align-items:center}.detail-cover{width:190px;height:190px;object-fit:cover;border-radius:20px;background:rgba(255,255,255,.06)}.detail h1{font-size:clamp(30px,5vw,54px);margin:0;letter-spacing:-.05em}.detail p{color:var(--muted)}.back{border:0;background:var(--card);border:1px solid var(--line);border-radius:999px;padding:9px 13px;cursor:pointer}.player{position:fixed;left:50%;bottom:14px;transform:translateX(-50%);z-index:30;width:min(940px,calc(100% - 28px));background:rgba(18,20,24,.92);border:1px solid var(--line);backdrop-filter:blur(26px);border-radius:20px;padding:12px 15px;box-shadow:0 25px 70px rgba(0,0,0,.45)}.player-top{display:flex;gap:12px;align-items:center}.player-art{width:48px;height:48px;border-radius:10px;object-fit:cover;background:rgba(255,255,255,.06)}.player-meta{min-width:0;flex:1}.player-title{font-weight:750;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.player-artist{font-size:13px;color:var(--muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.player-controls{display:flex;align-items:center;justify-content:center;gap:22px;margin-top:8px}.player-controls button{border:0;background:transparent;cursor:pointer;font-size:19px}.player-controls .play{width:42px;height:42px;border-radius:50%;background:#fff;color:#111}.seek{width:100%;accent-color:#fff}.error{position:fixed;z-index:40;left:50%;bottom:105px;transform:translateX(-50%);background:#351212;color:#ffd1d1;border:1px solid #673131;padding:9px 13px;border-radius:10px;display:none}.empty{color:var(--muted);padding:40px 0;text-align:center}
@media(max-width:700px){.app{padding:12px 14px 130px}.top{gap:10px}.brand{font-size:21px}.nav button{padding:8px 10px}.hero{grid-template-columns:1fr;gap:18px;min-height:0}.hero-art{width:min(70vw,300px);margin:auto}.hero-copy{text-align:center}.grid{grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}.detail-head{align-items:flex-start}.detail-cover{width:120px;height:120px}.player{bottom:8px;width:calc(100% - 16px)}}
</style>
</head>
<body>
<div class="app"><header class="top"><div class="brand">Toyako</div><nav class="nav" id="nav"></nav></header><main class="page" id="page"></main></div>
<div class="player" id="player"></div><div class="error" id="error"></div>
<script>
const $=id=>document.getElementById(id);let state=null,library={tracks:[],albums:[],artists:[],playlists:[]},view='home',detail=null;
const fmt=s=>{s=Math.max(0,Math.floor(s||0));return Math.floor(s/60)+':'+String(s%60).padStart(2,'0')};
const esc=s=>String(s??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
async function api(path,options={}){const r=await fetch(path,{cache:'no-store',...options});if(!r.ok)throw new Error(await r.text());return r.json()}
function err(e){$('error').textContent=e?.message||String(e);$('error').style.display='block';clearTimeout(window.__err);window.__err=setTimeout(()=>$('error').style.display='none',3000)}
async function cmd(command,extra={}){try{await api('/api/command',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({command,...extra})});await refreshState()}catch(e){err(e)}}
function artwork(url){return url?`<img class="cover" src="${esc(url)}" loading="lazy" onerror="this.replaceWith(fallback())">`:'<div class="cover">♪</div>'}
function fallback(){const d=document.createElement('div');d.className='cover';d.textContent='♪';return d}
function nav(){const items=[['home','Home'],['tracks','Tracks'],['albums','Albums'],['artists','Artists'],['playlists','Playlists']];$('nav').innerHTML=items.map(([id,label])=>`<button class="${view===id?'active':''}" onclick="go('${id}')">${label}</button>`).join('')}
function go(v){view=v;detail=null;nav();render()}
function trackById(id){return library.tracks.find(x=>x.id===id)}
function trackRow(t){return `<button class="row" onclick="cmd('playTrack',{id:'${t.id}'})"><img class="row-cover" src="${esc(t.artworkURL)}" loading="lazy"><div><div class="row-title">${esc(t.title)}</div><div class="row-sub">${esc(t.artist)}${t.album?' · '+esc(t.album):''}</div></div><span class="duration">${fmt(t.duration)}</span></button>`}
function entityCard(x,type){let onclick=type==='album'?`openDetail('album','${x.id}')`:type==='artist'?`openDetail('artist','${x.id}')`:type==='playlist'?`openDetail('playlist','${x.id}')`:`cmd('playTrack',{id:'${x.id}'})`;let sub=type==='album'?x.artist:type==='artist'?`${x.trackIDs.length} tracks`:type==='playlist'?`${x.trackIDs.length} tracks`:x.artist;return `<button class="card" onclick="${onclick}">${artwork(x.artworkURL)}<div class="card-title">${esc(x.name||x.title)}</div><div class="card-sub">${esc(sub)}</div></button>`}
function section(title,content){return `<section><div class="section-head"><h2>${esc(title)}</h2></div>${content}</section>`}
function home(){const tracks=library.tracks.slice(0,12),albums=library.albums.slice(0,8),artists=library.artists.slice(0,8),playlists=library.playlists.slice(0,8);return `<div class="hero"><img class="hero-art" src="${esc(state?.track?.artworkURL||albums[0]?.artworkURL||'')}" onerror="this.style.visibility='hidden'"><div class="hero-copy"><div class="eyebrow">Your Library</div><h1>Listen anywhere on your network.</h1><p>${library.tracks.length} tracks · ${library.albums.length} albums · ${library.artists.length} artists · ${library.playlists.length} playlists</p></div></div><div class="sections">${section('Tracks',`<div class="list">${tracks.map(trackRow).join('')}</div>`)}${section('Albums',`<div class="grid">${albums.map(x=>entityCard(x,'album')).join('')}</div>`)}${section('Artists',`<div class="grid">${artists.map(x=>entityCard(x,'artist')).join('')}</div>`)}${section('Playlists',`<div class="grid">${playlists.map(x=>entityCard(x,'playlist')).join('')}</div>`)}</div>`}
function tracksPage(){return `<div class="detail"><div class="detail-head"><div><div class="eyebrow">Library</div><h1>Tracks</h1><p>${library.tracks.length} tracks</p></div></div><div class="list">${library.tracks.map(trackRow).join('')}</div></div>`}
function albumsPage(){return `<div class="detail"><div><div class="eyebrow">Library</div><h1>Albums</h1></div><div class="grid">${library.albums.map(x=>entityCard(x,'album')).join('')}</div></div>`}
function artistsPage(){return `<div class="detail"><div><div class="eyebrow">Library</div><h1>Artists</h1></div><div class="grid">${library.artists.map(x=>entityCard(x,'artist')).join('')}</div></div>`}
function playlistsPage(){return `<div class="detail"><div><div class="eyebrow">Library</div><h1>Playlists</h1></div><div class="grid">${library.playlists.map(x=>entityCard(x,'playlist')).join('')}</div></div>`}
function openDetail(type,id){detail={type,id};render()}
function detailPage(){const d=detail;let x=(d.type==='album'?library.albums:d.type==='artist'?library.artists:library.playlists).find(y=>y.id===d.id);if(!x)return '<div class="empty">Not found</div>';const tracks=x.trackIDs.map(trackById).filter(Boolean);const title=x.name;const sub=d.type==='album'?x.artist:`${tracks.length} tracks`;return `<div class="detail"><button class="back" onclick="detail=null;render()">← Back</button><div class="detail-head">${artwork(x.artworkURL).replace('class="cover"','class="detail-cover"')}<div><div class="eyebrow">${esc(d.type)}</div><h1>${esc(title)}</h1><p>${esc(sub)}</p><button class="back" onclick="cmd('playTrackSet',{ids:${JSON.stringify(x.trackIDs)}})">Play All</button></div></div><div class="list">${tracks.map(trackRow).join('')}</div></div>`}
function render(){nav();$('page').innerHTML=detail?detailPage():view==='home'?home():view==='tracks'?tracksPage():view==='albums'?albumsPage():view==='artists'?artistsPage():playlistsPage();renderPlayer()}
function renderPlayer(){if(!state?.available){$('player').innerHTML='';return}const t=state.track||{};$('player').innerHTML=`<div class="player-top"><img class="player-art" src="${esc(t.artworkURL||'')}" onerror="this.style.visibility='hidden'"><div class="player-meta"><div class="player-title">${esc(t.title)}</div><div class="player-artist">${esc(t.artist)}</div></div><span style="color:var(--muted);font-size:12px">${state.playing?'Playing':'Paused'}</span></div><input class="seek" id="playerSeek" type="range" min="0" max="${state.duration||1}" value="${state.position||0}" step="0.1"><div class="player-controls"><button onclick="cmd('previous')">⏮</button><button class="play" onclick="cmd('toggle')">${state.playing?'❚❚':'▶'}</button><button onclick="cmd('next')">⏭</button></div>`;const seek=$('playerSeek');seek.onchange=()=>cmd('seek',{position:Number(seek.value)})}
async function refreshState(){try{state=await api('/api/state');render()}catch(e){err(e)}}
async function refreshLibrary(){try{library=await api('/api/library');render()}catch(e){err(e)}}
setInterval(refreshState,350);refreshLibrary();refreshState();
</script>
</body></html>
"""#

    static let manifest = #"""
{
  "name": "Toyako Remote",
  "short_name": "Toyako",
  "description": "Toyako music library and remote control",
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
