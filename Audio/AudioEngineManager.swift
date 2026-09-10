import AVFoundation
import MediaPlayer
import Combine


private struct PlaybackPersistenceState: Codable {
    let queue: [LocalTrack]
    let originalQueue: [LocalTrack]
    let queueIndex: Int
    let currentTrackID: UUID?
    let position: TimeInterval
    let isPlaying: Bool
    let isShuffle: Bool
    let repeatMode: RepeatMode
}

class AudioEngineManager: ObservableObject {
    private let player = AVPlayer()

    private var timeObserverToken: Any?
    private var endObserverToken: Any?
    private var lastPersistedTime: TimeInterval = -100
    private var didAttemptRestore = false

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

    // MARK: - Persistent Playback / Resume

    private let persistenceKey = "Toyako.PlaybackState.v2"

    func savePlaybackState(force: Bool = false) {
        guard currentTrack != nil else { return }
        if !force && abs(currentTime - lastPersistedTime) < 2.0 { return }
        lastPersistedTime = currentTime

        let state = PlaybackPersistenceState(
            queue: queue,
            originalQueue: originalQueue,
            queueIndex: queueIndex,
            currentTrackID: currentTrack?.id,
            position: currentTime,
            isPlaying: isPlaying,
            isShuffle: isShuffle,
            repeatMode: repeatMode
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: persistenceKey)
        }
    }

    func restoreIfPossible(from libraryTracks: [LocalTrack]) {
        guard !didAttemptRestore, !libraryTracks.isEmpty else { return }
        didAttemptRestore = true
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let state = try? JSONDecoder().decode(PlaybackPersistenceState.self, from: data),
              let savedCurrentID = state.currentTrackID else { return }

        func resolve(_ saved: LocalTrack) -> LocalTrack? {
            libraryTracks.first(where: { $0.id == saved.id })
                ?? libraryTracks.first(where: { $0.url.standardizedFileURL == saved.url.standardizedFileURL })
        }

        let restoredQueue = state.queue.compactMap(resolve)
        let restoredOriginal = state.originalQueue.compactMap(resolve)
        guard let current = libraryTracks.first(where: { $0.id == savedCurrentID })
                ?? restoredQueue.first(where: { $0.id == savedCurrentID }) else { return }

        originalQueue = restoredOriginal.isEmpty ? [current] : restoredOriginal
        queue = restoredQueue.isEmpty ? [current] : restoredQueue
        if !queue.contains(where: { $0.id == current.id }) { queue.insert(current, at: 0) }
        queueIndex = queue.firstIndex(where: { $0.id == current.id }) ?? min(max(state.queueIndex, 0), max(queue.count - 1, 0))
        isShuffle = state.isShuffle
        repeatMode = state.repeatMode

        currentTrack = current
        loadLyrics(for: current)
        detachTimeObserver()
        detachEndObserver()

        let item = AVPlayerItem(url: current.url)
        player.replaceCurrentItem(with: item)
        player.volume = 1.0
        player.seek(to: CMTime(seconds: max(0, min(state.position, current.duration)), preferredTimescale: 600))
        currentTime = max(0, min(state.position, current.duration))
        playbackProgress = current.duration > 0 ? currentTime / current.duration : 0
        isPlaying = state.isPlaying
        if state.isPlaying { player.play() }
        updateNowPlaying(track: current)
        attachTimeObserver(duration: current.duration)
        endObserverToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in self?.handleTrackEnded() }
        savePlaybackState(force: true)
    }

    // MARK: - Queue

    func enqueue(_ tracks: [LocalTrack]) {
        guard !tracks.isEmpty else { return }
        if queue.isEmpty {
            originalQueue = tracks
            queue = tracks
            queueIndex = 0
            play(track: tracks[0])
            savePlaybackState(force: true)
            return
        }

        let existingIDs = Set(queue.map(\.id))
        let additions = tracks.filter { !existingIDs.contains($0.id) }
        queue.append(contentsOf: additions)
        originalQueue = queue
        savePlaybackState(force: true)
    }

    func playNext(_ track: LocalTrack) {
        guard !queue.isEmpty else {
            enqueue([track])
            return
        }
        if queue.contains(where: { $0.id == track.id }) { return }
        let insertionIndex = min(queueIndex + 1, queue.count)
        queue.insert(track, at: insertionIndex)
        originalQueue = queue
        savePlaybackState(force: true)
    }

    func removeFromQueue(at offsets: IndexSet) {
        let currentID = currentTrack?.id
        let removedCurrent = offsets.contains(queueIndex)
        queue.remove(atOffsets: offsets)
        guard !queue.isEmpty else {
            if let current = currentTrack {
                queue = [current]
                queueIndex = 0
            } else {
                queueIndex = 0
            }
            originalQueue = queue
            savePlaybackState(force: true)
            return
        }

        if removedCurrent, let currentID,
           let newIndex = queue.firstIndex(where: { $0.id == currentID }) {
            queueIndex = newIndex
        } else {
            let removedBeforeCurrent = offsets.filter { $0 < queueIndex }.count
            queueIndex = max(0, min(queueIndex - removedBeforeCurrent, queue.count - 1))
        }
        originalQueue = queue
        savePlaybackState(force: true)
    }

    func moveQueue(from source: IndexSet, to destination: Int) {
        guard !source.isEmpty else { return }
        let currentID = currentTrack?.id
        queue.move(fromOffsets: source, toOffset: destination)
        queueIndex = currentID.flatMap { id in queue.firstIndex(where: { $0.id == id }) } ?? 0
        originalQueue = queue
        savePlaybackState(force: true)
    }

    func clearQueue() {
        guard let current = currentTrack else {
            queue.removeAll()
            originalQueue.removeAll()
            queueIndex = 0
            savePlaybackState(force: true)
            return
        }
        queue = [current]
        originalQueue = [current]
        queueIndex = 0
        savePlaybackState(force: true)
    }

    func playQueuedTrack(at index: Int) {
        guard queue.indices.contains(index) else { return }
        queueIndex = index
        play(track: queue[index])
    }

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

        savePlaybackState(force: true)

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
        savePlaybackState(force: true)
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
        savePlaybackState(force: true)
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
        savePlaybackState(force: true)
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
        savePlaybackState(force: true)
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

                self.savePlaybackState()

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
        savePlaybackState(force: true)
        detachTimeObserver()
        detachEndObserver()
    }
}