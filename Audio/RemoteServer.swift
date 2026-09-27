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
    private let queue = DispatchQueue(label: "com.toyako.remote-server")
    // Keep the remote on one stable port so toggling it off/on does not change the URL.
    private let fixedPort: UInt16 = 8787

    func attach(to manager: AudioEngineManager) {
        audioManager = manager
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
        case ("GET", "/api/state"):
            sendJSON(connection, object: statePayload())
        case ("GET", "/api/artwork"):
            guard let track = audioManager?.currentTrack else {
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

    private func audioFormatSummary(for track: LocalTrack) -> String? {
        guard let file = try? AVAudioFile(forReading: track.url) else { return nil }
        let format = file.fileFormat
        guard format.sampleRate > 0 else { return nil }
        let extensionName = track.url.pathExtension.uppercased()
        let sampleRate = String(format: "%.1f kHz", format.sampleRate / 1000.0)
        let channels = format.channelCount > 1 ? "Stereo" : "Mono"
        return [extensionName, sampleRate, channels].filter { !$0.isEmpty }.joined(separator: " · ")
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
<title>Toyako</title>
<style>
:root{color-scheme:dark;--white:#fff;--muted:rgba(255,255,255,.62);--faint:rgba(255,255,255,.28);--line:rgba(255,255,255,.22)}
*{box-sizing:border-box}
html,body{margin:0;width:100%;height:100%;min-height:100%;overflow:hidden;background:#08090b;color:var(--white);font-family:-apple-system,BlinkMacSystemFont,"SF Pro Display","SF Pro Text",system-ui,sans-serif;-webkit-font-smoothing:antialiased;touch-action:manipulation}
body{position:relative;min-height:100dvh}
#backdrop{position:fixed;inset:-8%;width:116%;height:116%;object-fit:cover;filter:blur(55px) saturate(.72);opacity:.48;transform:scale(1.05);display:none;pointer-events:none}
#backdrop.visible{display:block}
.backdrop-shade{position:fixed;inset:0;background:linear-gradient(90deg,rgba(5,7,10,.55),rgba(5,7,10,.36) 48%,rgba(5,7,10,.48)),rgba(6,8,11,.34);pointer-events:none}
.shell{position:relative;width:100%;height:100dvh;min-height:100svh;padding:clamp(14px,2.5vh,28px) clamp(20px,4vw,48px) clamp(16px,3vh,34px);display:flex;flex-direction:column;overflow:hidden}
.topbar{height:clamp(34px,5vh,42px);display:flex;align-items:center;justify-content:space-between;flex:0 0 auto}
.icon-btn{border:0;background:transparent;color:white;padding:10px;margin:-10px;cursor:pointer;display:grid;place-items:center;opacity:.94;flex:0 0 auto}
.icon-btn svg{width:clamp(22px,2.2vw,25px);height:clamp(22px,2.2vw,25px);fill:none;stroke:currentColor;stroke-width:2.2;stroke-linecap:round;stroke-linejoin:round}
.main{flex:1;min-height:0;display:grid;grid-template-columns:minmax(320px,44vw) minmax(0,1fr);gap:clamp(24px,5vw,72px);align-items:center;padding:clamp(4px,1vh,12px) 0;overflow:hidden}
.left{min-width:0;display:flex;flex-direction:column;justify-content:center;align-items:flex-start;max-width:560px;width:100%;margin:auto}
.art-wrap{width:min(100%,560px,42vh);aspect-ratio:1/1;display:grid;place-items:center}
.art{width:100%;height:100%;object-fit:cover;border-radius:18px;display:block;box-shadow:0 26px 60px rgba(0,0,0,.26);transition:transform .42s cubic-bezier(.22,.8,.2,1),opacity .25s}
.art.paused{transform:scale(.70)}
.fallback{width:100%;height:100%;border-radius:18px;background:rgba(255,255,255,.055);display:grid;place-items:center;color:rgba(255,255,255,.15);font-size:72px}
.info{margin-top:24px;width:100%;text-align:left}
.title{font-size:28px;font-weight:750;letter-spacing:-.035em;line-height:1.08;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.artist{font-size:18px;font-weight:500;color:var(--muted);margin-top:7px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.audio-info{font-size:14px;color:rgba(255,255,255,.47);margin-top:4px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.scrub{width:100%;margin-top:28px}
.range{width:100%;height:5px;appearance:none;-webkit-appearance:none;background:rgba(255,255,255,.23);border-radius:999px;outline:none;margin:0;padding:0;display:block}
.range::-webkit-slider-thumb{appearance:none;-webkit-appearance:none;width:17px;height:17px;border-radius:50%;background:white;border:0;box-shadow:0 2px 8px rgba(0,0,0,.18)}
.range::-moz-range-thumb{width:17px;height:17px;border-radius:50%;background:white;border:0}
.times{display:flex;justify-content:space-between;margin-top:9px;font-size:13px;color:rgba(255,255,255,.56);font-variant-numeric:tabular-nums}
.controls{width:100%;display:flex;align-items:center;justify-content:center;gap:clamp(18px,3.5vw,48px);margin-top:clamp(14px,2.8vh,25px)}
.control{border:0;background:transparent;color:white;display:grid;place-items:center;padding:8px;cursor:pointer;opacity:.96;flex:0 0 auto}
.control.dim{color:rgba(255,255,255,.35)}
.control svg{width:clamp(23px,2.5vw,27px);height:clamp(23px,2.5vw,27px);fill:currentColor;stroke:none}
.control.play{width:clamp(50px,5vw,58px);height:clamp(50px,5vw,58px);padding:0}
.control.play svg{width:clamp(37px,4vw,43px);height:clamp(37px,4vw,43px)}
.control:active{transform:scale(.91)}
.volume{width:100%;display:flex;align-items:center;gap:12px;margin-top:18px}
.volume svg{width:21px;height:21px;fill:white;opacity:.9;flex:0 0 auto}
.volume .range{height:5px}
.bottom-actions{width:100%;display:flex;justify-content:center;gap:30px;margin-top:14px}
.chip{border:0;background:transparent;color:white;font-size:15px;font-weight:600;padding:8px 10px;cursor:pointer;opacity:.9}
.chip.off{opacity:.34}
.right{min-width:0;height:min(76vh,820px);display:flex;align-items:center;overflow:hidden}
.lyrics{width:100%;height:100%;overflow-y:auto;overflow-x:hidden;position:relative;padding:0 28px;mask-image:linear-gradient(to bottom,transparent 0%,#000 13%,#000 87%,transparent 100%);-webkit-mask-image:linear-gradient(to bottom,transparent 0%,#000 13%,#000 87%,transparent 100%)}
.lyrics-inner{min-height:100%;display:flex;flex-direction:column;justify-content:center;gap:30px;padding:36vh 0;transition:none}
.line{font-size:50px;font-weight:750;line-height:1.1;letter-spacing:-.025em;color:white;opacity:.27;filter:blur(1.6px);transform:scale(.985);transform-origin:left center;cursor:pointer;transition:opacity .4s,filter .4s,transform .4s}
.line.past{opacity:.12;filter:blur(3.8px);transform:scale(.972)}
.line.active{opacity:1;filter:none;transform:scale(1)}
.roman{font-size:22px;font-weight:500;line-height:1.2;color:white;opacity:.18;margin-top:7px;letter-spacing:0}
.line.active .roman{opacity:.72}
.no-lyrics{font-size:22px;color:rgba(255,255,255,.42);font-weight:600}
.queue-panel{position:fixed;z-index:10;right:24px;top:70px;width:min(430px,calc(100vw - 48px));max-height:72vh;overflow:auto;background:rgba(20,22,25,.88);backdrop-filter:blur(28px);border:1px solid rgba(255,255,255,.11);border-radius:24px;padding:18px;box-shadow:0 30px 80px rgba(0,0,0,.5);display:none}
.queue-panel.open{display:block}.queue-head{display:flex;align-items:center;justify-content:space-between;margin-bottom:10px;font-weight:700}.queue-item{display:block;width:100%;padding:12px 10px;border-radius:12px;border:0;background:transparent;color:inherit;text-align:left;cursor:pointer;font:inherit}.queue-item:hover{background:rgba(255,255,255,.07)}.queue-item:active{background:rgba(255,255,255,.12);transform:scale(.995)}.queue-item.active{background:rgba(255,255,255,.10)}.queue-item small{display:block;color:var(--muted);margin-top:3px;pointer-events:none}.queue-item div{pointer-events:none}
.error{position:fixed;left:50%;bottom:18px;transform:translateX(-50%);color:#ffb3b3;font-size:13px;background:rgba(30,8,8,.75);padding:8px 12px;border-radius:10px;display:none;z-index:20}
@media (max-width:1100px) and (min-width:701px){
  .shell{padding:18px 28px 22px}
  .main{grid-template-columns:minmax(300px,42vw) minmax(0,1fr);gap:clamp(20px,4vw,48px)}
  .left{max-width:520px}
  .art-wrap{width:min(100%,42vw,46vh,500px)}
  .info{margin-top:18px}
  .title{font-size:clamp(22px,2.4vw,28px)}
  .artist{font-size:clamp(16px,1.7vw,18px)}
  .scrub{margin-top:18px}
  .right{height:min(70vh,680px)}
  .lyrics{padding:0 clamp(8px,2vw,28px)}
  .line{font-size:clamp(30px,4vw,46px)}
  .roman{font-size:clamp(15px,1.8vw,21px)}
}
@media(max-width:700px){
  .shell{padding:12px 18px max(16px,env(safe-area-inset-bottom))}
  .main{display:flex;flex-direction:column;justify-content:flex-start;align-items:stretch;position:relative;overflow:hidden;gap:0;padding:8px 0 0}
  .left{max-width:none;display:flex;width:100%;height:auto;min-height:0}
  .art-wrap{width:min(86vw,390px,52vh);max-width:100%;margin:0 auto}
  .info{margin-top:clamp(12px,2vh,17px)}
  .title{font-size:clamp(20px,6vw,23px)}
  .artist{font-size:clamp(14px,4.3vw,16px)}
  .audio-info{font-size:clamp(11px,3.2vw,12px)}
  .scrub{margin-top:clamp(14px,2.5vh,20px)}
  .controls{margin-top:clamp(12px,2vh,18px);gap:clamp(14px,5vw,24px)}
  .volume{margin-top:clamp(8px,1.8vh,12px)}
  .right{height:min(54dvh,430px);min-height:220px;width:100%;display:none;order:0}
  .line{font-size:clamp(25px,8vw,32px);line-height:1.08}
  .roman{font-size:clamp(14px,4vw,16px)}
  .bottom-actions{display:none}
  .portrait-lyrics-button{display:grid}
  .main.lyrics-mode .art-wrap{display:none}
  .main.lyrics-mode .right{display:flex;position:absolute;left:0;right:0;top:0;height:min(56dvh,460px);min-height:220px}
  .main.lyrics-mode .info{margin-top:10px}
  .main.lyrics-mode .left{max-width:none;padding-top:min(56dvh,460px)}
  .main.lyrics-mode .lyrics-toggle-icon{transform:rotate(180deg)}
}
@media(min-width:701px){.portrait-lyrics-button{display:none}}
@media (orientation:landscape) and (max-height:760px) and (min-width:701px){
  .shell{padding:10px 24px 14px}
  .topbar{height:30px}
  .main{grid-template-columns:minmax(280px,43vw) minmax(0,1fr);gap:clamp(18px,4vw,48px);padding:2px 0}
  .left{max-width:480px}
  .art-wrap{width:min(38vh,42vw,390px)}
  .info{margin-top:9px}
  .title{font-size:clamp(20px,2.5vw,23px)}
  .artist{font-size:15px;margin-top:4px}
  .audio-info{font-size:11px;margin-top:2px}
  .scrub{margin-top:10px}
  .times{margin-top:6px;font-size:11px}
  .controls{margin-top:8px;gap:clamp(16px,2.8vw,28px)}
  .volume{margin-top:6px}
  .right{height:min(78dvh,620px)}
  .lyrics{padding:0 clamp(8px,2vw,24px)}
  .lyrics-inner{gap:22px;padding:30vh 0}
  .line{font-size:clamp(27px,4.2vw,40px)}
  .roman{font-size:clamp(14px,1.8vw,17px)}
}
@media (max-height:600px) and (min-width:701px){
  .art-wrap{width:min(34vh,36vw,320px)}
  .info{margin-top:6px}
  .scrub{margin-top:7px}
  .controls{margin-top:5px}
  .volume{margin-top:4px}
}

</style>
</head>
<body>
<img id="backdrop" alt="">
<div class="backdrop-shade"></div>
<div class="shell">
  <div class="topbar">
    <button class="icon-btn" onclick="window.history.back()" aria-label="Close">
      <svg viewBox="0 0 24 24"><path d="m6 9 6 6 6-6"/></svg>
    </button>
    <div style="display:flex;align-items:center;gap:18px">
      <button class="icon-btn portrait-lyrics-button" onclick="togglePortraitLyrics()" aria-label="Show lyrics">
        <svg class="lyrics-toggle-icon" viewBox="0 0 24 24"><path d="M5 5h14v10H9l-4 4V5Z"/><path d="M8 9h8M8 12h5"/></svg>
      </button>
      <button class="icon-btn" onclick="toggleQueue()" aria-label="Queue">
      <svg viewBox="0 0 24 24"><path d="M8 6h13M8 12h13M8 18h9"/><path d="M3 6h.01M3 12h.01M3 18h.01"/></svg>
      </button>
    </div>
  </div>
  <div class="main" id="main">
    <section class="left">
      <div class="art-wrap" id="artWrap"><div class="fallback">♪</div></div>
      <div class="info">
        <div class="title" id="title">Nothing Playing</div>
        <div class="artist" id="artist"></div>
        <div class="audio-info" id="audioInfo"></div>
      </div>
      <div class="scrub">
        <input id="seek" class="range" type="range" min="0" max="1" value="0" step="0.01">
        <div class="times"><span id="elapsed">0:00</span><span id="remaining">-0:00</span></div>
      </div>
      <div class="controls">
        <button class="control" id="shuffle" onclick="toggleShuffle()" aria-label="Shuffle"><svg viewBox="0 0 24 24"><path d="M16 3h5v5h-2V6.41l-3.29 3.3-1.42-1.42L17.59 5H16V3ZM4 5h2.5c1.45 0 2.82.7 3.66 1.88l6.18 8.7A2.5 2.5 0 0 0 18.38 17H21v2h-2.62a4.5 4.5 0 0 1-3.86-2.18l-6.18-8.7A2.5 2.5 0 0 0 6.5 7H4V5Zm0 12h2.5a2.5 2.5 0 0 0 2.03-1.04l1.16-1.63 1.42 1.42-1 1.41A4.5 4.5 0 0 1 6.5 19H4v-2Z"/></svg></button>
        <button class="control" onclick="cmd('previous')" aria-label="Previous"><svg viewBox="0 0 24 24"><path d="M6 5v14h2V5H6Zm3 7 9 7V5l-9 7Z"/></svg></button>
        <button class="control play" id="play" onclick="cmd('toggle')" aria-label="Play or pause"><svg viewBox="0 0 24 24"><path id="playPath" d="M8 5v14l11-7L8 5Z"/></svg></button>
        <button class="control" onclick="cmd('next')" aria-label="Next"><svg viewBox="0 0 24 24"><path d="M16 5v14h2V5h-2Zm-1 7L6 5v14l9-7Z"/></svg></button>
        <button class="control" id="repeat" onclick="cycleRepeat()" aria-label="Repeat"><svg viewBox="0 0 24 24"><path d="M7 7h10V4l4 4-4 4V9H7a3 3 0 0 0-3 3H2a5 5 0 0 1 5-5Zm10 10H7v3l-4-4 4-4v3h10a3 3 0 0 0 3-3h2a5 5 0 0 1-5 5Z"/></svg></button>
      </div>
      <div class="volume">
        <svg viewBox="0 0 24 24"><path d="M4 9v6h4l5 4V5L8 9H4Z"/><path d="M16 8.5a5 5 0 0 1 0 7M18.5 6a8.5 8.5 0 0 1 0 12" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>
        <input id="volume" class="range" type="range" min="0" max="1" value="1" step="0.01">
        <svg viewBox="0 0 24 24"><path d="M4 9v6h4l5 4V5L8 9H4Z"/><path d="M16 8.5a5 5 0 0 1 0 7M18.5 6a8.5 8.5 0 0 1 0 12" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>
      </div>
    </section>
    <section class="right">
      <div class="lyrics" id="lyrics"><div class="lyrics-inner"><div class="no-lyrics">Lyrics Unavailable</div></div></div>
    </section>
  </div>
</div>
<div class="queue-panel" id="queuePanel"><div class="queue-head"><span>Queue</span><button class="icon-btn" onclick="toggleQueue()"><svg viewBox="0 0 24 24"><path d="m6 6 12 12M18 6 6 18"/></svg></button></div><div id="queue"></div></div>
<div class="error" id="error"></div>
<script>
let state=null,localPosition=0,lastTick=Date.now(),activeIndex=-1,lastTrackId='',manualLyricsScroll=false,portraitLyrics=false;
const $=id=>document.getElementById(id);
const fmt=s=>{s=Math.max(0,Math.floor(s||0));let m=Math.floor(s/60),sec=String(s%60).padStart(2,'0');return `${m}:${sec}`};
async function api(path,options={}){let r=await fetch(path,{cache:'no-store',...options});if(!r.ok)throw new Error(await r.text());return r.json()}
async function cmd(command,extra={}){try{await api('/api/command',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({command,...extra})});await refresh()}catch(e){showError(e)}}
function showError(e){$('error').textContent=e?.message||String(e);$('error').style.display='block';setTimeout(()=>$('error').style.display='none',3500)}
function renderArtwork(){let wrap=$('artWrap');if(state?.track?.artworkURL){let img=wrap.querySelector('img');if(!img){img=document.createElement('img');img.className='art';wrap.replaceChildren(img)}let url=state.track.artworkURL+'?t='+encodeURIComponent(state.track.id);if(img.src!==location.origin+url)img.src=url;img.classList.toggle('paused',!state.playing);let bg=$('backdrop');bg.src=url;bg.classList.add('visible')}else{wrap.innerHTML='<div class="fallback">♪</div>';let bg=$('backdrop');bg.removeAttribute('src');bg.classList.remove('visible')}}
function renderLyrics(force=false){
  let box=$('lyrics'),lines=state?.lyrics||[];
  if(!lines.length){box.innerHTML='<div class="lyrics-inner"><div class="no-lyrics">Lyrics Unavailable</div></div>';return}
  let idx=0;
  for(let i=0;i<lines.length;i++){if(lines[i].time<=localPosition)idx=i}
  if(!force&&idx===activeIndex)return;
  activeIndex=idx;
  let inner=document.createElement('div');inner.className='lyrics-inner';
  lines.forEach((l,i)=>{
    let d=document.createElement('div');d.className='line '+(i<idx?'past':i===idx?'active':'future');d.dataset.i=i;
    d.innerHTML=escapeHTML(l.text)+(state.settings['Toyako.Lyrics.ShowRomanization']&&l.romanized?`<div class="roman">${escapeHTML(l.romanized)}</div>`:'');
    d.onclick=()=>cmd('seek',{position:l.time});
    inner.appendChild(d);
  });
  box.replaceChildren(inner);
  requestAnimationFrame(()=>{
    let active=inner.querySelector('.active');
    if(active && !manualLyricsScroll){active.scrollIntoView({block:'center',behavior:force?'auto':'smooth'});}
  });
}

function renderQueue(){let q=state?.queue||[];$('queue').innerHTML=q.length?q.map((x,i)=>`<button type="button" class="queue-item ${x.id===state.track.id?'active':''}" data-index="${i}"><div>${escapeHTML(x.title)}</div><small>${escapeHTML(x.artist)}${x.album?' · '+escapeHTML(x.album):''}</small></button>`).join(''):'<div style="color:rgba(255,255,255,.5)">Queue is empty</div>';document.querySelectorAll('#queue .queue-item').forEach(el=>el.addEventListener('click',()=>cmd('playQueue',{index:Number(el.dataset.index)})))}
function render(){if(!state?.available)return;document.querySelector('.main').classList.toggle('lyrics-mode',portraitLyrics&&window.innerWidth<=600);$('title').textContent=state.track.title||'Nothing Playing';$('artist').textContent=state.track.artist||'';$('audioInfo').textContent=state.track.audioInfo||'';$('elapsed').textContent=fmt(localPosition);$('remaining').textContent='-'+fmt(Math.max(0,(state.duration||0)-localPosition));$('seek').max=state.duration||1;$('seek').value=Math.min(state.duration||1,localPosition);$('volume').value=state.volume??1;$('playPath').setAttribute('d',state.playing?'M7 5h4v14H7V5Zm6 0h4v14h-4V5Z':'M8 5v14l11-7L8 5Z');$('shuffle').classList.toggle('dim',!state.shuffle);$('repeat').classList.toggle('dim',state.repeat==='off');renderArtwork();renderLyrics(lastTrackId!==state.track.id);renderQueue();lastTrackId=state.track.id}
async function refresh(){try{let next=await api('/api/state');let wasPlaying=state?.playing;state=next;let now=Date.now();if(!wasPlaying||!state.playing)localPosition=state.position||0;else{localPosition=Math.max(0,state.position||0)}lastTick=now;render();$('error').style.display='none'}catch(e){showError(e)}}
function toggleShuffle(){cmd('shuffle',{value:!state.shuffle})}
function cycleRepeat(){let modes=['off','all','one'];let i=modes.indexOf(state.repeat);cmd('repeat',{value:modes[(i+1)%modes.length]})}
function toggleQueue(){$('queuePanel').classList.toggle('open')}
$('seek').addEventListener('input',e=>{localPosition=Number(e.target.value);$('elapsed').textContent=fmt(localPosition);$('remaining').textContent='-'+fmt(Math.max(0,(state.duration||0)-localPosition));renderLyrics()});$('seek').addEventListener('change',e=>cmd('seek',{position:Number(e.target.value)}));$('volume').addEventListener('input',e=>{if(state)state.volume=Number(e.target.value)});$('volume').addEventListener('change',e=>cmd('volume',{value:Number(e.target.value)}));
function togglePortraitLyrics(){portraitLyrics=!portraitLyrics;manualLyricsScroll=false;render();if(portraitLyrics)requestAnimationFrame(()=>renderLyrics(true));}
function updateOrientation(){if(window.innerWidth>600){portraitLyrics=false;document.querySelector('.main')?.classList.remove('lyrics-mode')}else{render()}}
window.addEventListener('resize',updateOrientation);
$('lyrics').addEventListener('scroll',()=>{manualLyricsScroll=true;clearTimeout(window.__lyricsScrollTimer);window.__lyricsScrollTimer=setTimeout(()=>manualLyricsScroll=false,1800)},{passive:true});
setInterval(()=>{let now=Date.now(),dt=(now-lastTick)/1000;lastTick=now;if(state?.playing){localPosition=Math.min(state.duration||Infinity,localPosition+dt);$('elapsed').textContent=fmt(localPosition);$('remaining').textContent='-'+fmt(Math.max(0,(state.duration||0)-localPosition));$('seek').value=Math.min(state.duration||1,localPosition);renderLyrics()}},250);
setInterval(refresh,1000);refresh();
function escapeHTML(s){return String(s??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]))}
</script>
</body></html>
"""#

}
