import SwiftUI
import UIKit
import AVFoundation
import MediaPlayer
import Translation

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
    @State private var artworkTint: Color = .black
    @State private var audioFormatInfo: AudioFormatInfo?
    @State private var systemVolume: Float = AVAudioSession.sharedInstance().outputVolume

    @AppStorage(ToyakoPreferences.showAudioInfoKey) private var showAudioInfo = true

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            // Treat portrait and narrow Stage Manager windows as the compact
            // Now Playing layout. In compact mode lyrics replace the artwork
            // instead of sharing the screen with it.
            let isCompact = !isLandscape || geometry.size.width < 760

            ZStack {
                Color.black.ignoresSafeArea()

                ColorfulArtworkBleedBackground(
                    artworkData: nowPlayingArtworkData,
                    accentColor: artworkTint
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
                artworkTint = .black
                audioFormatInfo = nil
                return
            }

            async let artwork = ArtworkStore.shared.data(for: url)
            async let format = AudioFormatInfo.load(url: url)

            let loadedArtwork = await artwork
            let loadedFormat = await format
            guard !Task.isCancelled else { return }

            if let loadedArtwork {
                async let palette = ArtworkPalette.averageColor(from: loadedArtwork)
                let tint = await palette

                guard !Task.isCancelled else { return }

                withAnimation(.easeOut(duration: 0.35)) {
                    nowPlayingArtworkData = loadedArtwork
                    audioFormatInfo = loadedFormat
                    if let tint {
                        artworkTint = Color(uiColor: tint)
                    }
                }
            } else {
                audioFormatInfo = loadedFormat
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

            if showAudioInfo, let audioFormatInfo {
                Text(audioFormatInfo.displayString)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
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
            // Give each track/lyric set its own SmoothLyricsView identity.
            // TranslationSession is stateful, so merely changing the lyrics
            // inside the existing view can leave the translation task attached
            // to the previous song. Recreating this view guarantees that the
            // translation configuration and task belong to the new lyrics.
            .id("smooth-lyrics-\(trackID?.uuidString ?? "none")-\(lyrics.count)-\(lyrics.first?.id.uuidString ?? "")-\(lyrics.last?.id.uuidString ?? "")")
        }
    }
}

private func activeLyricID(lyrics: [LyricLine], currentTime: TimeInterval) -> UUID? {
    guard !lyrics.isEmpty else { return nil }

    // Always derive the active line from the same playback clock used by
    // SmoothLyricsView. Using AudioEngineManager.currentTime here could be one
    // update behind when Now Playing is first presented, causing the current
    // lyric to be temporarily missing until the next line change.
    // Lyrics are time-sorted. Binary search avoids scanning the entire lyric
    // array four times per second while playback is running.
    var low = 0
    var high = lyrics.count
    while low < high {
        let mid = (low + high) >> 1
        if lyrics[mid].time <= currentTime {
            low = mid + 1
        } else {
            high = mid
        }
    }
    return low > 0 ? lyrics[low - 1].id : nil
}

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

    @AppStorage(ToyakoPreferences.showRomanizationKey) private var showRomanization = true
    @AppStorage(ToyakoPreferences.translationKey) private var showTranslation = false
    @State private var translations: [UUID: String] = [:]
    @State private var translationConfiguration: TranslationSession.Configuration?
    @AppStorage(ToyakoPreferences.lyricsFontScaleKey) private var lyricsFontScale = 1.0
    @AppStorage(ToyakoPreferences.lyricsLineSpacingKey) private var lyricsLineSpacing = 30.0
    @AppStorage(ToyakoPreferences.lyricsAnimationStyleKey) private var lyricsAnimationStyle = LyricsAnimationStyle.dynamic.rawValue

    private var animationStyle: LyricsAnimationStyle {
        LyricsAnimationStyle(rawValue: lyricsAnimationStyle) ?? .dynamic
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: CGFloat(lyricsLineSpacing)) {
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
            .id("\(trackID?.uuidString ?? "none")-\(lyrics.count)-\(lyrics.first?.id.uuidString ?? "")-\(lyrics.last?.id.uuidString ?? "")")
            .translationTask(translationConfiguration) { session in
                guard showTranslation else { return }

                let japaneseLines = lyrics.filter {
                    $0.containsJapanese && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }

                guard !japaneseLines.isEmpty else { return }

                let requests = japaneseLines.map {
                    TranslationSession.Request(sourceText: $0.text)
                }

                do {
                    let responses = try await session.translations(from: requests)
                    guard !Task.isCancelled else { return }

                    var result: [UUID: String] = [:]
                    for (line, response) in zip(japaneseLines, responses) {
                        result[line.id] = response.targetText
                    }

                    await MainActor.run {
                        translations = result
                    }
                } catch {
                    // Translation may be unavailable until Apple's Japanese and
                    // English language models are installed. Keep the lyrics visible.
                }
            }
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
                updateTranslationConfiguration()
            }
            // Lyrics are loaded asynchronously after NowPlayingView can already
            // be on screen. In that case the original onAppear fires too early,
            // before LazyVStack has the current lyric to scroll to. Re-anchor when
            // the lyric collection arrives.
            .onChange(of: lyrics.map(\.id)) { _, _ in
                translations.removeAll()
                restartTranslationSession()
                DispatchQueue.main.async {
                    scrollToCurrentLyric(proxy: proxy, animated: false)
                }
            }
            .onChange(of: trackID) { _, newTrackID in
                translations.removeAll()
                restartTranslationSession()
                guard newTrackID != nil else { return }
                // Give the new lyric collection one layout pass before scrolling.
                DispatchQueue.main.async {
                    scrollToCurrentLyric(proxy: proxy, animated: false)
                }
            }
            .onChange(of: showTranslation) { _, enabled in
                translations.removeAll()
                if enabled {
                    restartTranslationSession()
                } else {
                    translationConfiguration = nil
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

    private func updateTranslationConfiguration(invalidate: Bool = false) {
        guard showTranslation else {
            translationConfiguration = nil
            return
        }

        if invalidate || translationConfiguration == nil {
            translationConfiguration = TranslationSession.Configuration(
                source: Locale.Language(identifier: "ja"),
                target: Locale.Language(identifier: "en")
            )
        }
    }

    /// Force SwiftUI to tear down the previous TranslationSession before
    /// starting a session for the newly loaded track. Reusing an equivalent
    /// Configuration can otherwise leave the translation task attached to the
    /// previous song, so the new translation does not appear until the view is
    /// recreated.
    private func restartTranslationSession() {
        guard showTranslation else {
            translationConfiguration = nil
            return
        }

        translationConfiguration = nil

        DispatchQueue.main.async {
            guard showTranslation else { return }
            translationConfiguration = TranslationSession.Configuration(
                source: Locale.Language(identifier: "ja"),
                target: Locale.Language(identifier: "en")
            )
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
                    compact: compact,
                    translatedText: translations[line.id]
                )
            } else {
                Text(line.text)
                    .font(.system(size: (compact ? 42 : 50) * lyricsFontScale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .opacity(lineOpacity(state))
                    .blur(radius: lineBlur(state))
                    .scaleEffect(lineScale(state), anchor: .leading)
                    .offset(y: lineOffset(state))
                    .fixedSize(horizontal: false, vertical: true)

                if showRomanization,
                   lineContainsJapanese(line),
                   let romanized = line.romanized,
                   !romanized.isEmpty {
                    Text(romanized)
                        .font(.system(size: (compact ? 18 : 22) * lyricsFontScale, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .opacity(romanizedOpacity(state))
                        .blur(radius: lineBlur(state))
                        .offset(y: state == .past ? -7 : 0)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if showTranslation,
                   lineContainsJapanese(line),
                   let translated = translations[line.id],
                   !translated.isEmpty {
                    Text(translated)
                        .font(.system(size: (compact ? 15 : 18) * lyricsFontScale, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(state == .active ? 0.72 : 0.22))
                        // Translation follows the exact same blur curve as
                        // the Japanese lyric and romanization. This keeps the
                        // past/future layers visually consistent.
                        .blur(radius: lineBlur(state))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .animation(
            animationStyle == .minimal
                ? .easeInOut(duration: 0.22)
                : animationStyle == .smooth
                        ? .smooth(duration: 0.58)
                        : .timingCurve(0.22, 0.72, 0.25, 1.0, duration: 0.62),
            value: state
        )
    }

    private func lineContainsJapanese(_ line: LyricLine) -> Bool {
        containsJapaneseCharacters(line.text)
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
        // Keep the depth cue, but avoid large blur radii across many lyric
        // rows. SwiftUI blur is an offscreen rendering pass and gets expensive
        // when dozens of rows are visible.
        case .future: return 0.8
        case .past: return 1.8
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
    let compact: Bool
    let translatedText: String?

    @AppStorage(ToyakoPreferences.lyricsFontScaleKey) private var lyricsFontScale = 1.0

    @State private var anchorTime: TimeInterval = 0
    @State private var anchorDate = Date()

    private var japaneseFont: Font { Font.system(size: compact ? 42 : 50, weight: .bold, design: .rounded) }
    private var romanizedFont: Font { Font.system(size: compact ? 18 : 21, weight: .medium, design: .rounded) }

    var body: some View {
        Group {
            if state == .active && isPlaying {
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
        if line.containsJapanese {
            JapaneseTimedLine(
                line: line,
                state: state,
                currentTime: currentTime,
                japaneseFont: japaneseFont,
                romanizedFont: romanizedFont,
                translatedText: translatedText
            )
            .scaleEffect(lyricsFontScale * (compact ? 0.86 : 1.0), anchor: .leading)
        } else {
            WordFlow(
                words: line.words,
                currentTime: currentTime,
                font: japaneseFont,
                baseOpacity: state == .future ? 0.27 : (state == .past ? 0.12 : 1.0),
                riseAmplitude: 3.2
            )
            .scaleEffect(lyricsFontScale * (compact ? 0.86 : 1.0), anchor: .leading)
            .opacity(state == .active ? 1 : (state == .future ? 0.27 : 0.12))
            .blur(radius: state == .active ? 0 : (state == .future ? 0.8 : 1.8))
            .scaleEffect(state == .active ? 1 : (state == .future ? 0.985 : 0.972), anchor: .leading)
            .offset(y: state == .past ? -14 : (state == .future ? 3 : 0))
        }
    }

    private func interpolatedTime(at date: Date) -> TimeInterval {
        guard state == .active, isPlaying else { return currentTime }
        return anchorTime + max(0, date.timeIntervalSince(anchorDate))
    }
}

/// Japanese karaoke renderer. Each timed TTML word is split into Unicode-safe
/// Japanese units while Latin/digit sequences stay atomic. The same timing
/// interval drives both the Japanese glyph and its corresponding romaji.
private struct JapaneseTimedLine: View {
    let line: LyricLine
    let state: LyricLineState
    let currentTime: TimeInterval
    let japaneseFont: Font
    let romanizedFont: Font
    let translatedText: String?

    @AppStorage(ToyakoPreferences.translationKey) private var showTranslation = false

    private var allUnits: [LyricUnit] {
        line.words.flatMap(\.units)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(horizontalSpacing: 4, verticalSpacing: 8) {
                ForEach(allUnits) { unit in
                    JapaneseLyricUnitView(
                        unit: unit,
                        currentTime: currentTime,
                        state: state,
                        japaneseFont: japaneseFont,
                        romanizedFont: romanizedFont
                    )
                }
            }
            if showTranslation, let translatedText, !translatedText.isEmpty {
                Text(translatedText)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(state == .active ? 0.72 : 0.22))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(state == .active ? 1 : (state == .future ? 0.27 : 0.12))
        .blur(radius: state == .active ? 0 : (state == .future ? 1.6 : 3.8))
        .scaleEffect(state == .active ? 1 : (state == .future ? 0.985 : 0.972), anchor: .leading)
        .offset(y: state == .past ? -14 : (state == .future ? 3 : 0))
    }
}

private struct JapaneseLyricUnitView: View {
    let unit: LyricUnit
    let currentTime: TimeInterval
    let state: LyricLineState
    let japaneseFont: Font
    let romanizedFont: Font

    @AppStorage(ToyakoPreferences.showRomanizationKey) private var showRomanization = true
    @AppStorage(ToyakoPreferences.karaokeGlowKey) private var karaokeGlow = true
    @AppStorage(ToyakoPreferences.lyricsAnimationStyleKey) private var lyricsAnimationStyle = LyricsAnimationStyle.dynamic.rawValue

    private var animationStyle: LyricsAnimationStyle {
        LyricsAnimationStyle(rawValue: lyricsAnimationStyle) ?? .dynamic
    }

    private var isActive: Bool {
        state == .active && currentTime >= unit.startTime && currentTime < unit.endTime
    }

    private var progress: Double {
        guard isActive else { return 0 }
        return min(1, max(0, (currentTime - unit.startTime) / max(0.001, unit.endTime - unit.startTime)))
    }

    private var glyphOpacity: Double {
        if isActive { return 1 }
        if state == .past || currentTime >= unit.endTime { return 0.82 }
        return 0.30
    }

    private var romajiOpacity: Double {
        if isActive { return 0.78 }
        if state == .past || currentTime >= unit.endTime { return 0.42 }
        return 0.18
    }

    private var activeOffset: CGFloat {
        switch animationStyle {
        case .dynamic: return -4 * CGFloat(sin(.pi * progress))
        case .smooth: return -3 * CGFloat(sin(.pi * progress))
        case .minimal: return 0
        }
    }

    private var activeScale: CGFloat {
        switch animationStyle {
        case .dynamic: return CGFloat(progress) * 0.006
        case .smooth: return CGFloat(progress) * 0.0045
        case .minimal: return 0
        }
    }

    var body: some View {
        VStack(spacing: 1) {
            Text(unit.text)
                .font(japaneseFont)
                .foregroundStyle(.white.opacity(glyphOpacity))
                .offset(y: activeOffset)
                .scaleEffect(1 + activeScale)
                .shadow(
                    color: .white.opacity(karaokeGlow && progress > 0 ? 0.72 * progress : 0),
                    radius: karaokeGlow && progress > 0 ? (animationStyle == .dynamic ? 9.0 : (animationStyle == .smooth ? 7.0 : 5.0)) : 0
                )

            if showRomanization, let romanized = unit.romanized,
               !romanized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               containsJapaneseCharacters(unit.text) {
                Text(romanized)
                    .font(romanizedFont)
                    .foregroundStyle(.white.opacity(romajiOpacity))
                    .scaleEffect(1 + CGFloat(progress) * 0.004)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
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

private struct WordRiseReveal: View {
    let word: LyricWord
    let currentTime: TimeInterval
    let font: Font
    let baseOpacity: Double
    let riseAmplitude: CGFloat

    @AppStorage(ToyakoPreferences.karaokeGlowKey) private var karaokeGlow = true
    @AppStorage(ToyakoPreferences.lyricsAnimationStyleKey) private var lyricsAnimationStyle = LyricsAnimationStyle.dynamic.rawValue

    private var animationStyle: LyricsAnimationStyle {
        LyricsAnimationStyle(rawValue: lyricsAnimationStyle) ?? .dynamic
    }

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
            .offset(y: animationStyle == .dynamic || animationStyle == .smooth ? -riseAmplitude * CGFloat(activeProgress) : (0))
            .scaleEffect(animationStyle == .minimal ? 1 : 1 + CGFloat(activeProgress) * (animationStyle == .dynamic ? 0.006 : 0.004), anchor: .center)
            .shadow(
                color: .white.opacity(karaokeGlow && activeProgress > 0 ? 0.68 * activeProgress : 0),
                radius: karaokeGlow && activeProgress > 0 ? (animationStyle == .dynamic ? 8.0 : 6.0) : 0
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
