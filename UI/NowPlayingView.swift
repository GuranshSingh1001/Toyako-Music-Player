import SwiftUI
import UIKit

struct NowPlayingView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var audioManager: AudioEngineManager
    @EnvironmentObject var clock: PlaybackClock

    @State private var dragOffset: CGFloat = 0
    @State private var playPausePressed = false
    @State private var previousPressed = false
    @State private var nextPressed = false
    @State private var showQueue = false

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

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height

            ZStack {
                Color.black.ignoresSafeArea()

                AppleMusicMovingBleedBackground(
                    artworkData: nowPlayingArtworkData
                )
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .gesture(dismissGesture(height: geometry.size.height))

                if isLandscape {
                    HStack(spacing: geometry.size.width * 0.035) {
                        artworkPane(maxHeight: geometry.size.height * 0.48)
                            .frame(width: geometry.size.width * 0.35)
                            .contentShape(Rectangle())
                            .gesture(dismissGesture(height: geometry.size.height))

                        lyricsPane
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.horizontal, 48)
                    .padding(.vertical, 24)
                } else {
                    VStack(spacing: 18) {
                        artworkPane(maxHeight: geometry.size.height * 0.38)
                            .contentShape(Rectangle())
                            .gesture(dismissGesture(height: geometry.size.height))

                        lyricsPane
                    }
                    .padding(.horizontal, 24)
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
                .padding(.trailing, 10)
                .padding(.top, 8)
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

            playbackControls
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
                LazyArtwork(url: track.url, size: min(maxHeight, 420), cornerRadius: 12)
                    .frame(maxHeight: maxHeight)
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

    private var playbackControls: some View {
        HStack(spacing: 36) {
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
    }

    private var repeatIcon: String {
        switch audioManager.repeatMode {
        case .off, .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

// MARK: - Lyrics

private var lyricsPane: some View {
    let lyrics = audioManager.currentLyrics
    let activeID = activeLyricID(lyrics: lyrics)
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
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
        } else {
            SmoothLyricsView(
                lyrics: lyrics,
                activeID: activeID,
                trackID: trackID
            ) { time in
                audioManager.seek(to: time)
            }
        }
    }
}

private func activeLyricID(
    lyrics: [LyricLine]
) -> UUID? {

    guard !lyrics.isEmpty else {
        return nil
    }

    return lyrics.last {
        $0.time <= audioManager.currentTime
    }?.id
}


// MARK: - Smooth Lyrics View

private struct SmoothLyricsView: View {

    let lyrics: [LyricLine]
    let activeID: UUID?
    let trackID: UUID?
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        ScrollViewReader { proxy in

            ScrollView(
                showsIndicators: false
            ) {

                LazyVStack(
                    alignment: .leading,
                    spacing: 30
                ) {

                    ForEach(lyrics) { line in

                        lyricLine(
                            line: line,
                            active: line.id == activeID
                        )
                        .id(line.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSeek(line.time)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 220)
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(
                            color: .clear,
                            location: 0
                        ),

                        .init(
                            color: .black,
                            location: 0.12
                        ),

                        .init(
                            color: .black,
                            location: 0.88
                        ),

                        .init(
                            color: .clear,
                            location: 1
                        )
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            // MARK: - New Song

            .onChange(
                of: trackID
            ) { _, newTrackID in

                guard newTrackID != nil else {
                    return
                }

                guard let firstLyric = lyrics.first else {
                    return
                }

                // Wait one run-loop cycle so the new lyrics
                // have been inserted into the ScrollView.
                DispatchQueue.main.async {

                    withAnimation(
                        .easeOut(duration: 0.38)
                    ) {
                        proxy.scrollTo(
                            firstLyric.id,
                            anchor: .center
                        )
                    }
                }
            }

            // MARK: - Active Lyric

            .onChange(
                of: activeID
            ) { _, newID in

                guard let newID else {
                    return
                }

                withAnimation(
                    .smooth(
                        duration: 0.55,
                        extraBounce: 0.04
                    )
                ) {
                    proxy.scrollTo(
                        newID,
                        anchor: .center
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func lyricLine(
        line: LyricLine,
        active: Bool
    ) -> some View {

        VStack(
            alignment: .leading,
            spacing: 7
        ) {

            if line.text
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty {

                HStack(spacing: 7) {

                    Circle()
                        .frame(
                            width: 8,
                            height: 8
                        )

                    Circle()
                        .frame(
                            width: 8,
                            height: 8
                        )

                    Circle()
                        .frame(
                            width: 8,
                            height: 8
                        )
                }
                .foregroundStyle(.white)
                .opacity(
                    active
                        ? 0.9
                        : 0.22
                )
                .padding(.vertical, 10)

            } else {

                Text(line.text)
                    .font(
                        .system(
                            size: 50,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white)
                    .opacity(
                        active
                            ? 1
                            : 0.30
                    )
                    .blur(
                        radius:
                            active
                                ? 0
                                : 1.8
                    )
                    .scaleEffect(
                        active
                            ? 1
                            : 0.985,
                        anchor: .leading
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )

                if let romanized = line.romanized,
                   !romanized.isEmpty {

                    Text(romanized)
                        .font(
                            .system(
                                size: 22,
                                weight: .medium,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(.white)
                        .opacity(
                            active
                                ? 0.72
                                : 0.20
                        )
                        .blur(
                            radius:
                                active
                                    ? 0
                                    : 1.2
                        )
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                }
            }
        }
        .animation(
            .easeInOut(duration: 0.22),
            value: active
        )
    }
}

// MARK: - Apple Music Scrubber

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

    @ViewBuilder
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

        Image(uiImage: image)
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
            .rotationEffect(
                .degrees(angle)
            )
            .offset(
                x: CGFloat(x),
                y: CGFloat(y)
            )
            .blur(
                radius: blur,
                opaque: true
            )
            .saturation(1.12)
            .brightness(0.0)
            .opacity(opacity)
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