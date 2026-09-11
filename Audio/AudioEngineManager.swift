import AVFoundation
import Accelerate
import MediaPlayer
import Combine
import AudioToolbox
import MediaToolbox

// MARK: - Audio-Reactive Mini Player Spectrum
// Extracts five frequency-band amplitudes from the actual PCM audio flowing
// through AVPlayer. The bands are intentionally broad and perceptual rather
// than a full spectrum: they drive the five mini-player waves independently.

private final class AudioLevelMeter: @unchecked Sendable {

    private static let fftSize = 512
    private static let log2FFTSize: vDSP_Length = 9

    // Approximate perceptual bands for the five visible waves.
    // [sub/bass, bass, low-mid, high-mid, treble]
    private static let bands: [(Float, Float)] = [
        (20, 120),
        (120, 350),
        (350, 1_500),
        (1_500, 5_000),
        (5_000, 16_000)
    ]

    private var tap: MTAudioProcessingTap?
    private var lastPublishTime: CFTimeInterval = 0
    private var generation: UInt = 0

    // Reusable DSP buffers. The tap callback runs on an audio-processing
    // thread, so these are allocated once instead of per callback.
    private let fftSetup = vDSP_create_fftsetup(
        log2FFTSize,
        FFTRadix(kFFTRadix2)
    )
    private var fftInput = [Float](repeating: 0, count: fftSize)
    private var window = [Float](repeating: 0, count: fftSize)
    private var splitReal = [Float](repeating: 0, count: fftSize / 2)
    private var splitImag = [Float](repeating: 0, count: fftSize / 2)
    private var magnitudes = [Float](repeating: 0, count: fftSize / 2)

    private var smoothedBands = [Float](repeating: 0, count: 5)
    private var sampleRate: Float = 44_100

    var onBands: (([Float]) -> Void)?

    init() {
        window = vDSP.window(
            ofType: Float.self,
            usingSequence: .hanningDenormalized,
            count: Self.fftSize,
            isHalfWindow: false
        )
    }

    deinit {
        if let fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
    }

    func attach(
        to item: AVPlayerItem,
        track: AVAssetTrack
    ) {
        generation &+= 1

        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passUnretained(self).toOpaque(),
            init: audioTapInit,
            finalize: audioTapFinalize,
            prepare: audioTapPrepare,
            unprepare: audioTapUnprepare,
            process: audioTapProcess
        )

        var tapOut: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &tapOut
        )

        guard status == noErr, let tap = tapOut else { return }

        self.tap = tap

        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = tap

        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        item.audioMix = mix
    }

    func prepare(format: UnsafePointer<AudioStreamBasicDescription>) {
        sampleRate = Float(format.pointee.mSampleRate)
    }

    func reset() {
        generation &+= 1
        lastPublishTime = 0
        smoothedBands = Array(repeating: 0, count: 5)
        onBands?([0, 0, 0, 0, 0])
        onBands = nil
        tap = nil
    }

    fileprivate func process(
        tap: MTAudioProcessingTap,
        numberFrames: CMItemCount,
        bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
        numberFramesOut: UnsafeMutablePointer<CMItemCount>,
        flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
    ) {
        let status = MTAudioProcessingTapGetSourceAudio(
            tap,
            numberFrames,
            bufferListInOut,
            flagsOut,
            nil,
            numberFramesOut
        )

        guard status == noErr, let fftSetup else { return }

        let buffers = UnsafeMutableAudioBufferListPointer(bufferListInOut)
        let frames = min(Int(numberFramesOut.pointee), Self.fftSize)
        guard frames > 0 else { return }

        fftInput.withUnsafeMutableBufferPointer { input in
            for i in 0..<Self.fftSize {
                input[i] = 0
            }

            var totalChannels = 0
            for buffer in buffers {
                totalChannels += max(Int(buffer.mNumberChannels), 1)
            }
            guard totalChannels > 0 else { return }

            for buffer in buffers {
                guard let data = buffer.mData else { continue }

                let channels = max(Int(buffer.mNumberChannels), 1)
                let floatCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                let availableFrames = min(frames, floatCount / channels)
                guard availableFrames > 0 else { continue }

                let samples = data.assumingMemoryBound(to: Float.self)
                for frame in 0..<availableFrames {
                    var sum: Float = 0
                    for channel in 0..<channels {
                        sum += samples[frame * channels + channel]
                    }
                    input[frame] += sum / Float(totalChannels)
                }
            }
        }

        // Window the time-domain samples before the FFT to reduce spectral leakage.
        vDSP.multiply(fftInput, window, result: &fftInput)

        splitReal.withUnsafeMutableBufferPointer { real in
            splitImag.withUnsafeMutableBufferPointer { imag in
                magnitudes.withUnsafeMutableBufferPointer { mags in
                    var split = DSPSplitComplex(
                        realp: real.baseAddress!,
                        imagp: imag.baseAddress!
                    )

                    fftInput.withUnsafeBufferPointer { input in
                        input.baseAddress!.withMemoryRebound(
                            to: DSPComplex.self,
                            capacity: Self.fftSize / 2
                        ) { complexInput in
                            vDSP_ctoz(
                                complexInput,
                                2,
                                &split,
                                1,
                                vDSP_Length(Self.fftSize / 2)
                            )
                        }
                    }

                    vDSP_fft_zrip(
                        fftSetup,
                        &split,
                        1,
                        Self.log2FFTSize,
                        FFTDirection(FFT_FORWARD)
                    )

                    vDSP_zvmags(
                        &split,
                        1,
                        mags.baseAddress!,
                        1,
                        vDSP_Length(Self.fftSize / 2)
                    )

                    let binWidth = sampleRate / Float(Self.fftSize)

                    var levels = [Float](repeating: 0, count: 5)
                    for bandIndex in 0..<Self.bands.count {
                        let (lowHz, highHz) = Self.bands[bandIndex]
                        let firstBin = max(1, Int(lowHz / binWidth))
                        let lastBin = min(
                            Self.fftSize / 2 - 1,
                            Int(highHz / binWidth)
                        )

                        guard lastBin >= firstBin else { continue }

                        var sum: Float = 0
                        var count = 0
                        for bin in firstBin...lastBin {
                            sum += mags[bin]
                            count += 1
                        }

                        let power = sum / Float(max(count, 1))
                        // sqrt(power) gives amplitude; the multiplier makes
                        // normal music occupy a useful visual range.
                        let amplitude = sqrt(max(power, 0)) * 8.0
                        levels[bandIndex] = min(max(amplitude, 0), 1)
                    }

                    for i in levels.indices {
                        // Fast attack / slower release, similar to Apple's
                        // compact music visualizer behavior.
                        let target = levels[i]
                        if target > smoothedBands[i] {
                            smoothedBands[i] += (target - smoothedBands[i]) * 0.58
                        } else {
                            smoothedBands[i] += (target - smoothedBands[i]) * 0.16
                        }
                        levels[i] = smoothedBands[i]
                    }

                    let now = CACurrentMediaTime()
                    guard now - lastPublishTime >= (1.0 / 30.0) else { return }
                    lastPublishTime = now

                    let published = levels
                    let generation = self.generation

                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.generation == generation else { return }
                        self.onBands?(published)
                    }
                }
            }
        }
    }
}

// MARK: - C-Compatible Audio Tap Callbacks

private func audioTapInit(
    _ tap: MTAudioProcessingTap,
    _ clientInfo: UnsafeMutableRawPointer?,
    _ tapStorageOut:
        UnsafeMutablePointer<UnsafeMutableRawPointer?>
) {

    tapStorageOut.pointee =
        clientInfo
}


private func audioTapFinalize(
    _ tap: MTAudioProcessingTap
) {
}


private func audioTapPrepare(
    _ tap: MTAudioProcessingTap,
    _ maxFrames: CMItemCount,
    _ processingFormat:
        UnsafePointer<AudioStreamBasicDescription>
) {
    let storage = MTAudioProcessingTapGetStorage(tap)
    let meter = Unmanaged<AudioLevelMeter>
        .fromOpaque(storage)
        .takeUnretainedValue()
    meter.prepare(format: processingFormat)
}


private func audioTapUnprepare(
    _ tap: MTAudioProcessingTap
) {
}


private func audioTapProcess(
    _ tap: MTAudioProcessingTap,
    _ numberFrames: CMItemCount,
    _ flags: MTAudioProcessingTapFlags,
    _ bufferListInOut:
        UnsafeMutablePointer<AudioBufferList>,
    _ numberFramesOut:
        UnsafeMutablePointer<CMItemCount>,
    _ flagsOut:
        UnsafeMutablePointer<MTAudioProcessingTapFlags>
) {

    let storage = MTAudioProcessingTapGetStorage(tap)

    let meter =
        Unmanaged<AudioLevelMeter>
            .fromOpaque(storage)
            .takeUnretainedValue()

    meter.process(
        tap:
            tap,

        numberFrames:
            numberFrames,

        bufferListInOut:
            bufferListInOut,

        numberFramesOut:
            numberFramesOut,

        flagsOut:
            flagsOut
    )
}


// MARK: - Playback Persistence

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


// MARK: - Audio Engine Manager

class AudioEngineManager: ObservableObject {

    private let player =
        AVPlayer()

    private var timeObserverToken:
        Any?

    private var endObserverToken:
        Any?

    private var lastPersistedTime:
        TimeInterval = -100

    private var didAttemptRestore =
        false

    private let audioLevelMeter =
        AudioLevelMeter()


    // MARK: Published State

    @Published var audioBands:
        [Float] = [0, 0, 0, 0, 0]

    @Published var currentTrack:
        LocalTrack?

    @Published var isPlaying:
        Bool = false

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


    // MARK: Initialization

    init() {

        audioLevelMeter.onBands = {
            [weak self] bands in

            self?.audioBands = bands
        }

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

        if let audioTrack =
            asset.tracks(
                withMediaType: .audio
            ).first {

            audioLevelMeter.attach(
                to:
                    item,

                track:
                    audioTrack
            )
        }

        return item
    }


    private func resetAudioMeter() {

        audioLevelMeter.reset()

        audioBands = [0, 0, 0, 0, 0]

        audioLevelMeter.onBands = {
            [weak self] bands in

            self?.audioBands = bands
        }
    }


    // MARK: - Persistent Playback / Resume

    private let persistenceKey =
        "Toyako.PlaybackState.v2"


    func savePlaybackState(
        force: Bool = false
    ) {

        guard currentTrack != nil else {
            return
        }

        if !force &&
            abs(
                currentTime -
                lastPersistedTime
            ) < 2.0 {

            return
        }

        lastPersistedTime =
            currentTime

        let state =
            PlaybackPersistenceState(
                queue:
                    queue,

                originalQueue:
                    originalQueue,

                queueIndex:
                    queueIndex,

                currentTrackID:
                    currentTrack?.id,

                position:
                    currentTime,

                isPlaying:
                    isPlaying,

                isShuffle:
                    isShuffle,

                repeatMode:
                    repeatMode
            )

        if let data =
            try? JSONEncoder()
                .encode(state) {

            UserDefaults.standard.set(
                data,
                forKey:
                    persistenceKey
            )
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

        didAttemptRestore =
            true

        guard
            let data =
                UserDefaults.standard.data(
                    forKey:
                        persistenceKey
                ),

            let state =
                try? JSONDecoder().decode(
                    PlaybackPersistenceState.self,
                    from:
                        data
                ),

            let savedCurrentID =
                state.currentTrackID
        else {
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

        loadLyrics(
            for:
                current
        )

        detachTimeObserver()
        detachEndObserver()

        resetAudioMeter()


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

        resetAudioMeter()


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
            duration > 0
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

                guard
                    let self
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
                            seconds /
                                duration,

                            1
                        )
                    )


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


        if let data =
            track.artworkData,

           let image =
            UIImage(
                data:
                    data
            ) {

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