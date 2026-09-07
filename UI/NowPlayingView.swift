import SwiftUI
import MediaPlayer
import AVFoundation

struct NowPlayingView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var audioManager: AudioEngineManager
    
    @State private var showingQueue = false
    @State private var showRomaji = true
    @State private var isFavorite = false
    @State private var volume: Float = AVAudioSession.sharedInstance().outputVolume

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                ambientBackground(size: geo.size)

                VStack(spacing: 0) {
                    // Top Pill Grabber
                    Capsule()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 44, height: 5)
                        .padding(.top, 14)
                        .padding(.bottom, 8)
                        .onTapGesture { dismiss() }

                    if isLandscape {
                        HStack(alignment: .center, spacing: geo.size.width * 0.06) {
                            leftPlayerPane(maxHeight: geo.size.height * 0.58)
                                .frame(width: geo.size.width * 0.44)

                            rightContentPane
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .padding(.horizontal, 48)
                        .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 20) {
                            leftPlayerPane(maxHeight: geo.size.height * 0.40)
                            rightContentPane
                        }
                        .padding(24)
                    }

                    // Bottom AirPlay and Utility Footer
                    bottomUtilityBar
                        .padding(.horizontal, 48)
                        .padding(.bottom, 20)
                }
            }
        }
    }

    // MARK: - Ambient Blurred Background
    private func ambientBackground(size: CGSize) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let data = audioManager.currentTrack?.artworkData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .blur(radius: 70)
                    .saturation(1.3)
                    .opacity(0.60)
            } else {
                LinearGradient(
                    colors: [Color(red: 0.18, green: 0.15, blue: 0.15), Color.black],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            // Dark vignette overlay for Apple Music contrast
            LinearGradient(
                colors: [
                    Color.black.opacity(0.25),
                    Color.black.opacity(0.55),
                    Color.black.opacity(0.85)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Left Pane: Artwork, Metadata, Scrubber, Controls
    private func leftPlayerPane(maxHeight: CGFloat) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 4)

            // Album Artwork
            if let data = audioManager.currentTrack?.artworkData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: maxHeight)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: maxHeight, height: maxHeight)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.3))
                    )
            }

            // Title & Artist + Favorite & More Buttons
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(audioManager.currentTrack?.title ?? "Not Playing")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(audioManager.currentTrack?.artist ?? "Unknown Artist")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 16) {
                    Button {
                        isFavorite.toggle()
                    } label: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .font(.system(size: 18))
                            .foregroundColor(isFavorite ? .yellow : .white.opacity(0.7))
                    }

                    Menu {
                        Button("Go to Artist") {}
                        Button("Go to Album") {}
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, 4)

            // Scrubber Bar
            VStack(spacing: 4) {
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
                .tint(.white.opacity(0.85))

                HStack {
                    Text(formatTime(audioManager.currentTime))
                    Spacer()
                    Text("-" + formatTime(max(0, (audioManager.currentTrack?.duration ?? 0) - audioManager.currentTime)))
                }
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.55))
            }
            .padding(.horizontal, 2)

            // Playback Controls
            HStack(spacing: 36) {
                Button { audioManager.toggleShuffle() } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(audioManager.isShuffle ? .white : .white.opacity(0.35))
                }

                Button { audioManager.backward() } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 28))
                }

                Button { audioManager.togglePlayPause() } label: {
                    Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 40))
                        .frame(width: 48, height: 48)
                }

                Button { audioManager.forward() } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 28))
                }

                Button { audioManager.toggleRepeat() } label: {
                    Image(systemName: repeatIcon())
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(audioManager.repeatMode != .off ? .white : .white.opacity(0.35))
                }
            }
            .foregroundColor(.white)
            .padding(.vertical, 4)

            // Volume Slider
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))

                Slider(value: $volume, in: 0...1)
                    .tint(.white.opacity(0.75))

                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 4)

            Spacer(minLength: 4)
        }
    }

    // MARK: - Right Content Pane: Lyrics & Queue
    private var rightContentPane: some View {
        VStack(spacing: 0) {
            // Lyrics Header Utilities (Sing tool & Romaji toggle)
            if !showingQueue {
                HStack {
                    Spacer()
                    Button {
                        // Sing tool placeholder
                    } label: {
                        Image(systemName: "mic.fill.badge.plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                    }

                    Button {
                        showRomaji.toggle()
                    } label: {
                        Image(systemName: "character.bubble")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(showRomaji ? .white : .white.opacity(0.4))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            if showingQueue {
                queuePane
            } else {
                lyricsPane
            }
        }
    }

    // MARK: - Clean Apple Music Typography Lyrics
    private var lyricsPane: some View {
        let lyrics = audioManager.currentLyrics
        let activeId = activeLineId()

        return ScrollViewReader { proxy in
            if lyrics.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 44))
                        .foregroundColor(.white.opacity(0.25))
                    Text("Lyrics Unavailable")
                        .font(.title3.weight(.medium))
                        .foregroundColor(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 32) {
                        ForEach(Array(lyrics.enumerated()), id: \.element.id) { index, line in
                            let isActive = line.id == activeId
                            let distance = activeDistance(activeId: activeId, currentIndex: index, lyrics: lyrics)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(line.text)
                                    .font(.system(size: isActive ? 34 : 28, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .opacity(isActive ? 1.0 : max(0.18, 0.45 - (Double(distance) * 0.08)))
                                    .blur(radius: isActive ? 0 : min(CGFloat(distance) * 0.45, 1.2))
                                    .scaleEffect(isActive ? 1.02 : 0.99, anchor: .leading)

                                if showRomaji, let romaji = line.romanized, !romaji.isEmpty {
                                    Text(romaji)
                                        .font(.system(size: isActive ? 16 : 13, weight: .medium, design: .rounded))
                                        .foregroundColor(.white)
                                        .opacity(isActive ? 0.75 : max(0.12, 0.32 - (Double(distance) * 0.06)))
                                        .blur(radius: isActive ? 0 : min(CGFloat(distance) * 0.3, 0.9))
                                }
                            }
                            .id(line.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                audioManager.seek(to: line.time)
                            }
                            .animation(.spring(response: 0.38, dampingFraction: 0.8), value: isActive)
                        }
                    }
                    .padding(.vertical, 180)
                    .padding(.horizontal, 16)
                }
                .mask(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .black, location: 0.12),
                            .init(color: .black, location: 0.88),
                            .init(color: .clear, location: 1.0)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .onChange(of: audioManager.currentTime) { _, _ in
                    if let activeId = activeId {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            proxy.scrollTo(activeId, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Queue Pane
    private var queuePane: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Playing Next")
                .font(.title3.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            List {
                ForEach(Array(audioManager.queue.enumerated()), id: \.element.id) { idx, item in
                    HStack(spacing: 12) {
                        Text("\(idx + 1)")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.white.opacity(0.4))
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.bold())
                                .foregroundColor(idx == audioManager.queueIndex ? Color.accentColor : Color.white)
                                .lineLimit(1)
                            Text(item.artist)
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.5))
                                .lineLimit(1)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        audioManager.queueIndex = idx
                        audioManager.play(track: item)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.08)))
    }

    // MARK: - Bottom Utility Bar
    private var bottomUtilityBar: some View {
        HStack {
            // Audio Output Destination
            HStack(spacing: 6) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 13))
                Text("iPad Speaker")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.75))

            Spacer()

            // Lyrics & Queue Toggle Switchers
            HStack(spacing: 24) {
                Button {
                    showingQueue = false
                } label: {
                    Image(systemName: "quote.bubble.fill")
                        .font(.system(size: 18))
                        .foregroundColor(!showingQueue ? .white : .white.opacity(0.4))
                }

                Button {
                    showingQueue = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 18))
                        .foregroundColor(showingQueue ? .white : .white.opacity(0.4))
                }
            }
        }
        .padding(.top, 6)
    }

    // MARK: - Helpers
    private func repeatIcon() -> String {
        switch audioManager.repeatMode {
        case .off, .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    private func activeLineId() -> UUID? {
        audioManager.currentLyrics.last(where: { $0.time <= audioManager.currentTime })?.id
    }

    private func activeDistance(activeId: UUID?, currentIndex: Int, lyrics: [LyricLine]) -> Int {
        guard let activeId = activeId,
              let activeIndex = lyrics.firstIndex(where: { $0.id == activeId }) else {
            return 0
        }
        return abs(activeIndex - currentIndex)
    }

    private func formatTime(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
