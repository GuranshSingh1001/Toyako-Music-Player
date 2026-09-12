import AVFoundation
import MediaPlayer
import Combine
import UIKit

// MARK: - Playback Clock

/// Publishes only the fast, continuously-changing playback position
/// (currentTime / playbackProgress), updated ~4x/sec while a track plays.
///
/// This is deliberately its own ObservableObject, separate from
/// AudioEngineManager. Any view holding `@EnvironmentObject var audioManager`
/// re-renders on EVERY @Published change on that object, even if the view
/// never reads currentTime/playbackProgress. Because dozens of views
/// (including the Home screen) hold a reference to AudioEngineManager just
/// to read currentTrack/isPlaying, keeping the position ticker on the same
/// object was invalidating and rebuilding those screens 4 times a second
/// during playback — the cause of the "unstable" Home screen. Only the
/// scrubber/progress UI (MiniPlayerView, NowPlayingView) observes this
/// clock, so everything else stays quiet while a song plays.
final class PlaybackClock: ObservableObject {
    @Published var currentTime: TimeInterval = 0.0
    @Published var playbackProgress: Double = 0.0
}

// MARK: - Audio Engine Manager

class AudioEngineManager: ObservableObject {

    private let player =
        AVPlayer()

    private var timeObserverToken:
        Any?

    // Invalidates callbacks already queued by AVPlayer when the item/observer changes.
    private var timeObserverGeneration: UInt = 0

    // Prevents a queued pre-seek callback from overwriting the requested position.
    private var pendingSeekTarget: TimeInterval?
    private var pendingSeekTrackID: UUID?

    private var endObserverToken:
        Any?

    private var lastPersistedTime:
        TimeInterval = -100

    private var didAttemptRestore =
        false



    // MARK: Published State


    @Published var currentTrack:
        LocalTrack?

    @Published var isPlaying:
        Bool = false

    /// Fast-ticking playback position, kept off this object on purpose.
    /// See PlaybackClock above. Read/write it exactly like before
    /// (`currentTime = ...`) — these are passthroughs, not new call sites.
    let clock = PlaybackClock()

    var currentTime: TimeInterval {
        get { clock.currentTime }
        set { clock.currentTime = newValue }
    }

    var playbackProgress: Double {
        get { clock.playbackProgress }
        set { clock.playbackProgress = newValue }
    }

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

    /// Small local history used by the Home screen. Artwork is intentionally
    /// not persisted, so loading it adds essentially no startup cost.
    @Published private(set) var recentlyPlayed:
        [LocalTrack] = []


    // MARK: Initialization

    init() {


        loadRecentlyPlayed()
        setupRemoteControls()
        setupInterruptionHandling()
    }


    // MARK: Player Item

    private func makePlayerItem(
        url: URL
    ) -> AVPlayerItem {

        let asset =
            AVURLAsset(
                url: url,
                options: [
                    AVURLAssetPreferPreciseDurationAndTimingKey:
                        false
                ]
            )

        let item =
            AVPlayerItem(
                asset: asset
            )


        return item
    }



    // MARK: - Recently Played

    private let recentlyPlayedKey = "Toyako.RecentlyPlayed.v1"
    private let recentlyPlayedLimit = 12

    private func loadRecentlyPlayed() {
        let cache = ToyakoUnifiedCache.load()
        if let cache, !cache.recentlyPlayed.isEmpty {
            recentlyPlayed = cache.recentlyPlayed
            return
        }

        // Legacy UserDefaults migration. The next write is folded into the
        // single ToyakoCache.bin file.
        if let data = UserDefaults.standard.data(forKey: recentlyPlayedKey),
           let decoded = try? JSONDecoder().decode([LocalTrack].self, from: data) {
            recentlyPlayed = decoded
            saveRecentlyPlayedCache()
            UserDefaults.standard.removeObject(forKey: recentlyPlayedKey)
        } else if let cache {
            recentlyPlayed = cache.recentlyPlayed
        }
    }

    private func saveRecentlyPlayedCache() {
        let value = recentlyPlayed
        Task.detached(priority: .utility) {
            ToyakoUnifiedCache.update { cache in
                cache.recentlyPlayed = value
            }
        }
    }

    private func recordRecentlyPlayed(_ track: LocalTrack) {
        recentlyPlayed.removeAll {
            $0.url.standardizedFileURL == track.url.standardizedFileURL
        }

        recentlyPlayed.insert(track, at: 0)

        if recentlyPlayed.count > recentlyPlayedLimit {
            recentlyPlayed.removeLast(recentlyPlayed.count - recentlyPlayedLimit)
        }

        saveRecentlyPlayedCache()
    }

    // MARK: - Persistent Playback / Resume

    func savePlaybackState(
        force: Bool = false
    ) {

        guard currentTrack != nil else {
            return
        }

        if !force &&
            abs(currentTime - lastPersistedTime) < 2.0 {
            return
        }

        lastPersistedTime = currentTime

        let state = ToyakoPlaybackState(
            queue: queue,
            originalQueue: originalQueue,
            queueIndex: queueIndex,
            currentTrackID: currentTrack?.id,
            position: currentTime,
            isPlaying: isPlaying,
            isShuffle: isShuffle,
            repeatMode: repeatMode
        )

        Task.detached(priority: .utility) {
            ToyakoUnifiedCache.savePlaybackState(state)
        }
    }


    /// Replaces cached queue/current-track metadata with
    /// the latest library objects.
    func synchronizeLibrary(
        _ libraryTracks: [LocalTrack]
    ) {

        guard
            !libraryTracks.isEmpty
        else {
            return
        }

        func resolve(
            _ track: LocalTrack
        ) -> LocalTrack? {

            libraryTracks.first {
                $0.url.standardizedFileURL ==
                    track.url.standardizedFileURL
            }
            ??
            libraryTracks.first {
                $0.id == track.id
            }
        }


        if let current = currentTrack,
           let refreshed =
                resolve(current) {

            let trackChanged =
                current.title !=
                    refreshed.title
                ||
                current.artist !=
                    refreshed.artist
                ||
                current.album !=
                    refreshed.album
                ||
                current.duration !=
                    refreshed.duration
                ||
                current.artworkData !=
                    refreshed.artworkData

            if trackChanged {

                currentTrack =
                    refreshed

                loadLyrics(
                    for:
                        refreshed
                )

                updateNowPlaying(
                    track:
                        refreshed
                )
            }
        }


        let refreshedQueue =
            queue.compactMap(resolve)

        let refreshedOriginal =
            originalQueue.compactMap(resolve)


        if !refreshedQueue.isEmpty {

            queue =
                refreshedQueue

            if let currentID =
                currentTrack?.id,

               let currentIndex =
                queue.firstIndex(
                    where:
                        {
                            $0.id ==
                                currentID
                        }
                ) {

                queueIndex =
                    currentIndex

            } else if let currentURL =
                currentTrack?.url.standardizedFileURL,

                      let currentIndex =
                        queue.firstIndex(
                            where:
                                {
                                    $0.url
                                        .standardizedFileURL ==
                                        currentURL
                                }
                        ) {

                queueIndex =
                    currentIndex
            }
        }


        if !refreshedOriginal.isEmpty {

            originalQueue =
                refreshedOriginal
        }


        if currentTrack != nil {

            savePlaybackState(
                force:
                    true
            )
        }
    }


    func restoreIfPossible(
        from libraryTracks:
            [LocalTrack]
    ) {

        guard
            !didAttemptRestore,
            !libraryTracks.isEmpty
        else {
            return
        }

        let state: ToyakoPlaybackState? = {
            if let state = ToyakoUnifiedCache.loadPlaybackState() {
                return state
            }

            if let cache = ToyakoUnifiedCache.load(),
               let state = cache.playbackState {
                ToyakoUnifiedCache.savePlaybackState(state)
                return state
            }

            // One-time migration from the previous UserDefaults JSON cache.
            if let data = UserDefaults.standard.data(forKey: "Toyako.PlaybackState.v2"),
               let legacy = try? JSONDecoder().decode(ToyakoPlaybackState.self, from: data) {
                ToyakoUnifiedCache.update { cache in
                    cache.playbackState = legacy
                }
                UserDefaults.standard.removeObject(forKey: "Toyako.PlaybackState.v2")
                return legacy
            }
            return nil
        }()

        guard let state, let savedCurrentID = state.currentTrackID else {
            return
        }


        func resolve(
            _ saved: LocalTrack
        ) -> LocalTrack? {

            libraryTracks.first {
                $0.id == saved.id
            }
            ??
            libraryTracks.first {
                $0.url.standardizedFileURL ==
                    saved.url.standardizedFileURL
            }
        }


        let restoredQueue =
            state.queue.compactMap(resolve)

        let restoredOriginal =
            state.originalQueue.compactMap(resolve)


        let current:
            LocalTrack?

        if let libraryCurrent =
            libraryTracks.first(
                where:
                    {
                        $0.id ==
                            savedCurrentID
                    }
            ) {

            current =
                libraryCurrent

        } else {

            current =
                restoredQueue.first(
                    where:
                        {
                            $0.id ==
                                savedCurrentID
                        }
                )
        }


        guard let current else {
            return
        }


        // The library can be populated asynchronously. Do not mark restore as
        // completed until the saved state has actually been decoded and its
        // current track has been resolved. Otherwise an early call made while
        // the library is empty prevents the real restore on the next update.
        didAttemptRestore =
            true


        originalQueue =
            restoredOriginal.isEmpty
            ? [current]
            : restoredOriginal

        queue =
            restoredQueue.isEmpty
            ? [current]
            : restoredQueue


        if !queue.contains(
            where:
                {
                    $0.id ==
                        current.id
                }
        ) {

            queue.insert(
                current,
                at:
                    0
            )
        }


        queueIndex =
            queue.firstIndex(
                where:
                    {
                        $0.id ==
                            current.id
                    }
            )
            ??
            min(
                max(
                    state.queueIndex,
                    0
                ),
                max(
                    queue.count - 1,
                    0
                )
            )


        isShuffle =
            state.isShuffle

        repeatMode =
            state.repeatMode

        currentTrack =
            current

        pendingSeekTarget = nil
        pendingSeekTrackID = nil

        loadLyrics(
            for:
                current
        )

        detachTimeObserver()
        detachEndObserver()



        let item =
            makePlayerItem(
                url:
                    current.url
            )

        player.replaceCurrentItem(
            with:
                item
        )

        player.volume =
            1.0


        let restoredPosition =
            max(
                0,
                min(
                    state.position,
                    current.duration
                )
            )


        player.seek(
            to:
                CMTime(
                    seconds:
                        restoredPosition,
                    preferredTimescale:
                        600
                )
        )

        currentTime =
            restoredPosition

        playbackProgress =
            current.duration > 0
            ? currentTime /
                current.duration
            : 0


        isPlaying =
            false

        player.pause()

        updateNowPlaying(
            track:
                current
        )

        attachTimeObserver(
            duration:
                current.duration
        )


        endObserverToken =
            NotificationCenter.default.addObserver(
                forName:
                    .AVPlayerItemDidPlayToEndTime,

                object:
                    item,

                queue:
                    .main

            ) { [weak self] _ in

                self?.handleTrackEnded()
            }


        savePlaybackState(
            force:
                true
        )
    }


    // MARK: - Queue

    func enqueue(
        _ tracks: [LocalTrack]
    ) {

        guard
            !tracks.isEmpty
        else {
            return
        }


        if queue.isEmpty {

            originalQueue =
                tracks

            queue =
                tracks

            queueIndex =
                0

            play(
                track:
                    tracks[0]
            )

            savePlaybackState(
                force:
                    true
            )

            return
        }


        let existingIDs =
            Set(
                queue.map(\.id)
            )

        let additions =
            tracks.filter {
                !existingIDs.contains(
                    $0.id
                )
            }

        queue.append(
            contentsOf:
                additions
        )

        originalQueue =
            queue

        savePlaybackState(
            force:
                true
        )
    }


    func playNext(
        _ track: LocalTrack
    ) {

        guard
            !queue.isEmpty
        else {

            enqueue(
                [track]
            )

            return
        }


        if queue.contains(
            where:
                {
                    $0.id ==
                        track.id
                }
        ) {
            return
        }


        let insertionIndex =
            min(
                queueIndex + 1,
                queue.count
            )

        queue.insert(
            track,
            at:
                insertionIndex
        )

        originalQueue =
            queue

        savePlaybackState(
            force:
                true
        )
    }


    func removeFromQueue(
        at offsets: IndexSet
    ) {

        let currentID =
            currentTrack?.id

        let removedCurrent =
            offsets.contains(
                queueIndex
            )

        queue.remove(
            atOffsets:
                offsets
        )


        guard
            !queue.isEmpty
        else {

            if let current =
                currentTrack {

                queue =
                    [current]

                queueIndex =
                    0

            } else {

                queueIndex =
                    0
            }

            originalQueue =
                queue

            savePlaybackState(
                force:
                    true
            )

            return
        }


        if removedCurrent,
           let currentID,
           let newIndex =
                queue.firstIndex(
                    where:
                        {
                            $0.id ==
                                currentID
                        }
                ) {

            queueIndex =
                newIndex

        } else {

            let removedBeforeCurrent =
                offsets.filter {
                    $0 < queueIndex
                }.count

            queueIndex =
                max(
                    0,
                    min(
                        queueIndex -
                            removedBeforeCurrent,
                        queue.count - 1
                    )
                )
        }


        originalQueue =
            queue

        savePlaybackState(
            force:
                true
        )
    }


    func moveQueue(
        from source: IndexSet,
        to destination: Int
    ) {

        guard
            !source.isEmpty
        else {
            return
        }

        let currentID =
            currentTrack?.id

        queue.move(
            fromOffsets:
                source,

            toOffset:
                destination
        )

        queueIndex =
            currentID.flatMap {
                id in

                queue.firstIndex {
                    $0.id == id
                }

            }
            ??
            0

        originalQueue =
            queue

        savePlaybackState(
            force:
                true
        )
    }


    func clearQueue() {

        guard
            let current =
                currentTrack
        else {

            queue.removeAll()

            originalQueue.removeAll()

            queueIndex =
                0

            savePlaybackState(
                force:
                    true
            )

            return
        }


        queue =
            [current]

        originalQueue =
            [current]

        queueIndex =
            0

        savePlaybackState(
            force:
                true
        )
    }


    func playQueuedTrack(
        at index: Int
    ) {

        guard
            queue.indices.contains(index)
        else {
            return
        }

        queueIndex =
            index

        play(
            track:
                queue[index]
        )
    }


    func startQueue(
        tracks: [LocalTrack],
        startIndex: Int
    ) {

        guard
            !tracks.isEmpty,
            tracks.indices.contains(
                startIndex
            )
        else {
            return
        }


        originalQueue =
            tracks


        if isShuffle {

            var shuffled =
                tracks

            let selected =
                shuffled.remove(
                    at:
                        startIndex
                )

            shuffled.shuffle()

            queue =
                [selected] +
                shuffled

            queueIndex =
                0

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
        track:
            LocalTrack
    ) {

        currentTrack =
            track

        recordRecentlyPlayed(track)

        pendingSeekTarget = nil
        pendingSeekTrackID = nil

        currentTime =
            0

        playbackProgress =
            0


        loadLyrics(
            for:
                track
        )

        detachTimeObserver()
        detachEndObserver()



        let playerItem =
            makePlayerItem(
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

            guard
                let self
            else {

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

            guard
                let self
            else {

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


        savePlaybackState(
            force:
                true
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


        guard
            let current =
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
                [current] +
                pool

            queueIndex =
                0

        } else {

            queue =
                originalQueue

            queueIndex =
                queue.firstIndex {
                    $0.id ==
                        current.id
                }
                ??
                0
        }


        savePlaybackState(
            force:
                true
        )
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


        savePlaybackState(
            force:
                true
        )
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

        savePlaybackState(
            force:
                true
        )
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

        } else if repeatMode ==
                    .all &&
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

        } else if repeatMode ==
                    .all &&
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

        guard
            let duration =
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


        pendingSeekTarget = clampedTime
        pendingSeekTrackID = currentTrack?.id

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
            clampedTime /
            duration


        updatePlaybackState()

        savePlaybackState(
            force:
                true
        )
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

        // AVPlayer can already have a callback queued on the main queue.
        // Invalidate this observer before removing it so that callback cannot
        // mutate the UI state after a new item/observer is installed.
        timeObserverGeneration &+= 1

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

        guard
            duration > 0,
            let observedItem = player.currentItem
        else {
            return
        }

        // Capture both the observer generation and the exact AVPlayerItem.
        // This makes stale callbacks harmless after a track change.
        timeObserverGeneration &+= 1
        let observerGeneration = timeObserverGeneration
        let observedTrackID = currentTrack?.id

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

                guard
                    let self
                else {
                    return
                }

                // Ignore callbacks belonging to an old item or old observer.
                guard
                    self.timeObserverGeneration == observerGeneration,
                    self.player.currentItem === observedItem,
                    self.currentTrack?.id == observedTrackID
                else {
                    return
                }

                let seconds =
                    CMTimeGetSeconds(
                        time
                    )

                guard
                    seconds.isFinite
                else {
                    return
                }

                // A seek is published immediately by seek(). AVPlayer can then
                // deliver a callback from just before the seek completed. Ignore
                // that stale value until the player reaches the requested point.
                if let target = self.pendingSeekTarget,
                   self.pendingSeekTrackID == observedTrackID {
                    if abs(seconds - target) > 0.75 {
                        return
                    }

                    self.pendingSeekTarget = nil
                    self.pendingSeekTrackID = nil
                }

                let clampedSeconds =
                    max(
                        0,
                        min(
                            seconds,
                            duration
                        )
                    )

                self.currentTime =
                    clampedSeconds

                self.playbackProgress =
                    max(
                        0,
                        min(
                            clampedSeconds /
                                duration,
                            1
                        )
                    )

                self.savePlaybackState()
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

            guard
                let self,
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

            guard
                let self,
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

                guard
                    let positionEvent =
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

        // artworkData is deliberately not hydrated into LocalTrack. Artwork is
        // kept in ArtworkStore so playback cannot invalidate the entire Home
        // hierarchy. Publish metadata immediately, then load the cached/extracted
        // cover and attach it to the system Now Playing card independently.
        if let data =
            track.artworkData,
           let image =
            UIImage(data: data) {

            info[
                MPMediaItemPropertyArtwork
            ] =
                Self.makeNowPlayingArtwork(image)
        }

        MPNowPlayingInfoCenter
            .default()
            .nowPlayingInfo = info

        // Most tracks arrive with artworkData == nil by design. Pull the same
        // shared artwork cache used by the UI, without touching currentTrack or
        // the published library state. The track ID check prevents a slow cover
        // extraction from being applied after the user has moved to another song.
        guard track.artworkData == nil else { return }

        let trackID = track.id
        let url = track.url

        Task { [weak self] in
            let data = await ArtworkStore.shared.data(for: url)
            guard let data,
                  let image = UIImage(data: data) else {
                return
            }

            await MainActor.run {
                guard let self,
                      self.currentTrack?.id == trackID else {
                    return
                }

                let center =
                    MPNowPlayingInfoCenter
                        .default()

                var currentInfo =
                    center.nowPlayingInfo ?? [:]

                currentInfo[
                    MPMediaItemPropertyArtwork
                ] =
                    Self.makeNowPlayingArtwork(image)

                center.nowPlayingInfo = currentInfo
            }
        }
    }

    private static func makeNowPlayingArtwork(
        _ image: UIImage
    ) -> MPMediaItemArtwork {
        MPMediaItemArtwork(
            boundsSize: image.size
        ) { _ in
            image
        }
    }


    // MARK: - Live Now Playing Updates

    private func updatePlaybackState() {

        guard
            currentTrack != nil
        else {
            return
        }


        var info =
            MPNowPlayingInfoCenter
                .default()
                .nowPlayingInfo
            ??
            [:]


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


    // MARK: - Deinitialization

    deinit {

        savePlaybackState(
            force:
                true
        )

        detachTimeObserver()
        detachEndObserver()
    }
}
