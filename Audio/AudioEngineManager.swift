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
    @Published var originalQueue: [LocalTrack] = []
    @Published var queueIndex: Int = 0

    @Published var isShuffle: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var crossfadeEnabled: Bool = true

    init() {
        setupRemoteControls()
        setupInterruptionHandling()
    }

    func startQueue(tracks: [LocalTrack], startIndex: Int) {
        guard !tracks.isEmpty, tracks.indices.contains(startIndex) else { return }
        originalQueue = tracks
        
        if isShuffle {
            var shuffled = tracks
            let selected = shuffled.remove(at: startIndex)
            shuffled.shuffle()
            queue = [selected] + shuffled
            queueIndex = 0
        } else {
            queue = tracks
            queueIndex = startIndex
        }
        play(track: queue[queueIndex])
    }

    func play(track: LocalTrack) {
        currentTrack = track
        loadLyrics(for: track)

        detachTimeObserver()
        detachEndObserver()

        let playerItem = AVPlayerItem(url: track.url)

        if crossfadeEnabled && isPlaying {
            fadeOutAndSwitch(to: playerItem, track: track)
        } else {
            player.volume = 1.0
            player.replaceCurrentItem(with: playerItem)
            player.play()
            finalizePlay(track: track, playerItem: playerItem)
        }
    }

    private func fadeOutAndSwitch(to newItem: AVPlayerItem, track: LocalTrack) {
        var currentVol = player.volume
        Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            currentVol -= 0.15
            if currentVol <= 0.05 {
                timer.invalidate()
                self.player.replaceCurrentItem(with: newItem)
                self.player.play()
                self.fadeIn()
                self.finalizePlay(track: track, playerItem: newItem)
            } else {
                self.player.volume = currentVol
            }
        }
    }

    private func fadeIn() {
        var currentVol: Float = 0.0
        self.player.volume = 0.0
        Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            currentVol += 0.15
            if currentVol >= 1.0 {
                self.player.volume = 1.0
                timer.invalidate()
            } else {
                self.player.volume = currentVol
            }
        }
    }

    private func finalizePlay(track: LocalTrack, playerItem: AVPlayerItem) {
        isPlaying = true
        updateNowPlaying(track: track)
        attachTimeObserver(duration: track.duration)

        endObserverToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.handleTrackEnded()
        }
    }

    private func handleTrackEnded() {
        switch repeatMode {
        case .one:
            seek(to: 0.0)
            player.play()
        case .all:
            forward()
        case .off:
            if queueIndex + 1 < queue.count {
                forward()
            } else {
                player.pause()
                isPlaying = false
                seek(to: 0.0)
                updatePlaybackState()
            }
        }
    }

    func toggleShuffle() {
        isShuffle.toggle()
        guard let current = currentTrack else { return }

        if isShuffle {
            var pool = originalQueue.filter { $0.id != current.id }
            pool.shuffle()
            queue = [current] + pool
            queueIndex = 0
        } else {
            queue = originalQueue
            queueIndex = queue.firstIndex(where: { $0.id == current.id }) ?? 0
        }
    }

    func toggleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
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
        } else if repeatMode == .all && !queue.isEmpty {
            queueIndex = 0
            play(track: queue[queueIndex])
        }
    }

    func backward() {
        if currentTime > 3.0 {
            seek(to: 0.0)
        } else if queueIndex > 0 {
            queueIndex -= 1
            play(track: queue[queueIndex])
        } else if repeatMode == .all && !queue.isEmpty {
            queueIndex = queue.count - 1
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
        
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self, !self.isPlaying else { return .commandFailed }
            self.togglePlayPause()
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self, self.isPlaying else { return .commandFailed }
            self.togglePlayPause()
            return .success
        }

        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.forward()
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.backward()
            return .success
        }

        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: positionEvent.positionTime)
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
                self?.updatePlaybackState()
            }
        }
    }

    private func updateNowPlaying(track: LocalTrack) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
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
