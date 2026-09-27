import Foundation
import Network
import UIKit
import Combine
import Darwin

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

    func attach(to manager: AudioEngineManager) {
        audioManager = manager
    }

    func start() {
        guard listener == nil else { return }
        lastError = nil

        do {
            let listener = try NWListener(using: .tcp, on: .any)
            listener.service = NWListener.Service(name: "Toyako", type: "_toyako._tcp")
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
            guard let artwork = audioManager?.currentTrack?.artworkData else {
                sendError(connection, status: 404, message: "No artwork")
                return
            }
            send(connection, status: 200, contentType: "image/jpeg", bodyData: normalizedJPEGData(artwork))
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
            case "seek":
                if let position = object["position"] as? Double { manager.seek(to: position) }
            case "volume":
                if let value = object["value"] as? Double { manager.setVolume(Float(value)) }
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
            "volume": manager.volume,
            "shuffle": manager.isShuffle,
            "repeat": manager.repeatMode.rawValue,
            "track": [
                "id": track?.id.uuidString ?? "",
                "title": track?.title ?? "Nothing Playing",
                "artist": track?.artist ?? "",
                "album": track?.album ?? "",
                "artworkURL": track?.artworkData == nil ? NSNull() : "/api/artwork"
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
<meta name="theme-color" content="#080808">
<title>Toyako Remote</title>
<style>
:root{color-scheme:dark;--bg:#080808;--panel:rgba(255,255,255,.075);--text:#fff;--muted:rgba(255,255,255,.55);--accent:#fff}
*{box-sizing:border-box}body{margin:0;background:radial-gradient(circle at 50% -10%,#252525 0,#0d0d0d 42%,#050505 100%);color:var(--text);font-family:-apple-system,BlinkMacSystemFont,"SF Pro Display",system-ui,sans-serif;min-height:100vh}
main{max-width:980px;margin:auto;padding:28px 22px 60px}.top{display:flex;justify-content:space-between;align-items:center;gap:18px;margin-bottom:28px}.brand{font-size:18px;font-weight:700}.pill{font-size:12px;color:#111;background:#fff;border-radius:999px;padding:7px 11px;font-weight:700}
.layout{display:grid;grid-template-columns:minmax(280px,420px) 1fr;gap:36px;align-items:start}.art{width:min(76vw,420px);aspect-ratio:1;border-radius:24px;object-fit:cover;background:#171717;box-shadow:0 28px 70px rgba(0,0,0,.45);display:block;margin:auto}.fallback{display:grid;place-items:center;font-size:72px;color:#333}
.info{text-align:center;margin-top:18px}.title{font-size:28px;font-weight:750;letter-spacing:-.03em}.artist{font-size:17px;color:var(--muted);margin-top:5px}.album{font-size:14px;color:rgba(255,255,255,.4);margin-top:3px}.times{display:flex;justify-content:space-between;color:var(--muted);font-size:12px;margin-top:12px}input[type=range]{width:100%;accent-color:white}.controls{display:flex;justify-content:center;align-items:center;gap:28px;margin:14px 0 18px}.controls button,.small button{border:0;color:white;background:transparent;cursor:pointer}.big{font-size:34px}.medium{font-size:22px}.secondary{color:var(--muted)!important}
.row{display:flex;justify-content:center;gap:10px;flex-wrap:wrap}.chip{border:1px solid rgba(255,255,255,.12);background:var(--panel);color:white;border-radius:999px;padding:9px 13px;cursor:pointer}.section{margin-top:26px}.section h2{font-size:14px;color:var(--muted);text-transform:uppercase;letter-spacing:.12em;margin:0 0 12px}.lyrics{height:520px;overflow:auto;padding:35px 8px;text-align:center;scroll-behavior:smooth}.line{font-size:26px;font-weight:700;line-height:1.35;margin:24px 0;color:rgba(255,255,255,.18);filter:blur(1.8px);transition:.35s}.line.active{font-size:32px;color:white;filter:none}.roman{font-size:.48em;font-weight:500;color:rgba(255,255,255,.52);margin-top:5px}.queue{display:grid;gap:8px}.track{padding:12px 14px;border-radius:14px;background:rgba(255,255,255,.055);display:flex;justify-content:space-between;gap:14px}.track.active{background:rgba(255,255,255,.13)}.track small{color:var(--muted)}.settings{display:grid;gap:12px}.setting{display:flex;justify-content:space-between;align-items:center;padding:12px 14px;border-radius:15px;background:var(--panel)}.setting label{font-size:14px}.setting input{accent-color:white}.error{color:#ff8d8d;font-size:13px;text-align:center;margin-top:10px}
@media(max-width:760px){main{padding:18px 15px 45px}.layout{display:block}.art{width:min(86vw,420px)}.lyrics{height:430px}.title{font-size:24px}.section{margin-top:32px}}
</style></head>
<body><main>
<div class="top"><div class="brand">Toyako Remote</div><div class="pill" id="status">Connecting…</div></div>
<div class="layout"><section>
<div id="artWrap"><div class="art fallback">♪</div></div>
<div class="info"><div class="title" id="title">Nothing Playing</div><div class="artist" id="artist"></div><div class="album" id="album"></div></div>
<div class="times"><span id="elapsed">0:00</span><span id="duration">0:00</span></div><input id="seek" type="range" min="0" max="1" value="0" step="0.1">
<div class="controls"><button class="medium" onclick="cmd('previous')">⏮</button><button class="big" id="play" onclick="cmd('toggle')">▶︎</button><button class="medium" onclick="cmd('next')">⏭</button></div>
<div class="row"><button class="chip" id="shuffle" onclick="toggleShuffle()">Shuffle</button><button class="chip" id="repeat" onclick="cycleRepeat()">Repeat: Off</button></div>
<div class="section"><h2>Queue</h2><div class="queue" id="queue"></div></div>
<div class="section"><h2>Remote Settings</h2><div class="settings" id="settings"></div></div>
</section>
<section class="section" style="margin-top:0"><h2>Lyrics</h2><div class="lyrics" id="lyrics"><div class="line active">No lyrics</div></div></section>
</div><div class="error" id="error"></div></main>
<script>
let state=null, localPosition=0, lastTick=Date.now();
const $=id=>document.getElementById(id);
const fmt=s=>{s=Math.max(0,Math.floor(s||0));let m=Math.floor(s/60),sec=String(s%60).padStart(2,'0');return `${m}:${sec}`};
async function api(path,options={}){let r=await fetch(path,{cache:'no-store',...options});if(!r.ok)throw new Error(await r.text());return r.json()}
async function cmd(command,extra={}){try{await api('/api/command',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({command,...extra})});await refresh()}catch(e){showError(e)}}
function showError(e){$('error').textContent=e?.message||String(e)}
function toggleShuffle(){cmd('shuffle',{value:!state.shuffle})}
function cycleRepeat(){let order=['off','all','one'];let i=order.indexOf(state.repeat);cmd('repeat',{value:order[(i+1)%order.length]})}
function render(){if(!state)return;$('status').textContent=state.playing?'Playing':'Connected';localPosition=state.position;lastTick=Date.now();$('title').textContent=state.track.title;$('artist').textContent=state.track.artist;$('album').textContent=state.track.album;$('elapsed').textContent=fmt(state.position);$('duration').textContent=fmt(state.duration);$('play').textContent=state.playing?'❚❚':'▶︎';$('shuffle').textContent=state.shuffle?'Shuffle: On':'Shuffle: Off';$('repeat').textContent='Repeat: '+(state.repeat==='off'?'Off':state.repeat==='all'?'All':'One');$('seek').max=Math.max(1,state.duration);$('seek').value=Math.min(state.duration,state.position);renderArtwork();renderLyrics();renderQueue();renderSettings()}
function renderArtwork(){let wrap=$('artWrap');if(state.track.artworkURL){let old=wrap.querySelector('img');if(!old){old=document.createElement('img');old.className='art';wrap.replaceChildren(old)}old.src=state.track.artworkURL+'?t='+encodeURIComponent(state.track.id)}else{wrap.innerHTML='<div class="art fallback">♪</div>'}}
function renderLyrics(){let box=$('lyrics'), lines=state.lyrics||[];if(!lines.length){box.innerHTML='<div class="line active">No lyrics</div>';return}let active=0;for(let i=0;i<lines.length;i++){if(lines[i].time<=localPosition)active=i}box.innerHTML=lines.map((l,i)=>{let cls=i===active?'line active':'line';let roman=state.settings['Toyako.Lyrics.ShowRomanization']&&l.romanized?`<div class="roman">${escapeHTML(l.romanized)}</div>`:'';return `<div class="${cls}" data-i="${i}">${escapeHTML(l.text)}${roman}</div>`}).join('');let el=box.querySelector('.active');if(el)el.scrollIntoView({block:'center',behavior:'smooth'})}
function renderQueue(){let q=state.queue||[];$('queue').innerHTML=q.length?q.map(x=>`<div class="track ${x.id===state.track.id?'active':''}"><span>${escapeHTML(x.title)}<br><small>${escapeHTML(x.artist)}</small></span><small>${escapeHTML(x.album)}</small></div>`).join(''):'<div style="color:var(--muted)">Queue is empty</div>'}
function renderSettings(){let s=state.settings;let items=[['Toyako.Lyrics.ShowRomanization','Show Romanization'],['Toyako.Lyrics.KaraokeGlow','Karaoke Glow'],['Toyako.Lyrics.Translation','Translate Japanese Lyrics'],['Toyako.NowPlaying.ShowAudioInfo','Show Audio Quality']];$('settings').innerHTML=items.map(([k,label])=>`<div class="setting"><label>${label}</label><input type="checkbox" ${s[k]?'checked':''} onchange="setSetting('${k}',this.checked)"></div>`).join('')}
async function setSetting(key,value){let payload={};payload[key]=value;try{await api('/api/settings',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});await refresh()}catch(e){showError(e)}}
function escapeHTML(s){return String(s??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]))}
$('seek').addEventListener('change',e=>cmd('seek',{position:Number(e.target.value)}));
async function refresh(){try{state=await api('/api/state');render();$('error').textContent=''}catch(e){$('status').textContent='Offline';showError(e)}}
setInterval(()=>{if(state?.playing){localPosition+= (Date.now()-lastTick)/1000;lastTick=Date.now();$('elapsed').textContent=fmt(localPosition);$('seek').value=Math.min(state.duration,localPosition);renderLyrics()}} ,500);
setInterval(refresh,1000);refresh();
</script></body></html>
"""#
}
