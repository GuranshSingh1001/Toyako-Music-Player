import SwiftUI
import UIKit

struct NowPlayingView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var audioManager: AudioEngineManager
    let transitionNamespace: Namespace.ID

    @State private var dragOffset: CGFloat = 0
    @State private var playPausePressed = false
    @State private var previousPressed = false
    @State private var nextPressed = false
    @State private var showQueue = false

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height

            ZStack {
                Color.black.ignoresSafeArea()

                AppleMusicMovingBleedBackground(
                    artworkData: audioManager.currentTrack?.artworkData
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
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
                progress: audioManager.playbackProgress,
                duration: audioManager.currentTrack?.duration ?? 0,
                currentTime: audioManager.currentTime
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
        if let data = audioManager.currentTrack?.artworkData,
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: maxHeight)
                .clipShape(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .matchedGeometryEffect(
                    id: "nowPlayingArtwork",
                    in: transitionNamespace,
                    properties: .frame,
                    anchor: .center,
                    isSource: false
                )
                .shadow(color: .black.opacity(0.32), radius: 24, y: 12)
                .id(audioManager.currentTrack?.id)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .frame(width: maxHeight, height: maxHeight)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 52))
                        .foregroundStyle(.white.opacity(0.35))
                }
        }
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
                .scaleEffect(playPausePressed ? 0.76 : 1)
                .contentTransition(.symbolEffect(.replace))
                .animation(
                    .spring(response: 0.22, dampingFraction: 0.58),
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
                SmoothLyricsView(lyrics: lyrics, activeID: activeID) { time in
                    audioManager.seek(to: time)
                }
            }
        }
    }

    private func activeLyricID(lyrics: [LyricLine]) -> UUID? {
        lyrics.last { $0.time <= audioManager.currentTime }?.id
    }
}

// MARK: - Smooth Lyrics View

private struct SmoothLyricsView: View {
    let lyrics: [LyricLine]
    let activeID: UUID?
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 30) {
                    ForEach(lyrics) { line in
                        lyricLine(line: line, active: line.id == activeID)
                            .id(line.id)
                            .contentShape(Rectangle())
                            .onTapGesture { onSeek(line.time) }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 220)
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
            .onChange(of: activeID) { _, newID in
                guard let newID else { return }

                withAnimation(.smooth(duration: 0.55, extraBounce: 0.04)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func lyricLine(line: LyricLine, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(spacing: 7) {
                    Circle().frame(width: 8, height: 8)
                    Circle().frame(width: 8, height: 8)
                    Circle().frame(width: 8, height: 8)
                }
                .foregroundStyle(.white)
                .opacity(active ? 0.9 : 0.22)
                .padding(.vertical, 10)
            } else {
                Text(line.text)
                    .font(
                        .system(
                            size: active ? 50 : 50,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white)
                    .opacity(active ? 1 : 0.30)
                    .blur(radius: active ? 0 : 1.8)
                    .scaleEffect(active ? 1 : 0.985, anchor: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let romanized = line.romanized, !romanized.isEmpty {
                    Text(romanized)
                        .font(
                            .system(
                                size: active ? 22 : 22,
                                weight: .medium,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(.white)
                        .opacity(active ? 0.72 : 0.20)
                        .blur(radius: active ? 0 : 1.2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: active)
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
        min(1, max(0, progress))
    }

    private var shownProgress: Double {
        isHolding ? dragProgress : safeProgress
    }

    private var displayedTime: TimeInterval {
        duration * shownProgress
    }

    var body: some View {
        VStack(spacing: 7) {
            GeometryReader { geometry in
                Capsule()
                    .fill(.white.opacity(isHolding ? 0.30 : 0.18))
                    .frame(height: isHolding ? 9 : 5)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(isHolding ? 1.0 : 0.88))
                            .frame(
                                width: geometry.size.width * CGFloat(shownProgress),
                                height: isHolding ? 9 : 5
                            )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !isHolding {
                                    isHolding = true
                                    dragStartProgress = safeProgress
                                    dragProgress = safeProgress
                                    dragStartX = value.startLocation.x
                                }

                                // A tap/hold does not jump the slider. The drag is
                                // interpreted relative to the position where the finger
                                // first touched the control.
                                let deltaX = value.location.x - dragStartX
                                let delta = geometry.size.width > 0
                                    ? Double(deltaX / geometry.size.width)
                                    : 0

                                dragProgress = min(
                                    1,
                                    max(0, dragStartProgress + delta)
                                )
                            }
                            .onEnded { _ in
                                let finalProgress = min(1, max(0, dragProgress))

                                // A pure tap/hold produces no meaningful horizontal
                                // movement, so leave playback exactly where it was.
                                if abs(dragProgress - dragStartProgress) >= 0.002 {
                                    onSeek(finalProgress)
                                }

                                withAnimation(.easeOut(duration: 0.16)) {
                                    isHolding = false
                                }
                            }
                    )
            }
            .frame(height: 20)
            .transaction { transaction in
                // Playback progress is a live value; never interpolate it through
                // an inherited SwiftUI animation. Only the explicit hold animation
                // below is allowed to animate this control.
                transaction.animation = nil
            }

            HStack {
                Text(formatTime(displayedTime))
                Spacer()
                Text("-" + formatTime(max(0, duration - displayedTime)))
            }
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.62))
            .monospacedDigit()
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "0:00" }

        let seconds = max(0, Int(time.rounded(.down)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Moving Artwork Background

struct AppleMusicMovingBleedBackground: View {
    let artworkData: Data?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                Color.black

                if let artworkData,
                   let image = UIImage(data: artworkData) {

                    bleedLayer(
                        image: image,
                        time: t,
                        frequency: 0.071,
                        phase: 0.0,
                        scale: 1.42,
                        blur: 70,
                        opacity: 0.78
                    )

                    bleedLayer(
                        image: image,
                        time: t,
                        frequency: 0.053,
                        phase: 1.9,
                        scale: 1.54,
                        blur: 58,
                        opacity: 0.50
                    )

                    bleedLayer(
                        image: image,
                        time: t,
                        frequency: 0.037,
                        phase: 4.1,
                        scale: 1.68,
                        blur: 82,
                        opacity: 0.34
                    )

                    Color.black.opacity(0.18)
                } else {
                    LinearGradient(
                        colors: [.black, Color(white: 0.08), .black],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
        }
        .clipped()
        .drawingGroup(opaque: true)
        .animation(.smooth(duration: 0.8), value: artworkData?.hashValue)
    }

    @ViewBuilder
    private func bleedLayer(
        image: UIImage,
        time: TimeInterval,
        frequency: Double,
        phase: Double,
        scale: CGFloat,
        blur: CGFloat,
        opacity: Double
    ) -> some View {
        let a = time * frequency + phase
        let x = CGFloat(sin(a) * 34 + sin(a * 0.43 + 1.2) * 18)
        let y = CGFloat(cos(a * 0.87) * 30 + sin(a * 0.31 + 2.4) * 20)
        let rotation = sin(a * 0.67) * 8 + cos(a * 0.29) * 4
        let dynamicScale = scale + CGFloat(sin(a * 0.53) * 0.08)

        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .scaleEffect(dynamicScale)
            .rotationEffect(.degrees(rotation))
            .offset(x: x, y: y)
            .blur(radius: blur, opaque: true)
            .saturation(1.28)
            .brightness(-0.15)
            .opacity(opacity)
    }
}

