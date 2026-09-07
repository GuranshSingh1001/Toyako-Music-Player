import AVFoundation
import MediaPlayer
import Combine

class AudioEngineManager: ObservableObject {
    private let player = AVPlayer()
    private var timeObserverToken: Any?
    private var endObserverToken: Any?

    @Published var currentTrack: LocalTrack?
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0.0
    @Published var playbackProgress: Double = 0.0
    @Published var currentLyrics: [LyricLine] = []
    
    @Published var queue: [LocalTrack] = []
    @Published var queueIndex: Int = 0

    init() {
        setupRemoteControls()
        setupInterruptionHandling()
    }

    func startQueue(tracks: [LocalTrack], startIndex: Int) {
        guard !tracks.isEmpty, tracks.indices.contains(startIndex) else { return }
        queue = tracks
        queueIndex = startIndex
        play(track: tracks[startIndex])
    }

    func play(track: LocalTrack) {
        currentTrack = track
        loadLyrics(for: track)

        // Detach previous observers on this persistent player before swapping tracks
        detachTimeObserver()
        detachEndObserver()

        let playerItem = AVPlayerItem(url: track.url)
        player.replaceCurrentItem(with: playerItem)
        player.play()
        isPlaying = true

        updateNowPlaying(track: track)
        attachTimeObserver(duration: track.duration)

        endObserverToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.forward()
        }
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
        updatePlaybackState()
    }

    func forward() {
        if queueIndex + 1 < queue.count {
            queueIndex += 1
            play(track: queue[queueIndex])
        } else {
            player.pause()
            isPlaying = false
            seek(to: 0.0)
            updatePlaybackState()
        }
    }

    func backward() {
        if currentTime > 3.0 {
            seek(to: 0.0)
        } else if queueIndex > 0 {
            queueIndex -= 1
            play(track: queue[queueIndex])
        } else {
            seek(to: 0.0)
        }
    }

    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
        if let duration = currentTrack?.duration, duration > 0 {
            playbackProgress = time / duration
        }
        updatePlaybackState()
    }

    private func loadLyrics(for track: LocalTrack) {
        let lrcURL = track.url.deletingPathExtension().appendingPathExtension("lrc")
        if let content = try? String(contentsOf: lrcURL, encoding: .utf8) {
            currentLyrics = LRCParser.parse(content: content)
        } else {
            currentLyrics = []
        }
    }

    private func detachTimeObserver() {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }

    private func detachEndObserver() {
        if let token = endObserverToken {
            NotificationCenter.default.removeObserver(token)
            endObserverToken = nil
        }
    }

    private func attachTimeObserver(duration: TimeInterval) {
        guard duration > 0 else { return }

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let seconds = CMTimeGetSeconds(time)
            self.currentTime = seconds
            self.playbackProgress = seconds / duration
        }
    }

    private func setupRemoteControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.forward()
            return .success
        }
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.backward()
            return .success
        }
    }

    private func setupInterruptionHandling() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let info = notification.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
            if type == .began {
                self?.player.pause()
                self?.isPlaying = false
            }
        }
    }

    private func updateNowPlaying(track: LocalTrack) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0
        ]
        if let data = track.artworkData, let image = UIImage(data: data) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updatePlaybackState() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    deinit {
        detachTimeObserver()
        detachEndObserver()
    }
}