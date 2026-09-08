import SwiftUI
import UIKit

struct NowPlayingView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var audioManager: AudioEngineManager

    @State private var dragOffset: CGFloat = 0
    @State private var isVisible = false
    @State private var playPausePressed = false
    @State private var previousPressed = false
    @State private var nextPressed = false

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
            .offset(y: isVisible ? dragOffset : geometry.size.height)
        }
        .ignoresSafeArea()
        .onAppear {
            if isPresented { show() }
        }
        .onChange(of: isPresented) { _, presented in
            if presented {
                show()
            } else {
                dragOffset = 0
                isVisible = false
            }
        }
    }

    // MARK: - Presentation

    private func show() {
        dragOffset = 0

        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            isVisible = true
        }
    }

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

                withAnimation(.smooth(duration: 0.42)) {
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

    @State private var dragging = false
    @State private var dragProgress = 0.0

    private var shownProgress: Double {
        min(1, max(0, dragging ? dragProgress : progress))
    }

    private var displayedTime: TimeInterval {
        dragging ? duration * dragProgress : currentTime
    }

    var body: some View {
        VStack(spacing: 7) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(dragging ? 0.30 : 0.18))
                        .frame(height: dragging ? 9 : 5)

                    Capsule()
                        .fill(.white.opacity(dragging ? 1 : 0.88))
                        .frame(
                            width: geometry.size.width * CGFloat(shownProgress),
                            height: dragging ? 9 : 5
                        )

                    if dragging {
                        Circle()
                            .fill(.white)
                            .frame(width: 15, height: 15)
                            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                            .position(
                                x: thumbPosition(width: geometry.size.width),
                                y: geometry.size.height / 2
                            )
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !dragging {
                                withAnimation(
                                    .spring(response: 0.20, dampingFraction: 0.78)
                                ) {
                                    dragging = true
                                }
                            }

                            dragProgress = progressForX(
                                value.location.x,
                                width: geometry.size.width
                            )
                        }
                        .onEnded { value in
                            let newProgress = progressForX(
                                value.location.x,
                                width: geometry.size.width
                            )

                            dragProgress = newProgress
                            onSeek(newProgress)

                            withAnimation(
                                .spring(response: 0.27, dampingFraction: 0.82)
                            ) {
                                dragging = false
                            }
                        }
                )
                .animation(
                    .spring(response: 0.22, dampingFraction: 0.82),
                    value: dragging
                )
            }
            .frame(height: 20)

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

    private func progressForX(_ x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return max(0, min(1, Double(x / width)))
    }

    private func thumbPosition(width: CGFloat) -> CGFloat {
        let radius: CGFloat = 7.5
        guard width > radius * 2 else { return width / 2 }

        return max(
            radius,
            min(width - radius, width * CGFloat(shownProgress))
        )
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "0:00" }

        let seconds = max(0, Int(time))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Moving Artwork Background

struct AppleMusicMovingBleedBackground: View {
    let artworkData: Data?
    @State private var phase = false

    var body: some View {
        ZStack {
            Color.black

            if let artworkData,
               let image = UIImage(data: artworkData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(phase ? 1.48 : 1.32)
                    .rotationEffect(.degrees(phase ? 8 : -8))
                    .offset(x: phase ? 35 : -35, y: phase ? -28 : 28)
                    .blur(radius: 65, opaque: true)
                    .saturation(1.35)
                    .brightness(-0.14)
                    .opacity(0.82)

                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(phase ? 1.30 : 1.50)
                    .rotationEffect(.degrees(phase ? -10 : 10))
                    .offset(x: phase ? -30 : 30, y: phase ? 25 : -25)
                    .blur(radius: 52, opaque: true)
                    .saturation(1.2)
                    .brightness(-0.18)
                    .opacity(0.55)

                Color.black.opacity(0.16)
            } else {
                LinearGradient(
                    colors: [.black, Color(white: 0.08), .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .clipped()
        .onAppear {
            phase = false

            withAnimation(
                .easeInOut(duration: 16).repeatForever(autoreverses: true)
            ) {
                phase = true
            }
        }
        .id(artworkData?.hashValue ?? 0)
    }
}
