import SwiftUI
import UIKit
import AVFoundation
import MediaPlayer

struct NowPlayingView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var audioManager: AudioEngineManager
    @EnvironmentObject var clock: PlaybackClock

    @State private var dragOffset: CGFloat = 0
    @State private var playPausePressed = false
    @State private var previousPressed = false
    @State private var nextPressed = false
    @State private var showQueue = false
    @State private var showLyrics = false
    @State private var showLyricsSourcePicker = false

    // The panel itself slides up via ContentView's `.move(edge: .bottom)`
    // transition. That transition is driven by a parent `withAnimation`,
    // but LazyArtwork loads its image asynchronously via `.task`, so on
    // first appearance the artwork was popping straight into its final
    // spot the instant its data loaded — instead of traveling with the
    // rest of the sheet. Driving an explicit offset/opacity off this flag
    // (set true in .onAppear, below) makes the artwork visibly slide up
    // and fade in together with the panel every time it opens.
    @State private var artworkVisible = false
    @State private var nowPlayingArtworkData: Data?
    @State private var systemVolume: Float = AVAudioSession.sharedInstance().outputVolume

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            // Treat portrait and narrow Stage Manager windows as the compact
            // Now Playing layout. In compact mode lyrics replace the artwork
            // instead of sharing the screen with it.
            let isCompact = !isLandscape || geometry.size.width < 760

            ZStack {
                Color.black.ignoresSafeArea()

                AppleMusicMovingBleedBackground(
                    artworkData: nowPlayingArtworkData
                )
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .gesture(dismissGesture(height: geometry.size.height))

                if isCompact {
                    compactNowPlayingLayout(geometry: geometry)
                } else {
                    HStack(spacing: geometry.size.width * 0.035) {
                        artworkPane(maxHeight: geometry.size.height * 0.48)
                            .frame(width: geometry.size.width * 0.35)
                            .contentShape(Rectangle())
                            .gesture(dismissGesture(height: geometry.size.height))

                        lyricsPane(compact: false)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.horizontal, 48)
                    .padding(.vertical, 24)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .animation(.smooth(duration: 0.38), value: audioManager.currentTrack?.id)
            .overlay(alignment: .topLeading) {
                Button {
                    close(height: geometry.size.height)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 52, height: 52)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 10)
                .padding(.top, 8)
            }
            .overlay(alignment: .topTrailing) {
                if !isCompact {
                    HStack(spacing: 2) {
                        if audioManager.lyricsSources.count > 1 {
                            lyricsSourceButton(size: 52, opensAbove: false)
                        }

                        Button {
                            showQueue = true
                        } label: {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .frame(width: 52, height: 52)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Queue")
                    }
                    .padding(.trailing, 10)
                    .padding(.top, 8)
                }
            }
            .sheet(isPresented: $showQueue) {
                QueueView()
                    .environmentObject(audioManager)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.clear)
                    .presentationCornerRadius(30)
            }
            .offset(y: dragOffset)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.88).delay(0.04)) {
                artworkVisible = true
            }
        }
        .task(id: audioManager.currentTrack?.id) {
            guard let url = audioManager.currentTrack?.url else {
                nowPlayingArtworkData = nil
                return
            }

            let loaded = await ArtworkStore.shared.data(for: url)
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: 0.35)) {
                nowPlayingArtworkData = loaded
            }
        }
        .onChange(of: isPresented) { _, presented in
            if presented {
                dragOffset = 0
            }
        }
    }

    // MARK: - Compact Now Playing

    private func compactNowPlayingLayout(geometry: GeometryProxy) -> some View {
        let horizontalInset: CGFloat = 32
        let availableWidth = max(0, geometry.size.width - horizontalInset * 2)

        // Keep the lower control area anchored to the bottom. The artwork gets
        // all remaining vertical space instead of being capped at 360pt.
        let fixedBottomArea: CGFloat = 285
        let topInset: CGFloat = 72
        let artworkSize = min(
            availableWidth,
            max(220, geometry.size.height - topInset - fixedBottomArea)
        )

        return VStack(spacing: 0) {
            ZStack {
                artwork(maxHeight: artworkSize)
                    .frame(width: artworkSize, height: artworkSize)
                    .opacity(showLyrics ? 0 : 1)
                    .allowsHitTesting(!showLyrics)

                lyricsPane(compact: true)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: artworkSize,
                        maxHeight: artworkSize
                    )
                    .opacity(showLyrics ? 1 : 0)
                    .allowsHitTesting(showLyrics)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: artworkSize,
                maxHeight: artworkSize
            )
            .contentShape(Rectangle())
            .gesture(dismissGesture(height: geometry.size.height))

            trackInformation
                .padding(.top, 20)

            AppleMusicScrubberBar(
                progress: clock.playbackProgress,
                duration: audioManager.currentTrack?.duration ?? 0,
                currentTime: clock.currentTime
            ) { progress in
                guard let duration = audioManager.currentTrack?.duration,
                      duration > 0 else { return }

                audioManager.seek(to: progress * duration)
            }
            .padding(.top, 8)

            // Push the entire control group to the bottom. This is the key
            // change: no large empty region remains between volume and actions,
            // while the artwork expands into the space above it.
            Spacer(minLength: 12)

            playbackControls(compact: true)
                .frame(maxWidth: .infinity)

            systemVolumeSlider
                .padding(.top, 14)

            compactBottomActions
                .padding(.top, 10)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, horizontalInset)
        .padding(.top, topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.28), value: showLyrics)
    }

    private var compactBottomActions: some View {
        HStack(spacing: 20) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    showLyrics.toggle()
                }
            } label: {
                Image(systemName: showLyrics ? "photo" : "quote.bubble")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .frame(width: 48, height: 48)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showLyrics ? "Show artwork" : "Show lyrics")

            if audioManager.lyricsSources.count > 1 {
                lyricsSourceButton(size: 48, opensAbove: true)
            }

            Button {
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .frame(width: 48, height: 48)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Queue")
        }
    }

    private func lyricsSourceButton(size: CGFloat, opensAbove: Bool = false) -> some View {
        Button {
            showLyricsSourcePicker = true
        } label: {
            Image(systemName: "text.badge.plus")
                .font(.system(size: size >= 52 ? 18 : 21, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select lyrics")
        .popover(
            isPresented: $showLyricsSourcePicker,
            attachmentAnchor: .point(opensAbove ? .top : .bottom),
            arrowEdge: opensAbove ? .bottom : .top
        ) {
            LyricsSourcePickerView()
                .environmentObject(audioManager)
                .frame(minWidth: 230, maxWidth: 300)
                .presentationCompactAdaptation(.popover)
        }
    }

    // MARK: - Lyrics Source Picker

    private struct LyricsSourcePickerView: View {
        @EnvironmentObject private var audioManager: AudioEngineManager
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text("Lyrics")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 4)

                ForEach(audioManager.lyricsSources) { source in
                    Button {
                        audioManager.selectLyricsSource(source.id)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: source.id == audioManager.selectedLyricsSourceID ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18, weight: .semibold))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.displayName)
                                    .font(.body.weight(.medium))
                                Text(source.format.uppercased())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 8)
                        }
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - Presentation

    private func close(height: CGFloat) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            dragOffset = height
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            isPresented = false
        }
    }

    private func dismissGesture(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                guard value.translation.height > 0,
                      abs(value.translation.height) > abs(value.translation.width)
                else { return }

                dragOffset = value.translation.height
            }
            .onEnded { value in
                let translation = value.translation.height
                let predicted = value.predictedEndTranslation.height

                if translation > 110 || predicted > 280 {
                    close(height: height)
                } else {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                        dragOffset = 0
                    }
                }
            }
    }

    // MARK: - Artwork Pane

    private func artworkPane(maxHeight: CGFloat) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 4)

            artwork(maxHeight: maxHeight)
            trackInformation

            AppleMusicScrubberBar(
                progress: clock.playbackProgress,
                duration: audioManager.currentTrack?.duration ?? 0,
                currentTime: clock.currentTime
            ) { progress in
                guard let duration = audioManager.currentTrack?.duration,
                      duration > 0 else { return }

                audioManager.seek(to: progress * duration)
            }

            playbackControls()

            systemVolumeSlider
                .padding(.top, 2)

            Spacer(minLength: 4)
        }
    }

    // MARK: - Artwork

    @ViewBuilder
    private func artwork(maxHeight: CGFloat) -> some View {
        Group {
            if let track = audioManager.currentTrack {
                // Keep the artwork in the Now Playing hierarchy so it enters
                // together with the panel's bottom-to-top presentation. There is
                // deliberately no shared geometry/hero transition with the mini-player.
                LazyArtwork(url: track.url, size: min(maxHeight, 520), cornerRadius: 12)
                    .frame(maxHeight: maxHeight)
                    // Preserve the original Now Playing interaction: when
                    // playback is paused, the artwork visually contracts.
                    // This is intentionally a visual scale only so the rest
                    // of the layout does not jump when play/pause changes.
                    .scaleEffect(audioManager.isPlaying ? 1.0 : 0.70, anchor: .center)
                    .animation(
                        .spring(response: 0.48, dampingFraction: 0.82),
                        value: audioManager.isPlaying
                    )
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.secondary.opacity(0.12))
                    .frame(maxHeight: maxHeight)
            }
        }
        // See `artworkVisible` above: gives the artwork its own explicit
        // bottom-to-top travel + fade so it visibly moves with the panel
        // instead of appearing to sit fixed in place while everything
        // else slides past it.
        .offset(y: artworkVisible ? 0 : 60)
        .opacity(artworkVisible ? 1 : 0)
    }

    // MARK: - Track Information

    private var trackInformation: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(audioManager.currentTrack?.title ?? "Unknown Title")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(audioManager.currentTrack?.artist ?? "Unknown Artist")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.22), value: audioManager.currentTrack?.id)
    }

    // MARK: - Playback Controls

    @ViewBuilder
    private func playbackControls(compact: Bool = false) -> some View {
        HStack(spacing: 36) {
            if compact {
                repeatButton
            } else {
                shuffleButton
            }

            previousButton
            playPauseButton
            nextButton

            if compact {
                shuffleButton
            } else {
                repeatButton
            }
        }
    }

    private var shuffleButton: some View {
        Button {
            audioManager.toggleShuffle()
        } label: {
            Image(systemName: "shuffle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(
                    audioManager.isShuffle ? .white : .white.opacity(0.34)
                )
        }
        .buttonStyle(.plain)
    }

    private var repeatButton: some View {
        Button {
            audioManager.toggleRepeat()
        } label: {
            Image(systemName: repeatIcon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(
                    audioManager.repeatMode != .off
                        ? .white
                        : .white.opacity(0.34)
                )
        }
        .buttonStyle(.plain)
    }

    private var previousButton: some View {
        Button {
            previousPressed = true
            audioManager.backward()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                previousPressed = false
            }
        } label: {
            Image(systemName: "backward.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .scaleEffect(previousPressed ? 0.76 : 1)
                .offset(x: previousPressed ? -2 : 0)
                .animation(
                    .spring(response: 0.22, dampingFraction: 0.58),
                    value: previousPressed
                )
        }
        .buttonStyle(.plain)
    }

    private var playPauseButton: some View {
        Button {
            playPausePressed = true
            audioManager.togglePlayPause()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                playPausePressed = false
            }
        } label: {
            Image(
                systemName: audioManager.isPlaying ? "pause.fill" : "play.fill"
            )
            .font(.system(size: 38, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 50, height: 50)
            .contentTransition(.symbolEffect(.replace))
            .scaleEffect(playPausePressed ? 0.80 : 1.0)
            .animation(
                .spring(response: 0.24, dampingFraction: 0.64),
                value: playPausePressed
            )
        }
        .buttonStyle(.plain)
    }

    private var nextButton: some View {
        Button {
            nextPressed = true
            audioManager.forward()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                nextPressed = false
            }
        } label: {
            Image(systemName: "forward.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .scaleEffect(nextPressed ? 0.76 : 1)
                .offset(x: nextPressed ? 2 : 0)
                .animation(
                    .spring(response: 0.22, dampingFraction: 0.58),
                    value: nextPressed
                )
        }
        .buttonStyle(.plain)
    }

    private var repeatIcon: String {
        switch audioManager.repeatMode {
        case .off, .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    // MARK: - System Volume

    private var systemVolumeSlider: some View {
        SystemVolumeSlider(value: $systemVolume)
            .frame(height: 24)
    }

// MARK: - Lyrics

private func lyricsPane(compact: Bool = false) -> some View {
    let lyrics = audioManager.currentLyrics
    let activeID = activeLyricID(lyrics: lyrics, currentTime: clock.currentTime)
    let trackID = audioManager.currentTrack?.id

    return Group {
        if lyrics.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.18))

                Text("Lyrics Unavailable")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.42))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            SmoothLyricsView(
                lyrics: lyrics,
                activeID: activeID,
                trackID: trackID,
                currentTime: clock.currentTime,
                isPlaying: audioManager.isPlaying,
                compact: compact
            ) { time in
                audioManager.seek(to: time)
            }
        }
    }
}

private func activeLyricID(lyrics: [LyricLine], currentTime: TimeInterval) -> UUID? {
    guard !lyrics.isEmpty else { return nil }

    // Always derive the active line from the same playback clock used by
    // SmoothLyricsView. Using AudioEngineManager.currentTime here could be one
    // update behind when Now Playing is first presented, causing the current
    // lyric to be temporarily missing until the next line change.
    return lyrics.last { $0.time <= currentTime }?.id
}

// MARK: - Smooth Lyrics View

private enum LyricLineState: Equatable {
    case past
    case active
    case future
}

private struct SmoothLyricsView: View {
    let lyrics: [LyricLine]
    let activeID: UUID?
    let trackID: UUID?
    let currentTime: TimeInterval
    let isPlaying: Bool
    let compact: Bool
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 30) {
                    ForEach(lyrics) { line in
                        lyricLine(
                            line: line,
                            state: lineState(line),
                            currentTime: currentTime,
                            isPlaying: isPlaying
                        )
                        .id(line.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSeek(line.time)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, compact ? 140 : 220)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.12),
                        .init(color: .black, location: 0.88),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .onAppear {
                scrollToCurrentLyric(proxy: proxy, animated: false)
            }
            // Lyrics are loaded asynchronously after NowPlayingView can already
            // be on screen. In that case the original onAppear fires too early,
            // before LazyVStack has the current lyric to scroll to. Re-anchor when
            // the lyric collection arrives.
            .onChange(of: lyrics.map(\.id)) { _, _ in
                DispatchQueue.main.async {
                    scrollToCurrentLyric(proxy: proxy, animated: false)
                    DispatchQueue.main.async {
                        scrollToCurrentLyric(proxy: proxy, animated: false)
                    }
                }
            }
            .onChange(of: trackID) { _, newTrackID in
                guard newTrackID != nil else { return }
                // Give the new lyric collection one layout pass before scrolling.
                DispatchQueue.main.async {
                    scrollToCurrentLyric(proxy: proxy, animated: false)
                }
            }
            .onChange(of: activeID) { _, newID in
                guard let newID else { return }
                // A deliberately slower, non-bouncy movement keeps the lyric
                // surface calm. The line itself also fades/settles independently.
                withAnimation(.timingCurve(0.22, 0.72, 0.25, 1.0, duration: 0.62)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
    }

    private func scrollToCurrentLyric(
        proxy: ScrollViewProxy,
        animated: Bool
    ) {
        guard !lyrics.isEmpty else { return }

        // Prefer the actual active line. If playback is before the first timed
        // line, show the first line rather than leaving the lyric area empty.
        // This also makes the initial presentation deterministic.
        let targetID = activeID
            ?? lyrics.first(where: { $0.time > currentTime })?.id
            ?? lyrics.last?.id

        guard let targetID else { return }

        // LazyVStack sometimes needs one run-loop turn before its target exists.
        DispatchQueue.main.async {
            if animated {
                withAnimation(.timingCurve(0.22, 0.72, 0.25, 1.0, duration: 0.62)) {
                    proxy.scrollTo(targetID, anchor: .center)
                }
            } else {
                proxy.scrollTo(targetID, anchor: .center)
            }
        }
    }

    private func lineState(_ line: LyricLine) -> LyricLineState {
        if line.id == activeID { return .active }
        if line.time < currentTime { return .past }
        return .future
    }

    @ViewBuilder
    private func lyricLine(
        line: LyricLine,
        state: LyricLineState,
        currentTime: TimeInterval,
        isPlaying: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: line.hasWordTiming && lineContainsJapanese(line) ? 7 : 0) {
            if line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(spacing: 7) {
                    Circle().frame(width: 8, height: 8)
                    Circle().frame(width: 8, height: 8)
                    Circle().frame(width: 8, height: 8)
                }
                .foregroundStyle(.white)
                .opacity(state == .active ? 0.9 : 0.18)
                .padding(.vertical, 10)
            } else if line.hasWordTiming {
                TimedLyricPair(
                    line: line,
                    state: state,
                    currentTime: currentTime,
                    isPlaying: isPlaying,
                    showRomanized: lineContainsJapanese(line)
                )
            } else {
                Text(line.text)
                    .font(.system(size: 50, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .opacity(lineOpacity(state))
                    .blur(radius: lineBlur(state))
                    .scaleEffect(lineScale(state), anchor: .leading)
                    .offset(y: lineOffset(state))
                    .fixedSize(horizontal: false, vertical: true)

                if lineContainsJapanese(line),
                   let romanized = line.romanized,
                   !romanized.isEmpty {
                    Text(romanized)
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .opacity(romanizedOpacity(state))
                        .blur(radius: state == .active ? 0 : 1.4)
                        .offset(y: state == .past ? -7 : 0)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .animation(
            .timingCurve(0.22, 0.72, 0.25, 1.0, duration: 0.58),
            value: state
        )
    }

    private func lineContainsJapanese(_ line: LyricLine) -> Bool {
        containsJapaneseCharacters(line.text)
    }

    private func containsJapaneseCharacters(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x309F, // Hiragana
                 0x30A0...0x30FF, // Katakana
                 0x31F0...0x31FF, // Katakana extensions
                 0x3400...0x4DBF, // CJK extension A
                 0x4E00...0x9FFF, // CJK unified ideographs
                 0xF900...0xFAFF: // CJK compatibility ideographs
                return true
            default:
                return false
            }
        }
    }

    private func lineOpacity(_ state: LyricLineState) -> Double {
        switch state {
        case .active: return 1.0
        case .future: return 0.27
        case .past: return 0.12
        }
    }

    private func romanizedOpacity(_ state: LyricLineState) -> Double {
        switch state {
        case .active: return 0.72
        case .future: return 0.18
        case .past: return 0.08
        }
    }

    private func lineBlur(_ state: LyricLineState) -> CGFloat {
        switch state {
        case .active: return 0
        case .future: return 1.6
        case .past: return 3.8
        }
    }

    private func lineScale(_ state: LyricLineState) -> CGFloat {
        switch state {
        case .active: return 1.0
        case .future: return 0.985
        case .past: return 0.972
        }
    }

    private func lineOffset(_ state: LyricLineState) -> CGFloat {
        switch state {
        case .active: return 0
        case .future: return 3
        case .past: return -14
        }
    }
}

// MARK: - Word-Timed Lyrics

private struct TimedLyricPair: View {
    let line: LyricLine
    let state: LyricLineState
    let currentTime: TimeInterval
    let isPlaying: Bool
    let showRomanized: Bool

    @State private var anchorTime: TimeInterval = 0
    @State private var anchorDate = Date()

    private let japaneseFont = Font.system(size: 50, weight: .bold, design: .rounded)
    private let romanizedFont = Font.system(size: 22, weight: .medium, design: .rounded)

    private var romanizedWords: [LyricWord] {
        guard showRomanized else { return [] }
        return line.words.compactMap { word in
            let text = word.text.toJapaneseRomaji() ?? ""
            guard !text.isEmpty else { return nil }
            return LyricWord(text: text, startTime: word.startTime, endTime: word.endTime)
        }
    }

    var body: some View {
        Group {
            if state == .active && isPlaying {
                // One shared 30 Hz clock for the active lyric pair. The renderer
                // itself is deliberately animation-free: every frame is derived
                // directly from the audio clock, avoiding hundreds of SwiftUI
                // animations competing with playback.
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
                    timedContent(currentTime: interpolatedTime(at: timeline.date))
                }
            } else {
                timedContent(currentTime: currentTime)
            }
        }
        .onAppear {
            anchorTime = currentTime
            anchorDate = Date()
        }
        .onChange(of: currentTime) { _, newValue in
            anchorTime = newValue
            anchorDate = Date()
        }
        .onChange(of: isPlaying) { _, _ in
            anchorTime = currentTime
            anchorDate = Date()
        }
    }

    @ViewBuilder
    private func timedContent(currentTime: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: showRomanized ? 7 : 0) {
            if showRomanized && state == .active {
                // Japanese is the only language that gets character-level timing.
                JapaneseCharacterFlow(
                    words: line.words,
                    currentTime: currentTime,
                    font: japaneseFont
                )
            } else {
                // English/non-Japanese stays word-by-word. No character effects.
                WordFlow(
                    words: line.words,
                    currentTime: currentTime,
                    font: japaneseFont,
                    baseOpacity: state == .future ? 0.27 : (state == .past ? 0.12 : 1.0),
                    riseAmplitude: 3.2
                )
                .opacity(state == .active ? 1 : (state == .future ? 0.27 : 0.12))
                .blur(radius: state == .active ? 0 : (state == .future ? 1.6 : 3.8))
                .scaleEffect(state == .active ? 1 : (state == .future ? 0.985 : 0.972), anchor: .leading)
                .offset(y: state == .past ? -14 : (state == .future ? 3 : 0))
            }

            if showRomanized {
                // The romanized word rises on the EXACT same word interval as
                // its Japanese source word. It does not slide/reveal left-to-right.
                JapaneseKaraokeRomanizationFlow(
                    words: line.words,
                    currentTime: currentTime
                )
                .opacity(state == .active ? 1 : (state == .future ? 0.18 : 0.08))
                .blur(radius: state == .active ? 0 : 1.4)
                .offset(y: state == .past ? -7 : 0)
            }
        }
    }

    private func interpolatedTime(at date: Date) -> TimeInterval {
        guard state == .active, isPlaying else { return currentTime }
        return anchorTime + max(0, date.timeIntervalSince(anchorDate))
    }
}

private struct WordTimedLyricLine: View {
    let line: LyricLine
    let state: LyricLineState
    let currentTime: TimeInterval
    let isPlaying: Bool

    var body: some View {
        TimedLyricPair(
            line: line,
            state: state,
            currentTime: currentTime,
            isPlaying: isPlaying,
            showRomanized: containsJapaneseCharacters(line.text)
        )
    }

    private func containsJapaneseCharacters(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x309F, 0x30A0...0x30FF, 0x31F0...0x31FF,
                 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                return true
            default:
                return false
            }
        }
    }
}

// MARK: - Japanese character karaoke

// Japanese lyrics are rendered character-by-character. Each character receives
// an evenly distributed interval from the original TTML word/span timing.
// The Japanese character and its matching romanization use the exact same
// interval, so they highlight and rise together.
//
// English lyrics do not use any of this code. They continue to use WordFlow
// and WordRiseReveal below, preserving the existing English word-by-word design.

private struct TimedLyricToken: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let romanization: String
    let start: TimeInterval
    let end: TimeInterval

    func progress(at time: TimeInterval) -> Double {
        guard end > start else {
            return time >= start ? 1.0 : 0.0
        }

        return min(
            1.0,
            max(0.0, (time - start) / (end - start))
        )
    }

    func isActive(at time: TimeInterval) -> Bool {
        time >= start && time < end
    }
}

private struct JapaneseKaraokeLine: Identifiable, Hashable {
    let id = UUID()
    let tokens: [TimedLyricToken]

    var start: TimeInterval {
        tokens.first?.start ?? 0
    }

    var end: TimeInterval {
        tokens.last?.end ?? start
    }
}

private struct JapaneseCharacterFlow: View {
    let words: [LyricWord]
    let currentTime: TimeInterval
    let font: Font

    private var line: JapaneseKaraokeLine {
        var tokens: [TimedLyricToken] = []

        for word in words {
            let characters = Array(word.text).map(String.init)
            guard !characters.isEmpty else { continue }

            let duration = max(
                0.001,
                word.endTime - word.startTime
            )
            let characterDuration =
                duration / Double(characters.count)

            for (index, character) in characters.enumerated() {
                let start =
                    word.startTime +
                    characterDuration * Double(index)

                let end =
                    index == characters.count - 1
                    ? word.endTime
                    : start + characterDuration

                let romanization =
                    character.toJapaneseRomaji() ?? ""

                tokens.append(
                    TimedLyricToken(
                        text: character,
                        romanization: romanization,
                        start: start,
                        end: end
                    )
                )
            }
        }

        return JapaneseKaraokeLine(tokens: tokens)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            FlowLayout(
                horizontalSpacing: 0,
                verticalSpacing: 4
            ) {
                ForEach(line.tokens) { token in
                    JapaneseKaraokeTokenView(
                        token: token,
                        currentTime: currentTime,
                        font: font
                    )
                }
            }

            FlowLayout(
                horizontalSpacing: 0,
                verticalSpacing: 2
            ) {
                ForEach(line.tokens) { token in
                    JapaneseKaraokeRomanizationTokenView(
                        token: token,
                        currentTime: currentTime
                    )
                }
            }
        }
    }
}

private struct JapaneseKaraokeRomanizationFlow: View {
    let words: [LyricWord]
    let currentTime: TimeInterval

    var body: some View {
        FlowLayout(
            horizontalSpacing: 0,
            verticalSpacing: 2
        ) {
            ForEach(tokens) { token in
                JapaneseKaraokeRomanizationTokenView(
                    token: token,
                    currentTime: currentTime
                )
            }
        }
    }

    private var tokens: [TimedLyricToken] {
        var result: [TimedLyricToken] = []

        for word in words {
            let characters = Array(word.text).map(String.init)
            guard !characters.isEmpty else { continue }

            let duration = max(0.001, word.endTime - word.startTime)
            let characterDuration = duration / Double(characters.count)

            for (index, character) in characters.enumerated() {
                let start = word.startTime + characterDuration * Double(index)
                let end = index == characters.count - 1
                    ? word.endTime
                    : start + characterDuration

                result.append(
                    TimedLyricToken(
                        text: character,
                        romanization: character.toJapaneseRomaji() ?? "",
                        start: start,
                        end: end
                    )
                )
            }
        }

        return result
    }
}

private struct JapaneseKaraokeTokenView: View {
    let token: TimedLyricToken
    let currentTime: TimeInterval
    let font: Font

    private var progress: Double {
        token.progress(at: currentTime)
    }

    private var isActive: Bool {
        token.isActive(at: currentTime)
    }

    private var activeProgress: CGFloat {
        guard isActive else { return 0 }

        // Smooth rise/focus curve while the character is active.
        return CGFloat(
            sin(.pi * min(1.0, max(0.0, progress)))
        )
    }

    private var opacity: Double {
        if isActive { return 1.0 }
        if currentTime >= token.end { return 0.92 }
        return 0.30
    }

    var body: some View {
        Text(token.text)
            .font(font)
            .foregroundStyle(.white.opacity(opacity))
            .offset(y: -4.0 * activeProgress)
            .scaleEffect(
                1.0 + activeProgress * 0.012,
                anchor: .center
            )
            .shadow(
                color: .white.opacity(
                    activeProgress * 0.16
                ),
                radius: activeProgress > 0 ? 2.2 : 0
            )
            .fixedSize(
                horizontal: true,
                vertical: false
            )
            .transaction { transaction in
                // The audio clock supplies the motion directly. This avoids
                // hundreds of independent SwiftUI animations per lyric line.
                transaction.animation = nil
            }
    }
}

private struct JapaneseKaraokeRomanizationTokenView: View {
    let token: TimedLyricToken
    let currentTime: TimeInterval

    private var progress: Double {
        token.progress(at: currentTime)
    }

    private var isActive: Bool {
        token.isActive(at: currentTime)
    }

    private var activeProgress: CGFloat {
        guard isActive else { return 0 }

        return CGFloat(
            sin(.pi * min(1.0, max(0.0, progress)))
        )
    }

    private var opacity: Double {
        if isActive { return 1.0 }
        if currentTime >= token.end { return 0.72 }
        return 0.28
    }

    var body: some View {
        Text(token.romanization.isEmpty ? " " : token.romanization)
            .font(
                .system(
                    size: 13,
                    weight: .medium,
                    design: .rounded
                )
            )
            .foregroundStyle(.white.opacity(opacity))
            .offset(y: -2.7 * activeProgress)
            .scaleEffect(
                1.0 + activeProgress * 0.006,
                anchor: .center
            )
            .shadow(
                color: .white.opacity(
                    activeProgress * 0.12
                ),
                radius: activeProgress > 0 ? 2.0 : 0
            )
            .fixedSize(
                horizontal: true,
                vertical: false
            )
            .transaction { transaction in
                transaction.animation = nil
            }
    }
}

// MARK: - Lightweight word timing

private struct WordFlow: View {
    let words: [LyricWord]
    let currentTime: TimeInterval
    let font: Font
    let baseOpacity: Double
    let riseAmplitude: CGFloat

    var body: some View {
        FlowLayout(horizontalSpacing: 10, verticalSpacing: 4) {
            ForEach(words) { word in
                WordRiseReveal(
                    word: word,
                    currentTime: currentTime,
                    font: font,
                    baseOpacity: baseOpacity,
                    riseAmplitude: riseAmplitude
                )
            }
        }
    }
}

// No GeometryReader, masks, per-word blur layers, or implicit animations here.
// The word simply rises and settles according to the shared audio clock.
private struct WordRiseReveal: View {
    let word: LyricWord
    let currentTime: TimeInterval
    let font: Font
    let baseOpacity: Double
    let riseAmplitude: CGFloat

    private var activeProgress: Double {
        guard currentTime >= word.startTime && currentTime < word.endTime else { return 0 }
        let x = min(1, max(0, (currentTime - word.startTime) / max(0.001, word.endTime - word.startTime)))
        return sin(.pi * x)
    }

    private var isActive: Bool {
        currentTime >= word.startTime && currentTime < word.endTime
    }

    private var opacity: Double {
        if isActive { return 1.0 }
        if currentTime >= word.endTime { return 0.82 }
        return baseOpacity
    }

    var body: some View {
        Text(word.text)
            .font(font)
            .foregroundStyle(.white.opacity(opacity))
            .offset(y: -riseAmplitude * CGFloat(activeProgress))
            .scaleEffect(1 + CGFloat(activeProgress) * 0.006, anchor: .center)
            .shadow(
                color: .white.opacity(activeProgress * 0.13),
                radius: activeProgress > 0 ? 2.2 : 0
            )
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 6

    init(horizontalSpacing: CGFloat = 8, verticalSpacing: CGFloat = 6) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        arrange(maxWidth: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        let result = arrange(maxWidth: bounds.width, subviews: subviews)
        for item in result.items {
            subviews[item.index].place(
                at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + item.y),
                proposal: ProposedViewSize(width: item.width, height: item.height)
            )
        }
    }

    private func arrange(maxWidth: CGFloat, subviews: Subviews) -> LayoutResult {
        var items: [LayoutItem] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposedX = x == 0 ? 0 : x + horizontalSpacing

            if proposedX + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }

            let finalX = x == 0 ? 0 : x + horizontalSpacing
            items.append(LayoutItem(index: index, x: finalX, y: y, width: size.width, height: size.height))
            x = finalX + size.width
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, x)
        }

        return LayoutResult(
            size: CGSize(width: min(maxWidth, usedWidth), height: items.isEmpty ? 0 : y + rowHeight),
            items: items
        )
    }

    struct Cache {}

    func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    private struct LayoutItem {
        let index: Int
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
    }

    private struct LayoutResult {
        let size: CGSize
        let items: [LayoutItem]
    }
}

// MARK: - Apple Music Scrubber

struct SystemVolumeSlider: View {
    @Binding var value: Float

    @State private var isHolding = false
    @State private var dragStartVolume: Double = 0
    @State private var dragStartX: CGFloat = 0
    @State private var dragVolume: Double = 0

    private var safeVolume: Double {
        min(1, max(0, Double(value)))
    }

    private var shownVolume: Double {
        isHolding ? dragVolume : safeVolume
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: 24)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(isHolding ? 0.30 : 0.18))
                        .frame(height: isHolding ? 9 : 5)

                    Capsule()
                        .fill(.white.opacity(isHolding ? 1.0 : 0.88))
                        .frame(
                            width: geometry.size.width * CGFloat(shownVolume),
                            height: isHolding ? 9 : 5
                        )

                    Circle()
                        .fill(.white)
                        .frame(width: isHolding ? 20 : 16, height: isHolding ? 20 : 16)
                        .offset(
                            x: max(0, min(geometry.size.width - (isHolding ? 20 : 16),
                                         geometry.size.width * CGFloat(shownVolume) - (isHolding ? 10 : 8)))
                        )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            if !isHolding {
                                isHolding = true
                                dragStartVolume = safeVolume
                                dragVolume = safeVolume
                                dragStartX = gesture.startLocation.x
                            }

                            let deltaX = gesture.location.x - dragStartX
                            let delta = geometry.size.width > 0
                                ? Double(deltaX / geometry.size.width)
                                : 0

                            dragVolume = min(1, max(0, dragStartVolume + delta))
                            value = Float(dragVolume)
                        }
                        .onEnded { _ in
                            value = Float(min(1, max(0, dragVolume)))
                            withAnimation(.easeOut(duration: 0.16)) {
                                isHolding = false
                            }
                        }
                )
            }
            .frame(height: 20)

            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: 24)
        }
        .background(
            SystemVolumeBridge(value: $value)
                .frame(width: 1, height: 1)
                .opacity(0.01)
        )
        .onAppear {
            value = AVAudioSession.sharedInstance().outputVolume
        }
    }
}

private struct SystemVolumeBridge: UIViewRepresentable {
    @Binding var value: Float

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.showsRouteButton = false
        view.showsVolumeSlider = true

        if let slider = view.subviews.compactMap({ $0 as? UISlider }).first {
            context.coordinator.slider = slider
            slider.value = AVAudioSession.sharedInstance().outputVolume
        }

        context.coordinator.startObservingSystemVolume()
        return view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {
        context.coordinator.value = $value
        context.coordinator.setSystemVolume(value)
    }

    static func dismantleUIView(_ view: MPVolumeView, coordinator: Coordinator) {
        coordinator.stopObservingSystemVolume()
    }

    final class Coordinator: NSObject {
        var value: Binding<Float>
        weak var slider: UISlider?
        private var volumeObservation: NSKeyValueObservation?

        init(value: Binding<Float>) {
            self.value = value
        }

        func startObservingSystemVolume() {
            guard volumeObservation == nil else { return }

            let session = AVAudioSession.sharedInstance()
            try? session.setActive(true)

            volumeObservation = session.observe(
                \.outputVolume,
                options: [.initial, .new]
            ) { [weak self] _, change in
                guard let self, let newValue = change.newValue else { return }

                DispatchQueue.main.async {
                    self.value.wrappedValue = newValue
                }
            }
        }

        func setSystemVolume(_ volume: Float) {
            let clamped = min(1, max(0, volume))
            guard let slider, abs(slider.value - clamped) > 0.001 else { return }
            slider.setValue(clamped, animated: false)
        }

        func stopObservingSystemVolume() {
            volumeObservation?.invalidate()
            volumeObservation = nil
        }
    }
}

struct AppleMusicScrubberBar: View {
    let progress: Double
    let duration: TimeInterval
    let currentTime: TimeInterval
    let onSeek: (Double) -> Void

    @State private var isHolding = false
    @State private var dragStartProgress = 0.0
    @State private var dragStartX: CGFloat = 0
    @State private var dragProgress = 0.0

    private let dragThreshold: CGFloat = 8

    private var safeProgress: Double {
        min(
            1,
            max(0, progress)
        )
    }

    private var shownProgress: Double {
        isHolding
            ? dragProgress
            : safeProgress
    }

    private var displayedTime: TimeInterval {
        duration * shownProgress
    }

    var body: some View {
        VStack(spacing: 7) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(
                            .white.opacity(
                                isHolding ? 0.30 : 0.18
                            )
                        )
                        .frame(
                            height: isHolding ? 9 : 5
                        )

                    Capsule()
                        .fill(
                            .white.opacity(
                                isHolding ? 1.0 : 0.88
                            )
                        )
                        .frame(
                            width:
                                geometry.size.width
                                * CGFloat(shownProgress),
                            height: isHolding ? 9 : 5
                        )
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .center
                )
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(
                        minimumDistance: 0
                    )
                    .onChanged { value in
                        if !isHolding {
                            isHolding = true
                            dragStartProgress =
                                safeProgress
                            dragProgress =
                                safeProgress
                            dragStartX =
                                value.startLocation.x
                        }

                        // A tap/hold does not jump the slider.
                        // The drag is interpreted relative to
                        // the position where the finger first
                        // touched the control.
                        let deltaX =
                            value.location.x
                            - dragStartX

                        let delta =
                            geometry.size.width > 0
                                ? Double(
                                    deltaX
                                    / geometry.size.width
                                )
                                : 0

                        dragProgress = min(
                            1,
                            max(
                                0,
                                dragStartProgress + delta
                            )
                        )
                    }
                    .onEnded { _ in
                        let finalProgress = min(
                            1,
                            max(
                                0,
                                dragProgress
                            )
                        )

                        // A pure tap/hold produces no meaningful
                        // horizontal movement, so leave playback
                        // exactly where it was.
                        if abs(
                            dragProgress
                            - dragStartProgress
                        ) >= 0.002 {
                            onSeek(finalProgress)
                        }

                        withAnimation(
                            .easeOut(duration: 0.16)
                        ) {
                            isHolding = false
                        }
                    }
                )
            }
            .frame(height: 20)

            HStack {
                Text(
                    formatTime(displayedTime)
                )

                Spacer()

                Text(
                    "-"
                    + formatTime(
                        max(
                            0,
                            duration - displayedTime
                        )
                    )
                )
            }
            .font(
                .system(
                    size: 12,
                    weight: .medium,
                    design: .monospaced
                )
            )
            .foregroundStyle(
                .white.opacity(0.62)
            )
            .monospacedDigit()
        }
    }

    private func formatTime(
        _ time: TimeInterval
    ) -> String {
        guard time.isFinite else {
            return "0:00"
        }

        let seconds = max(
            0,
            Int(
                time.rounded(.down)
            )
        )

        return String(
            format: "%d:%02d",
            seconds / 60,
            seconds % 60
        )
    }
} 

// MARK: - Moving Artwork Background
// MARK: - Apple Music Style Artwork Bleed
//
// Replace the ENTIRE existing `AppleMusicMovingBleedBackground`
// with this implementation.
//
// It intentionally does NOT use random().
// Random values inside SwiftUI's body can cause visible jitter.
// Instead, several independent low-frequency curves create
// continuously changing, organic movement.

struct AppleMusicMovingBleedBackground: View {
    let artworkData: Data?

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in

                let time = timeline.date.timeIntervalSinceReferenceDate
                let width = geometry.size.width
                let height = geometry.size.height

                ZStack {
                    Color.black

                    if let artworkData,
                       let image = UIImage(data: artworkData) {

                        // -------------------------------------------------
                        // MAIN COLOR FIELD
                        // -------------------------------------------------

                        bleedLayer(
                            image: image,
                            time: time,
                            width: width,
                            height: height,
                            phase: 0.0,
                            speed: 0.075,
                            scale: 1.75,
                            blur: 105,
                            opacity: 0.72,
                            movement: 95,
                            rotation: 2.0
                        )

                        // -------------------------------------------------
                        // SECOND COLOR FIELD
                        // -------------------------------------------------

                        bleedLayer(
                            image: image,
                            time: time,
                            width: width,
                            height: height,
                            phase: 2.4,
                            speed: 0.052,
                            scale: 2.05,
                            blur: 125,
                            opacity: 0.48,
                            movement: 125,
                            rotation: -3.0
                        )

                        // -------------------------------------------------
                        // LARGE SOFT COLOR FIELD
                        // -------------------------------------------------

                        bleedLayer(
                            image: image,
                            time: time,
                            width: width,
                            height: height,
                            phase: 4.8,
                            speed: 0.037,
                            scale: 2.35,
                            blur: 150,
                            opacity: 0.34,
                            movement: 155,
                            rotation: 2.5
                        )

                        // -------------------------------------------------
                        // VERY SLOW AMBIENT COLOR
                        // -------------------------------------------------

                        ambientLayer(
                            image: image,
                            time: time,
                            width: width,
                            height: height,
                            phase: 1.2,
                            speed: 0.021,
                            scale: 2.70,
                            blur: 175,
                            opacity: 0.24,
                            movement: 190
                        )

                        // -------------------------------------------------
                        // SOFT COLOR POOL
                        // -------------------------------------------------

                        colorPool(
                            image: image,
                            time: time,
                            width: width,
                            height: height,
                            phase: 3.1,
                            speed: 0.028,
                            scale: 2.90,
                            blur: 190,
                            opacity: 0.20
                        )

                        // -------------------------------------------------
                        // CENTER DARKENING
                        //
                        // Keeps the lyrics and controls readable while
                        // allowing the artwork colors to remain visible.
                        // -------------------------------------------------

                        RadialGradient(
                            stops: [
                                .init(
                                    color: .black.opacity(0.03),
                                    location: 0.00
                                ),
                                .init(
                                    color: .black.opacity(0.08),
                                    location: 0.35
                                ),
                                .init(
                                    color: .black.opacity(0.22),
                                    location: 0.68
                                ),
                                .init(
                                    color: .black.opacity(0.52),
                                    location: 1.00
                                )
                            ],
                            center: .center,
                            startRadius: min(width, height) * 0.10,
                            endRadius: max(width, height) * 0.82
                        )

                        // -------------------------------------------------
                        // VERY SUBTLE OVERALL DARKENING
                        // -------------------------------------------------

                        Color.black.opacity(0.14)

                    } else {

                        // Fallback before artwork is loaded.
                        LinearGradient(
                            colors: [
                                .black,
                                Color(white: 0.055),
                                .black
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
                .frame(
                    width: width,
                    height: height
                )
                .clipped()
                .drawingGroup()
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(
            .easeInOut(duration: 0.8),
            value: artworkData?.hashValue
        )
    }

    // MARK: - Main Bleed Layer

    private func bleedLayer(
        image: UIImage,
        time: TimeInterval,
        width: CGFloat,
        height: CGFloat,
        phase: Double,
        speed: Double,
        scale: CGFloat,
        blur: CGFloat,
        opacity: Double,
        movement: CGFloat,
        rotation: Double
    ) -> some View {

        let t = time * speed + phase

        // Several unrelated waves are combined.
        // This produces fluid movement rather than a circular orbit.

        let x =
            sin(t * 0.71) * movement
            + cos(t * 0.43 + 1.7) * movement * 0.52
            + sin(t * 0.23 + 3.2) * movement * 0.30
            + cos(t * 0.11 + 5.0) * movement * 0.18

        let y =
            cos(t * 0.63 + 0.8) * movement * 0.78
            + sin(t * 0.39 + 2.1) * movement * 0.55
            + cos(t * 0.19 + 4.5) * movement * 0.32
            + sin(t * 0.09 + 1.2) * movement * 0.20

        // Slow breathing makes the colour field continuously expand
        // and contract instead of looking like a static blurred image.

        let breathing =
            sin(t * 0.27 + phase) * 0.055
            + cos(t * 0.17 + 1.8) * 0.035
            + sin(t * 0.08 + 4.2) * 0.022

        // Extremely subtle rotation.
        // The rotation is deliberately small so it doesn't look like
        // the whole album cover is spinning.

        let angle =
            sin(t * 0.21 + phase) * rotation
            + cos(t * 0.13 + 2.4) * rotation * 0.45

        let renderedArtwork = Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(
                width: width * 1.65,
                height: height * 1.65
            )
            .scaleEffect(
                scale + breathing,
                anchor: .center
            )
            .rotationEffect(.degrees(angle))
            .offset(
                x: CGFloat(x),
                y: CGFloat(y)
            )
            .blur(radius: blur, opaque: true)
            .saturation(1.12)
            .opacity(opacity)

        return AnyView(renderedArtwork)
    }

    // MARK: - Ambient Layer

    @ViewBuilder
    private func ambientLayer(
        image: UIImage,
        time: TimeInterval,
        width: CGFloat,
        height: CGFloat,
        phase: Double,
        speed: Double,
        scale: CGFloat,
        blur: CGFloat,
        opacity: Double,
        movement: CGFloat
    ) -> some View {

        let t = time * speed + phase

        let x =
            sin(t * 0.57 + 1.4) * movement
            + cos(t * 0.31 + 3.1) * movement * 0.55
            + sin(t * 0.13 + 4.8) * movement * 0.25

        let y =
            cos(t * 0.49 + 2.2) * movement * 0.72
            + sin(t * 0.27 + 0.7) * movement * 0.48
            + cos(t * 0.11 + 5.4) * movement * 0.25

        let breathing =
            1.0
            + sin(t * 0.19 + phase) * 0.07
            + cos(t * 0.11 + 2.0) * 0.035

        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(
                width: width * 1.8,
                height: height * 1.8
            )
            .scaleEffect(
                scale * breathing,
                anchor: .center
            )
            .offset(
                x: CGFloat(x),
                y: CGFloat(y)
            )
            .blur(
                radius: blur,
                opaque: true
            )
            .saturation(1.20)
            .brightness(-0.16)
            .opacity(opacity)
    }

    // MARK: - Large Color Pool

    @ViewBuilder
    private func colorPool(
        image: UIImage,
        time: TimeInterval,
        width: CGFloat,
        height: CGFloat,
        phase: Double,
        speed: Double,
        scale: CGFloat,
        blur: CGFloat,
        opacity: Double
    ) -> some View {

        let t = time * speed + phase

        let x =
            sin(t * 0.43) * 145
            + cos(t * 0.21 + 1.8) * 85
            + sin(t * 0.09 + 4.0) * 45

        let y =
            cos(t * 0.37 + 0.9) * 125
            + sin(t * 0.19 + 2.7) * 75
            + cos(t * 0.07 + 5.1) * 40

        let scaleChange =
            1.0
            + sin(t * 0.17) * 0.065
            + cos(t * 0.08 + 2.0) * 0.035

        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(
                width: width * 1.9,
                height: height * 1.9
            )
            .scaleEffect(
                scale * scaleChange,
                anchor: .center
            )
            .offset(
                x: CGFloat(x),
                y: CGFloat(y)
            )
            .blur(
                radius: blur,
                opaque: true
            )
            .saturation(1.25)
            .brightness(-0.18)
            .opacity(opacity)
    }
}
}
