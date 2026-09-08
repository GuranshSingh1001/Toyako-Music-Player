import AVFoundation
import MediaPlayer
import Combine

class AudioEngineManager: ObservableObject {
    private let player = AVPlayer()

    private var timeObserverToken: Any?
    private var endObserverToken: Any?

    @Published var currentTrack: LocalTrack?

    @Published var isPlaying: Bool = false

    @Published var currentTime:
        TimeInterval = 0.0

    @Published var playbackProgress:
        Double = 0.0

    @Published var currentLyrics:
        [LyricLine] = []

    @Published var queue:
        [LocalTrack] = []

    @Published var originalQueue:
        [LocalTrack] = []

    @Published var queueIndex:
        Int = 0

    @Published var isShuffle:
        Bool = false

    @Published var repeatMode:
        RepeatMode = .off

    @Published var crossfadeEnabled:
        Bool = true

    init() {
        setupRemoteControls()
        setupInterruptionHandling()
    }

    // MARK: - Queue

    func startQueue(
        tracks: [LocalTrack],
        startIndex: Int
    ) {
        guard
            !tracks.isEmpty,
            tracks.indices.contains(startIndex)
        else {
            return
        }

        originalQueue = tracks

        if isShuffle {
            var shuffled =
                tracks

            let selected =
                shuffled.remove(
                    at: startIndex
                )

            shuffled.shuffle()

            queue =
                [selected] + shuffled

            queueIndex = 0

        } else {
            queue =
                tracks

            queueIndex =
                startIndex
        }

        play(
            track:
                queue[queueIndex]
        )
    }

    // MARK: - Play

    func play(
        track: LocalTrack
    ) {
        currentTrack =
            track

        // Reset UI state immediately when
        // changing songs.
        currentTime = 0
        playbackProgress = 0

        loadLyrics(
            for: track
        )

        detachTimeObserver()
        detachEndObserver()

        let playerItem =
            AVPlayerItem(
                url:
                    track.url
            )

        if crossfadeEnabled &&
            isPlaying {

            fadeOutAndSwitch(
                to:
                    playerItem,
                track:
                    track
            )

        } else {
            player.volume =
                1.0

            player.replaceCurrentItem(
                with:
                    playerItem
            )

            player.play()

            finalizePlay(
                track:
                    track,
                playerItem:
                    playerItem
            )
        }
    }

    // MARK: - Crossfade

    private func fadeOutAndSwitch(
        to newItem:
            AVPlayerItem,
        track:
            LocalTrack
    ) {
        var currentVol =
            player.volume

        Timer.scheduledTimer(
            withTimeInterval:
                0.04,
            repeats:
                true
        ) { [weak self] timer in

            guard let self else {
                timer.invalidate()
                return
            }

            currentVol -=
                0.15

            if currentVol <= 0.05 {

                timer.invalidate()

                self.player.replaceCurrentItem(
                    with:
                        newItem
                )

                self.player.play()

                self.fadeIn()

                self.finalizePlay(
                    track:
                        track,
                    playerItem:
                        newItem
                )

            } else {
                self.player.volume =
                    currentVol
            }
        }
    }

    private func fadeIn() {
        var currentVol:
            Float = 0.0

        player.volume =
            0.0

        Timer.scheduledTimer(
            withTimeInterval:
                0.04,
            repeats:
                true
        ) { [weak self] timer in

            guard let self else {
                timer.invalidate()
                return
            }

            currentVol +=
                0.15

            if currentVol >= 1.0 {

                self.player.volume =
                    1.0

                timer.invalidate()

            } else {
                self.player.volume =
                    currentVol
            }
        }
    }

    // MARK: - Finalize Playback

    private func finalizePlay(
        track:
            LocalTrack,
        playerItem:
            AVPlayerItem
    ) {
        isPlaying =
            true

        currentTime =
            0

        playbackProgress =
            0

        updateNowPlaying(
            track:
                track
        )

        attachTimeObserver(
            duration:
                track.duration
        )

        endObserverToken =
            NotificationCenter.default.addObserver(
                forName:
                    .AVPlayerItemDidPlayToEndTime,
                object:
                    playerItem,
                queue:
                    .main
            ) { [weak self] _ in

                self?.handleTrackEnded()
            }
    }

    // MARK: - Track Ended

    private func handleTrackEnded() {
        switch repeatMode {

        case .one:
            seek(
                to:
                    0.0
            )

            player.play()

            isPlaying =
                true

            updatePlaybackState()

        case .all:
            forward()

        case .off:

            if queueIndex + 1 <
                queue.count {

                forward()

            } else {

                player.pause()

                isPlaying =
                    false

                currentTime =
                    0

                playbackProgress =
                    0

                updatePlaybackState()
            }
        }
    }

    // MARK: - Shuffle

    func toggleShuffle() {
        isShuffle.toggle()

        guard let current =
            currentTrack
        else {
            return
        }

        if isShuffle {

            var pool =
                originalQueue.filter {
                    $0.id != current.id
                }

            pool.shuffle()

            queue =
                [current] + pool

            queueIndex =
                0

        } else {

            queue =
                originalQueue

            queueIndex =
                queue.firstIndex {
                    $0.id == current.id
                } ?? 0
        }
    }

    // MARK: - Repeat

    func toggleRepeat() {
        switch repeatMode {

        case .off:
            repeatMode =
                .all

        case .all:
            repeatMode =
                .one

        case .one:
            repeatMode =
                .off
        }
    }

    // MARK: - Play / Pause

    func togglePlayPause() {

        if isPlaying {
            player.pause()

            isPlaying =
                false

        } else {
            player.play()

            isPlaying =
                true
        }

        updatePlaybackState()
    }

    // MARK: - Next

    func forward() {

        if queueIndex + 1 <
            queue.count {

            queueIndex +=
                1

            play(
                track:
                    queue[queueIndex]
            )

        } else if repeatMode == .all &&
                    !queue.isEmpty {

            queueIndex =
                0

            play(
                track:
                    queue[queueIndex]
            )
        }
    }

    // MARK: - Previous

    func backward() {

        if currentTime > 3.0 {

            seek(
                to:
                    0.0
            )

        } else if queueIndex > 0 {

            queueIndex -=
                1

            play(
                track:
                    queue[queueIndex]
            )

        } else if repeatMode == .all &&
                    !queue.isEmpty {

            queueIndex =
                queue.count - 1

            play(
                track:
                    queue[queueIndex]
            )

        } else {

            seek(
                to:
                    0.0
            )
        }
    }

    // MARK: - Seeking

    func seek(
        to time:
            TimeInterval
    ) {
        guard let duration =
            currentTrack?.duration,
              duration > 0
        else {
            return
        }

        let clampedTime =
            max(
                0,
                min(
                    time,
                    duration
                )
            )

        let cmTime =
            CMTime(
                seconds:
                    clampedTime,
                preferredTimescale:
                    600
            )

        player.seek(
            to:
                cmTime,
            toleranceBefore:
                .zero,
            toleranceAfter:
                .zero
        )

        currentTime =
            clampedTime

        playbackProgress =
            clampedTime / duration

        updatePlaybackState()
    }

    // MARK: - Lyrics

    private func loadLyrics(
        for track:
            LocalTrack
    ) {
        let lrcURL =
            track.url
                .deletingPathExtension()
                .appendingPathExtension(
                    "lrc"
                )

        if let content =
            try? String(
                contentsOf:
                    lrcURL,
                encoding:
                    .utf8
            ) {

            currentLyrics =
                LRCParser.parse(
                    content:
                        content
                )

        } else {
            currentLyrics =
                []
        }
    }

    // MARK: - Time Observer

    private func detachTimeObserver() {

        if let token =
            timeObserverToken {

            player.removeTimeObserver(
                token
            )

            timeObserverToken =
                nil
        }
    }

    private func detachEndObserver() {

        if let token =
            endObserverToken {

            NotificationCenter.default.removeObserver(
                token
            )

            endObserverToken =
                nil
        }
    }

    private func attachTimeObserver(
        duration:
            TimeInterval
    ) {
        guard duration > 0
        else {
            return
        }

        let interval =
            CMTime(
                seconds:
                    0.25,
                preferredTimescale:
                    600
            )

        timeObserverToken =
            player.addPeriodicTimeObserver(
                forInterval:
                    interval,
                queue:
                    .main
            ) { [weak self] time in

                guard let self
                else {
                    return
                }

                let seconds =
                    CMTimeGetSeconds(
                        time
                    )

                guard seconds.isFinite
                else {
                    return
                }

                self.currentTime =
                    max(
                        0,
                        min(
                            seconds,
                            duration
                        )
                    )

                self.playbackProgress =
                    max(
                        0,
                        min(
                            seconds / duration,
                            1
                        )
                    )

                // Continuously refresh Control Center
                // and Lock Screen playback information.
                self.updatePlaybackState()
            }
    }

    // MARK: - Remote Controls

    private func setupRemoteControls() {

        let commandCenter =
            MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled =
            true

        commandCenter.playCommand.addTarget {
            [weak self] _ in

            guard let self,
                  !self.isPlaying
            else {
                return .commandFailed
            }

            self.togglePlayPause()

            return .success
        }

        commandCenter.pauseCommand.isEnabled =
            true

        commandCenter.pauseCommand.addTarget {
            [weak self] _ in

            guard let self,
                  self.isPlaying
            else {
                return .commandFailed
            }

            self.togglePlayPause()

            return .success
        }

        commandCenter.nextTrackCommand.isEnabled =
            true

        commandCenter.nextTrackCommand.addTarget {
            [weak self] _ in

            self?.forward()

            return .success
        }

        commandCenter.previousTrackCommand.isEnabled =
            true

        commandCenter.previousTrackCommand.addTarget {
            [weak self] _ in

            self?.backward()

            return .success
        }

        commandCenter
            .changePlaybackPositionCommand
            .isEnabled =
            true

        commandCenter
            .changePlaybackPositionCommand
            .addTarget {
                [weak self] event in

                guard let positionEvent =
                    event
                    as?
                    MPChangePlaybackPositionCommandEvent
                else {
                    return .commandFailed
                }

                self?.seek(
                    to:
                        positionEvent.positionTime
                )

                return .success
            }
    }

    // MARK: - Audio Interruptions

    private func setupInterruptionHandling() {

        NotificationCenter.default.addObserver(
            forName:
                AVAudioSession.interruptionNotification,
            object:
                nil,
            queue:
                .main
        ) { [weak self] notification in

            guard
                let info =
                    notification.userInfo,

                let typeValue =
                    info[
                        AVAudioSessionInterruptionTypeKey
                    ] as? UInt,

                let type =
                    AVAudioSession.InterruptionType(
                        rawValue:
                            typeValue
                    )
            else {
                return
            }

            if type == .began {

                self?.player.pause()

                self?.isPlaying =
                    false

                self?.updatePlaybackState()
            }
        }
    }

    // MARK: - Now Playing Information

    private func updateNowPlaying(
        track:
            LocalTrack
    ) {

        var info:
            [String: Any] = [

                MPMediaItemPropertyTitle:
                    track.title,

                MPMediaItemPropertyArtist:
                    track.artist,

                MPMediaItemPropertyAlbumTitle:
                    track.album,

                MPMediaItemPropertyPlaybackDuration:
                    track.duration,

                MPNowPlayingInfoPropertyElapsedPlaybackTime:
                    currentTime,

                MPNowPlayingInfoPropertyPlaybackRate:
                    isPlaying
                    ? 1.0
                    : 0.0,

                MPNowPlayingInfoPropertyDefaultPlaybackRate:
                    1.0
            ]

        if let data =
            track.artworkData,

           let image =
            UIImage(data: data) {

            info[
                MPMediaItemPropertyArtwork
            ] =
                MPMediaItemArtwork(
                    boundsSize:
                        image.size
                ) { _ in
                    image
                }
        }

        MPNowPlayingInfoCenter
            .default()
            .nowPlayingInfo =
            info
    }

    // MARK: - Live Now Playing Updates

    private func updatePlaybackState() {

        guard currentTrack != nil
        else {
            return
        }

        var info =
            MPNowPlayingInfoCenter
                .default()
                .nowPlayingInfo
            ?? [:]

        info[
            MPNowPlayingInfoPropertyElapsedPlaybackTime
        ] =
            currentTime

        info[
            MPNowPlayingInfoPropertyPlaybackRate
        ] =
            isPlaying
            ? 1.0
            : 0.0

        info[
            MPNowPlayingInfoPropertyDefaultPlaybackRate
        ] =
            1.0

        if let duration =
            currentTrack?.duration,
           duration > 0 {

            info[
                MPMediaItemPropertyPlaybackDuration
            ] =
                duration
        }

        MPNowPlayingInfoCenter
            .default()
            .nowPlayingInfo =
            info
    }

    deinit {
        detachTimeObserver()
        detachEndObserver()
    }
}