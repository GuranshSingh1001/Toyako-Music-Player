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

    private var timeObserverToken:
        Any?

    // Invalidates callbacks already queued by AVPlayer when the item/observer changes.
    private var timeObserverGeneration: UInt = 0

    // Prevents a queued pre-seek callback from overwriting the requested position.
    private var pendingSeekTarget: TimeInterval?
    private var pendingSeekTrackID: UUID?

    private var endObserverToken:
        Any?

    private var itemStatusObservation: NSKeyValueObservation?

    private var interruptionObserverToken: NSObjectProtocol?
    private var appBackgroundObserverToken: NSObjectProtocol?
    private var appForegroundObserverToken: NSObjectProtocol?
    private var remoteCommandTargets: [(command: MPRemoteCommand, token: Any)] = []
    private var wasPlayingBeforeInterruption = false

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

    /// When a track is played directly from Home/Recently Played, remember
    /// where playback was in the queue so Next/Previous can return to it
    /// without modifying the queue.
    private var suspendedQueueTrackID: LocalTrack.ID?

    @Published var isShuffle:
        Bool = false

    @Published var repeatMode:
        RepeatMode = .off

    /// Small local history used by the Home screen. Artwork is intentionally
    /// not persisted, so loading it adds essentially no startup cost.
    @Published private(set) var recentlyPlayed:
        [LocalTrack] = []


    // MARK: Initialization

    init() {
        ToyakoPlaybackDiagnostics.shared.log("AudioEngineManager init")
        ToyakoPreferences.registerDefaults()
        loadRecentlyPlayed()
        setupRemoteControls()
        setupInterruptionHandling()
        setupApplicationLifecycleHandling()
        setupPlaybackDiagnosticsNotifications()
    }

    private func setupPlaybackDiagnosticsNotifications() {
        let center = NotificationCenter.default
        center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main) { [weak self] notification in
            ToyakoPlaybackDiagnostics.shared.log("NOTIFICATION AVPlayerItemFailedToPlayToEndTime")
            let item = notification.object as? AVPlayerItem
            ToyakoPlaybackDiagnostics.shared.log("ITEM_FAILED_TO_END error=\(item?.error?.localizedDescription ?? "unknown") current=\(self?.currentTrack?.title ?? "nil")")
        }
        center.addObserver(forName: .AVPlayerItemNewErrorLogEntry, object: nil, queue: .main) { [weak self] notification in
            ToyakoPlaybackDiagnostics.shared.log("NOTIFICATION AVPlayerItemNewErrorLogEntry")
            let item = notification.object as? AVPlayerItem
            let entry = item?.errorLog()?.events.last
            ToyakoPlaybackDiagnostics.shared.log("ITEM_ERROR_LOG current=\(self?.currentTrack?.title ?? "nil") entry=\(entry.map { String(describing: $0) } ?? "nil")")
        }
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
                ToyakoPlaybackDiagnostics.shared.log("END_NOTIFICATION item=\(item) current=\(self?.currentTrack?.title ?? "nil") index=\(self?.queueIndex ?? -1)")
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
        ToyakoPlaybackDiagnostics.shared.log("QUEUE_PLAY_NEXT_BEGIN title=\(track.title) id=\(track.id) count=\(queue.count) index=\(queueIndex)")

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
        ToyakoPlaybackDiagnostics.shared.log("QUEUE_REMOVE_BEGIN offsets=\(Array(offsets)) count=\(queue.count) index=\(queueIndex) current=\(currentTrack?.title ?? "nil")")

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
        ToyakoPlaybackDiagnostics.shared.log("QUEUE_MOVE_BEGIN source=\(Array(source)) destination=\(destination) count=\(queue.count) index=\(queueIndex)")

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
        ToyakoPlaybackDiagnostics.shared.log("QUEUE_CLEAR_BEGIN count=\(queue.count) index=\(queueIndex) current=\(currentTrack?.title ?? "nil")")

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
        ToyakoPlaybackDiagnostics.shared.log("QUEUE_PLAY_AT requestedIndex=\(index) count=\(queue.count) currentIndex=\(queueIndex)")

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


    /// Play a track immediately without changing the queue or queue index.
    ///
    /// The first standalone play remembers the queue track that was active.
    /// Next/Previous can then resume from that queue position.
    func playStandalonePreservingQueue(_ track: LocalTrack) {
        ToyakoPlaybackDiagnostics.shared.log("STANDALONE_BEGIN title=\(track.title) id=\(track.id) queueIndex=\(queueIndex) count=\(queue.count) suspended=\(suspendedQueueTrackID?.uuidString ?? "nil")")
        guard !queue.isEmpty else {
            play(track: track)
            return
        }

        if suspendedQueueTrackID == nil,
           queue.indices.contains(queueIndex) {
            suspendedQueueTrackID = queue[queueIndex].id
        }

        play(track: track)
        savePlaybackState(force: true)
    }

    private func resumeQueueAfterStandalonePlay(direction: Int) -> Bool {
        guard let savedID = suspendedQueueTrackID else {
            return false
        }

        suspendedQueueTrackID = nil

        guard let savedIndex = queue.firstIndex(where: { $0.id == savedID }) else {
            // The queue may have been deliberately changed while the
            // standalone track was playing. In that case, normal navigation
            // should apply to the current queue.
            return false
        }

        let targetIndex = savedIndex + direction

        if queue.indices.contains(targetIndex) {
            queueIndex = targetIndex
            play(track: queue[targetIndex])
        } else if repeatMode == .all && !queue.isEmpty {
            queueIndex = direction > 0 ? 0 : queue.count - 1
            play(track: queue[queueIndex])
        } else {
            // No queue item in that direction: return to the saved queue
            // track rather than mutating the queue.
            queueIndex = savedIndex
            play(track: queue[savedIndex])
        }

        savePlaybackState(force: true)
        return true
    }

    func startQueue(
        tracks: [LocalTrack],
        startIndex: Int
    ) {
        ToyakoPlaybackDiagnostics.shared.log("QUEUE_START requestedCount=\(tracks.count) startIndex=\(startIndex) shuffle=\(isShuffle) repeat=\(repeatMode.rawValue)")

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
        let diagnostics = ToyakoPlaybackDiagnostics.shared
        let queueDescription = queue.map { "\($0.id.uuidString.prefix(8)):\($0.title)" }.joined(separator: " | ")
        let standardizedURL = track.url.standardizedFileURL
        let fileManager = FileManager.default
        let exists = fileManager.fileExists(atPath: standardizedURL.path)
        let resourceValues = try? standardizedURL.resourceValues(forKeys: [
            .fileSizeKey,
            .isReadableKey,
            .isRegularFileKey
        ])

        diagnostics.log("PLAY_BEGIN title=\(track.title) id=\(track.id) url=\(standardizedURL.path) urlAbsolute=\(standardizedURL.absoluteString) queueIndex=\(queueIndex) queueCount=\(queue.count) current=\(currentTrack?.title ?? "nil")")
        diagnostics.log("PLAY_TARGET_FILE exists=\(exists) readable=\(resourceValues?.isReadable ?? false) regular=\(resourceValues?.isRegularFile ?? false) size=\(resourceValues?.fileSize.map(String.init) ?? "nil") pathExtension=\(standardizedURL.pathExtension)")
        diagnostics.log("PLAY_TARGET_METADATA title=\(track.title) artist=\(track.artist) album=\(track.album) duration=\(track.duration) id=\(track.id) url=\(standardizedURL.path)")
        diagnostics.log("PLAY_STATE_BEFORE isPlaying=\(isPlaying) playerRate=\(player.rate) playerItem=\(player.currentItem.map { String(describing: $0) } ?? "nil") playerItemsCount=\(player.items().count) volume=\(volume)")
        diagnostics.log("PLAY_QUEUE queueIndex=\(queueIndex) queueCount=\(queue.count) queue=[\(queueDescription)]")

        guard exists else {
            diagnostics.log("PLAY_ABORT target file does not exist")
            return
        }

        // Keep the .playback session active when playback is started from a
        // queue, remote command, or after returning from the background.
        diagnostics.log("PLAY_STEP 01 BEFORE activateAudioSessionForPlayback")
        guard activateAudioSessionForPlayback() else {
            diagnostics.log("PLAY_ABORT step=01 audio session activation failed title=\(track.title)")
            return
        }
        diagnostics.log("PLAY_STEP 01 AFTER activateAudioSessionForPlayback")

        diagnostics.log("PLAY_STEP 02 BEFORE currentTrack assignment")
        currentTrack = track
        diagnostics.log("PLAY_STEP 02 AFTER currentTrack assignment current=\(currentTrack?.title ?? "nil")")

        diagnostics.log("PLAY_STEP 03 BEFORE recordRecentlyPlayed")
        recordRecentlyPlayed(track)
        diagnostics.log("PLAY_STEP 03 AFTER recordRecentlyPlayed recentlyPlayedCount=\(recentlyPlayed.count)")

        diagnostics.log("PLAY_STEP 04 BEFORE reset pending seek state")
        pendingSeekTarget = nil
        pendingSeekTrackID = nil
        diagnostics.log("PLAY_STEP 04 AFTER reset pending seek state")

        diagnostics.log("PLAY_STEP 05 BEFORE reset currentTime")
        currentTime = 0
        diagnostics.log("PLAY_STEP 05 AFTER reset currentTime currentTime=\(currentTime)")

        diagnostics.log("PLAY_STEP 06 BEFORE reset playbackProgress")
        playbackProgress = 0
        diagnostics.log("PLAY_STEP 06 AFTER reset playbackProgress playbackProgress=\(playbackProgress)")

        diagnostics.log("PLAY_STEP 07 BEFORE loadLyrics url=\(standardizedURL.path)")
        loadLyrics(for: track)
        diagnostics.log("PLAY_STEP 07 AFTER loadLyrics sources=\(lyricsSources.count) selected=\(selectedLyricsSourceID ?? "nil") lines=\(currentLyrics.count)")

        diagnostics.log("PLAY_STEP 08 BEFORE detachTimeObserver")
        detachTimeObserver()
        diagnostics.log("PLAY_STEP 08 AFTER detachTimeObserver")

        diagnostics.log("PLAY_STEP 09 BEFORE detachEndObserver")
        detachEndObserver()
        diagnostics.log("PLAY_STEP 09 AFTER detachEndObserver")

        diagnostics.log("PLAY_STEP 10 BEFORE makePlayerItem")
        let playerItem = makePlayerItem(url: standardizedURL)
        diagnostics.log("PLAY_STEP 10 AFTER makePlayerItem itemStatus=\(playerItem.status.rawValue) itemError=\(playerItem.error?.localizedDescription ?? "nil") asset=\(String(describing: playerItem.asset))")

        diagnostics.log("PLAY_STEP 11 BEFORE player.volume old=\(player.volume) new=\(volume)")
        player.volume = volume
        diagnostics.log("PLAY_STEP 11 AFTER player.volume actual=\(player.volume)")

        diagnostics.log("PLAY_STEP 12 BEFORE player.removeAllItems count=\(player.items().count)")
        player.removeAllItems()
        diagnostics.log("PLAY_STEP 12 AFTER player.removeAllItems count=\(player.items().count)")

        diagnostics.log("PLAY_STEP 13 BEFORE player.replaceCurrentItem itemStatus=\(playerItem.status.rawValue)")
        player.replaceCurrentItem(with: playerItem)
        diagnostics.log("PLAY_STEP 13 AFTER player.replaceCurrentItem currentItemMatches=\(player.currentItem === playerItem) currentItem=\(player.currentItem.map { String(describing: $0) } ?? "nil") count=\(player.items().count)")

        diagnostics.log("PLAY_STEP 14 BEFORE player.play")
        player.play()
        diagnostics.log("PLAY_STEP 14 AFTER player.play rate=\(player.rate) timeControlStatus=\(player.timeControlStatus.rawValue) reason=\(String(describing: player.reasonForWaitingToPlay))")

        diagnostics.log("PLAY_STEP 15 BEFORE finalizePlay")
        finalizePlay(track: track, playerItem: playerItem)
        diagnostics.log("PLAY_STEP 15 AFTER finalizePlay isPlaying=\(isPlaying) current=\(currentTrack?.title ?? "nil") playerRate=\(player.rate)")
        diagnostics.log("PLAY_COMPLETE title=\(track.title) id=\(track.id)")
    }


    // MARK: - Finalize Playback

    private func finalizePlay(
        track:
            LocalTrack,

        playerItem:
            AVPlayerItem
    ) {
        ToyakoPlaybackDiagnostics.shared.log("PLAY_COMMIT title=\(track.title) id=\(track.id) itemStatus=\(playerItem.status.rawValue) playerItems=\(player.items().count) queueIndex=\(queueIndex) queueCount=\(queue.count)")

        itemStatusObservation?.invalidate()
        itemStatusObservation = playerItem.observe(\AVPlayerItem.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self else { return }
            let status = item.status
            if status == .failed {
                ToyakoPlaybackDiagnostics.shared.log("ITEM_FAILED title=\(track.title) id=\(track.id) error=\(item.error?.localizedDescription ?? "unknown")")
            } else {
                ToyakoPlaybackDiagnostics.shared.log("ITEM_STATUS title=\(track.title) status=\(status.rawValue)")
            }
        }

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
                ToyakoPlaybackDiagnostics.shared.log("END_NOTIFICATION item=\(playerItem) current=\(self?.currentTrack?.title ?? "nil") index=\(self?.queueIndex ?? -1)")
                self?.handleTrackEnded()
            }
    }


    // MARK: - Track Ended

    private func handleTrackEnded() {
        ToyakoPlaybackDiagnostics.shared.log("TRACK_ENDED title=\(currentTrack?.title ?? "nil") index=\(queueIndex) count=\(queue.count) repeat=\(repeatMode.rawValue)")

        switch repeatMode {
        case .one:
            guard let track = queue.indices.contains(queueIndex)
                    ? queue[queueIndex]
                    : currentTrack ?? queue.first else {
                ToyakoPlaybackDiagnostics.shared.log("TRACK_ENDED_REPEAT_ONE_ABORT empty queue")
                return
            }
            play(track: track)

        case .all:
            forward()

        case .off:
            if queueIndex + 1 < queue.count {
                forward()
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
        // Manual Play at the end of a completed queue restarts from
        // the first queue item. This is intentionally manual; the queue never
        // auto-restarts when the final track finishes.
        if !isPlaying && !queue.isEmpty && queueIndex >= queue.count - 1 {
            queueIndex = 0
            play(track: queue[queueIndex])
            savePlaybackState(force: true)
            return
        }


        guard currentTrack != nil else {
            return
        }

        if isPlaying {

            player.pause()

            isPlaying =
                false

        } else {

            // A Smart Folio can cause the system to deactivate the audio
            // session while the iPad is covered. Re-activate it immediately
            // before accepting a remote play/toggle command so a Bluetooth
            // headset can wake playback without opening the cover.
            guard activateAudioSessionForPlayback() else {
                return
            }

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
        let beforeIndex = queueIndex
        let beforeTrack = currentTrack?.title ?? "nil"
        let queueCount = queue.count
        ToyakoPlaybackDiagnostics.shared.log("NEXT_BEGIN beforeIndex=\(beforeIndex) count=\(queueCount) current=\(beforeTrack) repeat=\(repeatMode.rawValue) shuffle=\(isShuffle) suspended=\(suspendedQueueTrackID?.uuidString ?? "nil")")

        if resumeQueueAfterStandalonePlay(direction: 1) {
            ToyakoPlaybackDiagnostics.shared.log("NEXT_STANDALONE_RESUME handled=true newIndex=\(queueIndex) current=\(currentTrack?.title ?? "nil")")
            return
        }

        let targetIndex: Int
        if queueIndex + 1 < queue.count {
            targetIndex = queueIndex + 1
        } else if repeatMode == .all && !queue.isEmpty {
            targetIndex = 0
        } else {
            ToyakoPlaybackDiagnostics.shared.log("NEXT_NO_TARGET index=\(queueIndex) count=\(queue.count)")
            return
        }

        guard queue.indices.contains(targetIndex) else {
            ToyakoPlaybackDiagnostics.shared.log("NEXT_INVALID_TARGET targetIndex=\(targetIndex) indexRange=\(queue.indices)")
            return
        }

        queueIndex = targetIndex
        let target = queue[targetIndex]
        ToyakoPlaybackDiagnostics.shared.log("NEXT_TARGET targetIndex=\(targetIndex) title=\(target.title) id=\(target.id) url=\(target.url.path)")
        play(track: target)
        ToyakoPlaybackDiagnostics.shared.log("NEXT_END index=\(queueIndex) current=\(currentTrack?.title ?? "nil")")
    }


    // MARK: - Previous

    func backward() {

        if currentTime > 3.0 {

            seek(
                to:
                    0.0
            )

        } else if resumeQueueAfterStandalonePlay(direction: -1) {
            return

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

        itemStatusObservation?.invalidate()
        itemStatusObservation = nil

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
            guard self.activateAudioSessionForPlayback() else { return .commandFailed }
            self.player.play()
            self.isPlaying = true
            self.updatePlaybackState()
            self.savePlaybackState(force: true)
            return .success
        }
        remoteCommandTargets.append((commandCenter.playCommand, playTarget))
        commandCenter.playCommand.isEnabled = true

        let pauseTarget = commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.isPlaying else { return .commandFailed }
            self.player.pause()
            self.isPlaying = false
            self.updatePlaybackState()
            self.savePlaybackState(force: true)
            return .success
        }
        remoteCommandTargets.append((commandCenter.pauseCommand, pauseTarget))
        commandCenter.pauseCommand.isEnabled = true

        // Many Bluetooth headsets send the single toggle command rather than
        // separate play/pause commands. Register it explicitly; otherwise the
        // headset button can appear to stop working while the iPad is covered
        // or locked.
        let toggleTarget = commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            guard self.currentTrack != nil else { return .commandFailed }
            self.togglePlayPause()
            return .success
        }
        remoteCommandTargets.append((commandCenter.togglePlayPauseCommand, toggleTarget))
        commandCenter.togglePlayPauseCommand.isEnabled = true

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


            guard let self else { return }

            let reasonValue =
                info[AVAudioSessionInterruptionReasonKey] as? UInt
            let reason = reasonValue.flatMap {
                AVAudioSession.InterruptionReason(rawValue: $0)
            }

            ToyakoPlaybackDiagnostics.shared.log("INTERRUPTION type=\(typeValue) reason=\(reason.map { String(describing: $0) } ?? "nil") playing=\(self.isPlaying) current=\(self.currentTrack?.title ?? "nil")")

            if type == .began {

                // iPadOS can report an interruption while the app is being
                // suspended by the cover/lock transition. Treat that as a
                // lifecycle event, not as an audio takeover: otherwise the
                // later Bluetooth Play command can be stranded until the
                // cover is opened again.
                if reason == .appWasSuspended {
                    _ = self.activateAudioSessionForPlayback()
                    self.updatePlaybackState()
                    return
                }

                self.wasPlayingBeforeInterruption = self.isPlaying
                self.player.pause()
                self.isPlaying = false
                self.updatePlaybackState()
                self.savePlaybackState(force: true)

            } else {

                guard self.activateAudioSessionForPlayback() else { return }

                if self.wasPlayingBeforeInterruption {
                    self.player.play()
                    self.isPlaying = true
                }

                self.wasPlayingBeforeInterruption = false
                self.updatePlaybackState()
                self.savePlaybackState(force: true)
            }
        }
    }


    // MARK: - Application Lifecycle

    private func setupApplicationLifecycleHandling() {
        let center = NotificationCenter.default

        // Keep Now Playing/remote-control state coherent as a covered or
        // locked iPad moves the app out of the foreground.
        appBackgroundObserverToken = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.currentTrack != nil else {
                ToyakoPlaybackDiagnostics.shared.log("APP_BACKGROUND noCurrentTrack")
                return
            }
            ToyakoPlaybackDiagnostics.shared.log("APP_BACKGROUND playing=\(self.isPlaying) current=\(self.currentTrack?.title ?? "nil") index=\(self.queueIndex)")
            self.updatePlaybackState()
        }

        appForegroundObserverToken = center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.currentTrack != nil else {
                ToyakoPlaybackDiagnostics.shared.log("APP_FOREGROUND noCurrentTrack")
                return
            }
            ToyakoPlaybackDiagnostics.shared.log("APP_FOREGROUND playing=\(self.isPlaying) current=\(self.currentTrack?.title ?? "nil") index=\(self.queueIndex)")
            // Restore the session, but never implicitly resume a user-paused track.
            _ = self.activateAudioSessionForPlayback()
            self.updatePlaybackState()
        }
    }

    // MARK: - Audio Session

    @discardableResult
    private func activateAudioSessionForPlayback() -> Bool {
        let session = AVAudioSession.sharedInstance()

        do {
            // Keep the session configured for media playback. Re-setting the
            // category is intentional: after a Smart Folio interruption or
            // suspension the system can leave the session inactive.
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            return true
        } catch {
            ToyakoPlaybackDiagnostics.shared.log("AUDIO_SESSION_ERROR \(error.localizedDescription)")
            return false
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


    // MARK: - Remote Playback Helpers

    func playFromRemote() {
        guard currentTrack != nil, !isPlaying else { return }
        guard activateAudioSessionForPlayback() else { return }
        player.play()
        isPlaying = true
        updatePlaybackState()
        savePlaybackState(force: true)
    }

    func pauseFromRemote() {
        guard isPlaying else { return }
        player.pause()
        isPlaying = false
        updatePlaybackState()
        savePlaybackState(force: true)
    }

    func cycleRepeatMode(to mode: RepeatMode) {
        repeatMode = mode
        savePlaybackState(force: true)
    }

    // MARK: - Deinitialization

    deinit {

        savePlaybackState(
            force:
                true
        )

        detachTimeObserver()
        detachEndObserver()

        if let interruptionObserverToken {
            NotificationCenter.default.removeObserver(interruptionObserverToken)
        }
        if let appBackgroundObserverToken {
            NotificationCenter.default.removeObserver(appBackgroundObserverToken)
        }
        if let appForegroundObserverToken {
            NotificationCenter.default.removeObserver(appForegroundObserverToken)
        }


        for target in remoteCommandTargets {
            target.command.removeTarget(target.token)
        }
        remoteCommandTargets.removeAll()
    }
}
