import SwiftUI

struct NowPlayingView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var audioManager: AudioEngineManager
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                appleMusicBrightBleedBackground(size: geo.size)

                if isLandscape {
                    HStack(spacing: geo.size.width * 0.05) {
                        artworkPane(maxHeight: geo.size.height * 0.52)
                            .frame(width: geo.size.width * 0.44)

                        lyricsPane
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.horizontal, 48)
                    .padding(.vertical, 24)
                } else {
                    VStack(spacing: 20) {
                        artworkPane(maxHeight: geo.size.height * 0.38)
                        lyricsPane
                    }
                    .padding(24)
                }
            }
            .overlay(alignment: .topLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(24)
                }
            }
            .offset(y: max(0, dragOffset))
            // High-responsiveness interactive swipe-down gesture
            .gesture(
                DragGesture(coordinateSpace: .local)
                    .updating($dragOffset) { value, state, _ in
                        if value.translation.height > 0 {
                            state = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > 60 || value.predictedEndTranslation.height > 120 {
                            dismiss()
                        }
                    }
            )
            .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.85), value: dragOffset)
        }
    }

    // MARK: - Extra Bright & Vibrant Apple Music Background
    private func appleMusicBrightBleedBackground(size: CGSize) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let data = audioManager.currentTrack?.artworkData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(1.4)
                    .clipped()
                    .blur(radius: 50)
                    .saturation(1.6)
                    .contrast(1.1)
                    .opacity(0.98)

                // Luminous warm tint to make the background feel brighter
                Color.white.opacity(0.12)
                Color.black.opacity(0.05)
            } else {
                Color.black
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Left Pane: Artwork, Metadata, Controls
    private func artworkPane(maxHeight: CGFloat) -> some View {
        VStack(spacing: 18) {
            Spacer(minLength: 8)

            if let data = audioManager.currentTrack?.artworkData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: maxHeight)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: maxHeight, height: maxHeight)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 54))
                            .foregroundColor(.white.opacity(0.35))
                    )
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(audioManager.currentTrack?.title ?? "Unknown Title")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(audioManager.currentTrack?.artist ?? "Unknown Artist")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)

            VStack(spacing: 6) {
                Slider(
                    value: Binding(
                        get: { audioManager.playbackProgress },
                        set: { newProgress in
                            if let dur = audioManager.currentTrack?.duration {
                                audioManager.seek(to: newProgress * dur)
                            }
                        }
                    ),
                    in: 0.0...1.0
                )
                .tint(.white)

                HStack {
                    Text(formatTime(audioManager.currentTime))
                    Spacer()
                    Text("-" + formatTime(max(0, (audioManager.currentTrack?.duration ?? 0) - audioManager.currentTime)))
                }
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.65))
            }
            .padding(.horizontal, 4)

            HStack(spacing: 40) {
                Button { audioManager.toggleShuffle() } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(audioManager.isShuffle ? .white : .white.opacity(0.35))
                }

                Button { audioManager.backward() } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 26))
                }

                Button { audioManager.togglePlayPause() } label: {
                    Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 38))
                        .frame(width: 44, height: 44)
                }

                Button { audioManager.forward() } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 26))
                }

                Button { audioManager.toggleRepeat() } label: {
                    Image(systemName: repeatIcon())
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(audioManager.repeatMode != .off ? .white : .white.opacity(0.35))
                }
            }
            .foregroundColor(.white)
            .padding(.vertical, 4)

            Spacer(minLength: 8)
        }
    }

    // MARK: - Large Apple Music Scale Lyrics Pane
    private var lyricsPane: some View {
        let lyrics = audioManager.currentLyrics
        let activeId = activeLineId()

        return ScrollViewReader { proxy in
            if lyrics.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 42))
                        .foregroundColor(.white.opacity(0.2))
                    Text("Lyrics Unavailable")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 36) {
                        ForEach(lyrics) { line in
                            let isActive = line.id == activeId

                            VStack(alignment: .leading, spacing: 8) {
                                if line.text.trimmingCharacters(in: .whitespaces).isEmpty {
                                    HStack(spacing: 8) {
                                        Circle().frame(width: 9, height: 9)
                                        Circle().frame(width: 9, height: 9)
                                        Circle().frame(width: 9, height: 9)
                                    }
                                    .foregroundColor(.white)
                                    .opacity(isActive ? 0.95 : 0.25)
                                    .padding(.vertical, 10)
                                } else {
                                    // Scaled up to 38pt matching Apple Music iPad lyrics size
                                    Text(line.text)
                                        .font(.system(size: 38, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .opacity(isActive ? 1.0 : 0.35)

                                    if let romaji = line.romanized, !romaji.isEmpty {
                                        Text(romaji)
                                            .font(.system(size: 18, weight: .medium, design: .rounded))
                                            .foregroundColor(.white)
                                            .opacity(isActive ? 0.8 : 0.25)
                                    }
                                }
                            }
                            .id(line.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                audioManager.seek(to: line.time)
                            }
                            .animation(.easeInOut(duration: 0.3), value: isActive)
                        }
                    }
                    .padding(.vertical, 220)
                    .padding(.horizontal, 16)
                }
                .mask(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .black, location: 0.15),
                            .init(color: .black, location: 0.85),
                            .init(color: .clear, location: 1.0)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .onChange(of: audioManager.currentTime) { _, _ in
                    if let activeId = activeId {
                        withAnimation(.easeInOut(duration: 0.45)) {
                            proxy.scrollTo(activeId, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func repeatIcon() -> String {
        switch audioManager.repeatMode {
        case .off, .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    private func activeLineId() -> UUID? {
        audioManager.currentLyrics.last(where: { $0.time <= audioManager.currentTime })?.id
    }

    private func formatTime(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
