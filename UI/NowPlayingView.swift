import SwiftUI

struct NowPlayingView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var audioManager: AudioEngineManager
    @State private var showingQueue = false
    @State private var animateBleed = false

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                liquidBleedBackground(size: geo.size)

                if isLandscape {
                    HStack(spacing: 32) {
                        artworkPane(maxHeight: geo.size.height * 0.44)
                            .frame(maxWidth: geo.size.width * 0.44)
                        
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
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                        .padding(20)
                }
            }
            .overlay(alignment: .topTrailing) {
                Button { showingQueue.toggle() } label: {
                    Image(systemName: showingQueue ? "quote.bubble.fill" : "list.bullet")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                        .padding(20)
                }
            }
        }
        .onAppear {
            animateBleed = true
        }
    }

    private func liquidBleedBackground(size: CGSize) -> some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            if let data = audioManager.currentTrack?.artworkData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(animateBleed ? 1.4 : 1.15)
                    .rotationEffect(.degrees(animateBleed ? 15 : -15))
                    .blur(radius: 85)
                    .opacity(0.7)
                    .animation(.easeInOut(duration: 8).repeatForever(autoreverses: true), value: animateBleed)
            } else {
                Circle()
                    .fill(Color.purple.opacity(0.55))
                    .frame(width: size.width * 0.7, height: size.width * 0.7)
                    .blur(radius: 90)
                    .offset(x: animateBleed ? -120 : 120, y: animateBleed ? -90 : 90)
                    .animation(.easeInOut(duration: 7).repeatForever(autoreverses: true), value: animateBleed)

                Circle()
                    .fill(Color.blue.opacity(0.55))
                    .frame(width: size.width * 0.65, height: size.width * 0.65)
                    .blur(radius: 90)
                    .offset(x: animateBleed ? 120 : -120, y: animateBleed ? 90 : -90)
                    .animation(.easeInOut(duration: 6).repeatForever(autoreverses: true), value: animateBleed)
            }

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.35)
                .edgesIgnoringSafeArea(.all)
        }
    }

    private func artworkPane(maxHeight: CGFloat) -> some View {
        VStack(spacing: 14) {
            Spacer(minLength: 10)

            if let data = audioManager.currentTrack?.artworkData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: maxHeight)
                    .cornerRadius(22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.45), .white.opacity(0.08), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: .black.opacity(0.55), radius: 25, y: 12)
            } else {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: maxHeight, height: maxHeight)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 54))
                            .foregroundColor(.white.opacity(0.35))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
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

            HStack(spacing: 34) {
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

            Spacer(minLength: 10)
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
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .opacity(0.65)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.35), .white.opacity(0.08), .clear, .white.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 25, x: 0, y: 15)
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
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(lyrics) { line in
                            let isActive = line.id == activeId
                            VStack(alignment: .leading, spacing: 4) {
                                Text(line.text)
                                    .font(.system(size: isActive ? 30 : 22, weight: .bold, design: .rounded))
                                    .foregroundColor(isActive ? .white : .white.opacity(0.25))
                                    .blur(radius: isActive ? 0 : 0.6)
                                    .scaleEffect(isActive ? 1.02 : 0.98, anchor: .leading)
                                    .shadow(color: isActive ? .white.opacity(0.35) : .clear, radius: 10)

                                if let romaji = line.romanized, !romaji.isEmpty {
                                    Text(romaji)
                                        .font(.system(size: isActive ? 15 : 12, weight: .medium, design: .rounded))
                                        .foregroundColor(isActive ? .white.opacity(0.85) : .white.opacity(0.2))
                                        .blur(radius: isActive ? 0 : 0.4)
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
                    .padding(.horizontal, 28)
                }
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
