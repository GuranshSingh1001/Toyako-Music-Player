import SwiftUI

struct NowPlayingView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var audioManager: AudioEngineManager
    @State private var showingQueue = false

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                optimizedAmbientBackground(size: geo.size)

                if isLandscape {
                    HStack(spacing: 36) {
                        artworkPane(maxHeight: geo.size.height * 0.46)
                            .frame(width: geo.size.width * 0.44)
                        
                        rightPane
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 24)
                } else {
                    VStack(spacing: 16) {
                        artworkPane(maxHeight: geo.size.height * 0.38)
                        rightPane
                    }
                    .padding(20)
                }
            }
            .overlay(alignment: .topLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(width: 44, height: 44)
                        .liquidGlass(cornerRadius: 22, opacity: 0.6)
                        .padding(20)
                }
            }
            .overlay(alignment: .topTrailing) {
                Button { showingQueue.toggle() } label: {
                    Image(systemName: showingQueue ? "quote.bubble.fill" : "list.bullet")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(width: 44, height: 44)
                        .liquidGlass(cornerRadius: 22, opacity: 0.6)
                        .padding(20)
                }
            }
        }
    }

    private func optimizedAmbientBackground(size: CGSize) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let data = audioManager.currentTrack?.artworkData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .blur(radius: 50)
                    .opacity(0.48)
                    .overlay(Color.black.opacity(0.35))
            } else {
                LinearGradient(
                    colors: [Color(red: 0.12, green: 0.12, blue: 0.2), Color.black],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .drawingGroup()
        .ignoresSafeArea()
    }

    private func artworkPane(maxHeight: CGFloat) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)

            if let data = audioManager.currentTrack?.artworkData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: maxHeight)
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.55), radius: 24, y: 12)
            } else {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: maxHeight, height: maxHeight)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 54))
                            .foregroundColor(.white.opacity(0.35))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(audioManager.currentTrack?.title ?? "Unknown Title")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text("\(audioManager.currentTrack?.artist ?? "Unknown Artist") — \(audioManager.currentTrack?.album ?? "Unknown Album")")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
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
                    Text(formatTime(audioManager.currentTrack?.duration ?? 0))
                }
                .font(.caption2.monospacedDigit())
                .foregroundColor(.white.opacity(0.55))
            }
            .padding(.horizontal, 4)

            HStack(spacing: 32) {
                Button { audioManager.toggleShuffle() } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(audioManager.isShuffle ? .white : .white.opacity(0.3))
                }

                Button { audioManager.backward() } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 24))
                }

                Button { audioManager.togglePlayPause() } label: {
                    Image(systemName: audioManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56))
                }

                Button { audioManager.forward() } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 24))
                }

                Button { audioManager.toggleRepeat() } label: {
                    Image(systemName: repeatIcon())
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(audioManager.repeatMode != .off ? .white : .white.opacity(0.3))
                }
            }
            .foregroundColor(.white)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .liquidGlass(cornerRadius: 30, opacity: 0.35)

            Spacer(minLength: 8)
        }
    }

    private var rightPane: some View {
        VStack {
            if showingQueue {
                queuePane
            } else {
                lyricsPane
            }
        }
        .padding(.vertical, 8)
    }

    private var lyricsPane: some View {
        let lyrics = audioManager.currentLyrics
        let activeId = activeLineId()

        return ScrollViewReader { proxy in
            if lyrics.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 42))
                        .foregroundColor(.white.opacity(0.2))
                    Text("Lyrics Unavailable")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 28) {
                        ForEach(lyrics) { line in
                            let isActive = line.id == activeId
                            VStack(alignment: .leading, spacing: 6) {
                                Text(line.text)
                                    .font(.system(size: isActive ? 32 : 24, weight: .bold, design: .rounded))
                                    .foregroundColor(isActive ? .white : .white.opacity(0.25))
                                    .blur(radius: isActive ? 0 : 0.6)
                                    .scaleEffect(isActive ? 1.02 : 0.98, anchor: .leading)
                                    .shadow(color: isActive ? .white.opacity(0.35) : .clear, radius: 10)

                                if let romaji = line.romanized, !romaji.isEmpty {
                                    Text(romaji)
                                        .font(.system(size: isActive ? 15 : 12, weight: .medium, design: .rounded))
                                        .foregroundColor(isActive ? .white.opacity(0.85) : .white.opacity(0.2))
                                }
                            }
                            .id(line.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                audioManager.seek(to: line.time)
                            }
                            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isActive)
                        }
                    }
                    .padding(.vertical, 160)
                    .padding(.horizontal, 20)
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
        .liquidGlass(cornerRadius: 24, opacity: 0.4)
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
