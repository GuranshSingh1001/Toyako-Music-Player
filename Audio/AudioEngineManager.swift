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

// MARK: - Lyrics Sources

struct LyricsSource: Identifiable, Equatable {
    let id: String
    let displayName: String
    let format: String
    let lyrics: [LyricLine]
}

// MARK: - Audio Engine Manager

class AudioEngineManager: ObservableObject {

    private var player: AVQueuePlayer = AVQueuePlayer()
    private var secondaryPlayer: AVQueuePlayer = AVQueuePlayer()

    private var timeObserverToken:
        Any?

    // Invalidates callbacks already queued by AVPlayer when the item/observer changes.
    private var timeObserverGeneration: UInt = 0

    // Prevents a queued pre-seek callback from overwriting the requested position.
    private var pendingSeekTarget: TimeInterval?
    private var pendingSeekTrackID: UUID?

    private var endObserverToken:
        Any?

    private var interruptionObserverToken: NSObjectProtocol?
    private var remoteCommandTargets: [(command: MPRemoteCommand, token: Any)] = []
    private var fadeOutTimer: Timer?
    private var fadeInTimer: Timer?

    private var lastPersistedTime:
        TimeInterval = -100

    private var didAttemptRestore =
        false



    // MARK: Published State


    @Published var currentTrack:
        LocalTrack?

    @Published var isPlaying:
        Bool = false

    /// App playback volume used by the compact Now Playing volume slider.
    /// This is AVPlayer volume, not the device's system volume.
    @Published private(set) var volume: Float = 1.0

    func setVolume(_ value: Float) {
        let clamped = min(1.0, max(0.0, value))
        volume = clamped
        player.volume = clamped
    }

    func setCrossfadeDuration(_ value: TimeInterval) {
        let clamped = min(3.0, max(0.5, value))
        crossfadeDuration = clamped
        UserDefaults.standard.set(clamped, forKey: ToyakoPreferences.crossfadeDurationKey)
    }

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

    /// All valid lyric files found for the current track. TTML and LRC are
    /// kept as separate sources so the user can switch between them without
    /// changing the audio track.
    @Published private(set) var lyricsSources: [LyricsSource] = []

    @Published private(set) var selectedLyricsSourceID: String?

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

    @Published var crossfadeDuration:
        TimeInterval = 0.45

    @Published var gaplessEnabled:
        Bool = true

    /// Small local history used by the Home screen. Artwork is intentionally
    /// not persisted, so loading it adds essentially no startup cost.
    @Published private(set) var recentlyPlayed:
        [LocalTrack] = []


    // MARK: Initialization

    init() {
        ToyakoPreferences.registerDefaults()
        crossfadeEnabled = UserDefaults.standard.bool(forKey: ToyakoPreferences.crossfadeKey)
        crossfadeDuration = UserDefaults.standard.double(forKey: ToyakoPreferences.crossfadeDurationKey)
        gaplessEnabled = UserDefaults.standard.bool(forKey: ToyakoPreferences.gaplessKey)
        if crossfadeDuration < 0.5 || crossfadeDuration > 3.0 {
            crossfadeDuration = 0.75
        }

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

        let refreshedHistory = recentlyPlayed.compactMap(resolve)
        if refreshedHistory != recentlyPlayed {
            recentlyPlayed = refreshedHistory
            saveRecentlyPlayedCache()
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
            volume


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

        cancelTransitionFades()

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


        if crossfadeEnabled && isPlaying {
            fadeOutAndSwitch(
                to: playerItem,
                track: track
            )
        } else if gaplessEnabled && !crossfadeEnabled {
            playGapless(
                track: track,
                playerItem: playerItem
            )
        } else {
            player.volume = volume
            player.removeAllItems()
            player.replaceCurrentItem(with: playerItem)
            player.play()
            finalizePlay(track: track, playerItem: playerItem)
        }
    }


    // MARK: - Gapless Playback

    /// Uses AVQueuePlayer so the next queued item is prepared before the
    /// current item reaches its end. Crossfade deliberately takes precedence
    /// when enabled because it requires overlapping volume control.
    private func playGapless(track: LocalTrack, playerItem: AVPlayerItem) {
        cancelTransitionFades()
        player.removeAllItems()
        player.insert(playerItem, after: nil)

        if queue.indices.contains(queueIndex + 1) {
            for nextTrack in queue[(queueIndex + 1)...] {
                player.insert(makePlayerItem(url: nextTrack.url), after: player.items().last)
            }
        } else if repeatMode == .all && !queue.isEmpty {
            for nextTrack in queue {
                player.insert(makePlayerItem(url: nextTrack.url), after: player.items().last)
            }
        }

        player.volume = volume
        player.play()
        finalizePlay(track: track, playerItem: playerItem)
    }

    // MARK: - Crossfade

    private func cancelTransitionFades() {
        fadeOutTimer?.invalidate()
        fadeOutTimer = nil
        fadeInTimer?.invalidate()
        fadeInTimer = nil
    }

    private func fadeOutAndSwitch(
        to newItem: AVPlayerItem,
        track: LocalTrack
    ) {
        cancelTransitionFades()

        let oldPlayer = player
        let newPlayer = secondaryPlayer
        let duration = max(0.5, min(3.0, crossfadeDuration))
        let targetVolume = volume
        let startDate = Date()

        newPlayer.pause()
        newPlayer.removeAllItems()
        newPlayer.volume = 0
        newPlayer.insert(newItem, after: nil)
        newPlayer.play()

        fadeOutTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self, weak oldPlayer, weak newPlayer] timer in
            guard let self, let oldPlayer, let newPlayer else {
                timer.invalidate()
                return
            }

            let progress = min(1, max(0, Date().timeIntervalSince(startDate) / duration))
            let curve = progress * progress * (3 - 2 * progress)

            oldPlayer.volume = targetVolume * Float(1 - curve)
            newPlayer.volume = targetVolume * Float(curve)

            guard progress >= 1 else { return }

            timer.invalidate()
            self.fadeOutTimer = nil
            oldPlayer.pause()
            oldPlayer.removeAllItems()
            newPlayer.volume = targetVolume

            self.player = newPlayer
            self.secondaryPlayer = oldPlayer
            self.finalizePlay(track: track, playerItem: newItem)
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
            play(track: queue.indices.contains(queueIndex) ? queue[queueIndex] : currentTrack ?? queue.first!)

        case .all:
            if gaplessEnabled && !crossfadeEnabled {
                if queueIndex + 1 < queue.count {
                    queueIndex += 1
                    let next = queue[queueIndex]
                    currentTrack = next
                    recordRecentlyPlayed(next)
                    loadLyrics(for: next)
                    currentTime = 0
                    playbackProgress = 0
                    if let item = player.items().first {
                        detachTimeObserver()
                        detachEndObserver()
                        finalizePlay(track: next, playerItem: item)
                    }
                } else {
                    queueIndex = 0
                    play(track: queue[0])
                }
            } else {
                forward()
            }

        case .off:
            if queueIndex + 1 < queue.count {
                if gaplessEnabled && !crossfadeEnabled {
                    queueIndex += 1
                    let next = queue[queueIndex]
                    currentTrack = next
                    recordRecentlyPlayed(next)
                    loadLyrics(for: next)
                    currentTime = 0
                    playbackProgress = 0
                    if let item = player.items().first {
                        detachTimeObserver()
                        detachEndObserver()
                        finalizePlay(track: next, playerItem: item)
                    }
                } else {
                    forward()
                }
            } else {
                player.pause()
                isPlaying = false
                currentTime = 0
                playbackProgress = 0
                updatePlaybackState()
            }
        }
    }


    // MARK: - Shuffle

    func setCrossfadeEnabled(_ enabled: Bool) {
        crossfadeEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: ToyakoPreferences.crossfadeKey)
    }

    func setGaplessEnabled(_ enabled: Bool) {
        gaplessEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: ToyakoPreferences.gaplessKey)
    }

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
        for track: LocalTrack
    ) {
        let fileManager = FileManager.default
        let audioURL = track.url.standardizedFileURL
        let directoryURL = audioURL.deletingLastPathComponent()
        let audioName = audioURL.deletingPathExtension().lastPathComponent

        var sources: [LyricsSource] = []

        // ---------------------------------------------------------
        // TTML
        //
        // Exact sidecar first: Song.m4a -> Song.ttml
        // ---------------------------------------------------------
        let exactTTMLURL = directoryURL
            .appendingPathComponent(audioName)
            .appendingPathExtension("ttml")

        var ttmlURL: URL?

        if fileManager.fileExists(atPath: exactTTMLURL.path) {
            ttmlURL = exactTTMLURL
        } else if let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            ttmlURL = files.first { url in
                guard url.pathExtension.lowercased() == "ttml" else { return false }
                let lyricName = url.deletingPathExtension().lastPathComponent
                return lyricName.compare(
                    audioName,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) == .orderedSame
            }
        }

        if let ttmlURL,
           let content = readLyricsFile(ttmlURL) {
            let parsed = TTMLParser.parse(content: content)
            if !parsed.isEmpty {
                sources.append(
                    LyricsSource(
                        id: "ttml",
                        displayName: "Timed Lyrics",
                        format: "TTML",
                        lyrics: parsed
                    )
                )
            }
        }

        // ---------------------------------------------------------
        // LRC fallback/source.
        //
        // It is now retained even when valid TTML exists, so users can
        // explicitly switch between the two available lyric versions.
        // ---------------------------------------------------------
        let lrcURL = directoryURL
            .appendingPathComponent(audioName)
            .appendingPathExtension("lrc")

        if let content = readLyricsFile(lrcURL) {
            let parsed = LRCParser.parse(content: content)
            if !parsed.isEmpty {
                sources.append(
                    LyricsSource(
                        id: "lrc",
                        displayName: "LRC Lyrics",
                        format: "LRC",
                        lyrics: parsed
                    )
                )
            }
        }

        lyricsSources = sources

        // TTML is the default lyric format whenever a valid matching
        // TTML sidecar is available. LRC remains available as a manual
        // fallback/source choice through the lyric source selector.
        if let ttml = sources.first(where: { $0.id == "ttml" }) {
            selectedLyricsSourceID = ttml.id
            currentLyrics = ttml.lyrics
        } else if let preferred = sources.first(where: { $0.id == selectedLyricsSourceID }) {
            currentLyrics = preferred.lyrics
        } else if let first = sources.first {
            selectedLyricsSourceID = first.id
            currentLyrics = first.lyrics
        } else {
            selectedLyricsSourceID = nil
            currentLyrics = []
        }
    }

    /// Switches the active lyric source without reloading or interrupting
    /// playback. The Now Playing lyric view automatically re-anchors to the
    /// current playback position because currentLyrics is published.
    func selectLyricsSource(_ sourceID: String) {
        guard let source = lyricsSources.first(where: { $0.id == sourceID }) else {
            return
        }

        selectedLyricsSourceID = source.id
        currentLyrics = source.lyrics
    }

    private func readLyricsFile(
        _ url: URL
    ) -> String? {

        guard FileManager.default.fileExists(
            atPath: url.path
        ) else {
            return nil
        }

        if let content =
            try? String(
                contentsOf:
                    url,
                encoding:
                    .utf8
            ) {

            return content
        }

        if let content =
            try? String(
                contentsOf:
                    url,
                encoding:
                    .utf16
            ) {

            return content
        }

        if let content =
            try? String(
                contentsOf:
                    url,
                encoding:
                    .utf16LittleEndian
            ) {

            return content
        }

        if let content =
            try? String(
                contentsOf:
                    url,
                encoding:
                    .utf16BigEndian
            ) {

            return content
        }

        return nil
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
        let commandCenter = MPRemoteCommandCenter.shared()

        let playTarget = commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self, !self.isPlaying else { return .commandFailed }
            self.togglePlayPause()
            return .success
        }
        remoteCommandTargets.append((commandCenter.playCommand, playTarget))
        commandCenter.playCommand.isEnabled = true

        let pauseTarget = commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.isPlaying else { return .commandFailed }
            self.togglePlayPause()
            return .success
        }
        remoteCommandTargets.append((commandCenter.pauseCommand, pauseTarget))
        commandCenter.pauseCommand.isEnabled = true

        let nextTarget = commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.forward()
            return .success
        }
        remoteCommandTargets.append((commandCenter.nextTrackCommand, nextTarget))
        commandCenter.nextTrackCommand.isEnabled = true

        let previousTarget = commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.backward()
            return .success
        }
        remoteCommandTargets.append((commandCenter.previousTrackCommand, previousTarget))
        commandCenter.previousTrackCommand.isEnabled = true

        commandCenter.changePlaybackPositionCommand.isEnabled = true
        let positionTarget = commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.seek(to: positionEvent.positionTime)
            return .success
        }
        remoteCommandTargets.append((commandCenter.changePlaybackPositionCommand, positionTarget))
    }


    // MARK: - Audio Interruptions

    private func setupInterruptionHandling() {

        interruptionObserverToken = NotificationCenter.default.addObserver(
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

        cancelTransitionFades()
        detachTimeObserver()
        detachEndObserver()

        if let interruptionObserverToken {
            NotificationCenter.default.removeObserver(interruptionObserverToken)
        }

        for target in remoteCommandTargets {
            target.command.removeTarget(target.token)
        }
        remoteCommandTargets.removeAll()
    }
}
