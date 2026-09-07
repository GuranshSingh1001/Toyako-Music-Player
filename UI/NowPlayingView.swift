import SwiftUI

struct NowPlayingView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var audioManager: AudioEngineManager
    @State private var showingQueue = false
    @State private var animateMesh = false

    var body: some View {
        GeometryReader { geo in
            let isSplit = geo.size.width > 750

            ZStack {
                animatedBackground

                if isSplit {
                    HStack(spacing: 48) {
                        artworkPane
                            .frame(width: geo.size.width * 0.44)
                        rightPane
                            .frame(width: geo.size.width * 0.48)
                    }
                    .padding(36)
                } else {
                    VStack(spacing: 24) {
                        artworkPane
                        rightPane
                    }
                    .padding(20)
                }
            }
            .overlay(alignment: .topLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(24)
                }
            }
            .overlay(alignment: .topTrailing) {
                Button { showingQueue.toggle() } label: {
                    Image(systemName: showingQueue ? "quote.bubble.fill" : "list.bullet.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(24)
                }
            }
        }
        .onAppear {
            animateMesh = true
        }
    }

    private var animatedBackground: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            if let data = audioManager.currentTrack?.artworkData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(animateMesh ? 1.35 : 1.15)
                    .rotationEffect(.degrees(animateMesh ? 12 : -12))
                    .blur(radius: 75)
                    .opacity(0.65)
                    .animation(.easeInOut(duration: 8).repeatForever(autoreverses: true), value: animateMesh)
            } else {
                Circle()
                    .fill(Color.purple.opacity(0.4))
                    .frame(width: 450, height: 450)
                    .blur(radius: 80)
                    .offset(x: animateMesh ? -100 : 100, y: animateMesh ? -80 : 80)
                    .animation(.easeInOut(duration: 7).repeatForever(autoreverses: true), value: animateMesh)

                Circle()
                    .fill(Color.blue.opacity(0.4))
                    .frame(width: 450, height: 450)
                    .blur(radius: 80)
                    .offset(x: animateMesh ? 100 : -100, y: animateMesh ? 80 : -80)
                    .animation(.easeInOut(duration: 6).repeatForever(autoreverses: true), value: animateMesh)
            }

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.35)
                .edgesIgnoringSafeArea(.all)
        }
    }

    private var artworkPane: some View {
        VStack(spacing: 22) {
            Spacer()

            if let data = audioManager.currentTrack?.artworkData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(20)
                    .shadow(color: .black.opacity(0.6), radius: 30, y: 15)
            } else {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.08))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 64))
                            .foregroundColor(.white.opacity(0.3))
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(audioManager.currentTrack?.title ?? "Unknown Title")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("\(audioManager.currentTrack?.artist ?? "Unknown Artist") — \(audioManager.currentTrack?.album ?? "Unknown Album")")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
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
                .font(.caption.monospacedDigit())
                .foregroundColor(.white.opacity(0.5))
            }

            HStack(spacing: 36) {
                Button { audioManager.toggleShuffle() } label: {
                    Image(systemName: "shuffle")
                        .font(.title3)
                        .foregroundColor(audioManager.isShuffle ? .white : .white.opacity(0.3))
                }

                Button { audioManager.backward() } label: {
                    Image(systemName: "backward.fill").font(.title)
                }

                Button { audioManager.togglePlayPause() } label: {
                    Image(systemName: audioManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                }

                Button { audioManager.forward() } label: {
                    Image(systemName: "forward.fill").font(.title)
                }

                Button { audioManager.toggleRepeat() } label: {
                    Image(systemName: repeatIcon())
                        .font(.title3)
                        .foregroundColor(audioManager.repeatMode != .off ? .white : .white.opacity(0.3))
                }
            }
            .foregroundColor(.white)
            Spacer()
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
    }

    private var lyricsPane: some View {
        let lyrics = audioManager.currentLyrics
        let activeId = activeLineId()

        return ScrollViewReader { proxy in
            if lyrics.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 48))
                        .foregroundColor(.white.opacity(0.2))
                    Text("Lyrics Unavailable")
                        .font(.title3.weight(.medium))
                        .foregroundColor(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 32) {
                        ForEach(lyrics) { line in
                            let isActive = line.id == activeId
                            Text(line.text)
                                .font(.system(size: isActive ? 34 : 26, weight: .bold, design: .rounded))
                                .foregroundColor(isActive ? .white : .white.opacity(0.25))
                                .blur(radius: isActive ? 0 : 0.8)
                                .scaleEffect(isActive ? 1.04 : 0.98, anchor: .leading)
                                .shadow(color: isActive ? .white.opacity(0.3) : .clear, radius: 10)
                                .id(line.id)
                                .onTapGesture {
                                    audioManager.seek(to: line.time)
                                }
                                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isActive)
                        }
                    }
                    .padding(.vertical, 180)
                    .padding(.horizontal, 24)
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
                .font(.title2.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 8)

            List {
                ForEach(Array(audioManager.queue.enumerated()), id: \.element.id) { idx, item in
                    HStack(spacing: 14) {
                        Text("\(idx + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.white.opacity(0.4))
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.headline)
                                .foregroundColor(idx == audioManager.queueIndex ? Color.accentColor : Color.white)
                                .lineLimit(1)
                            Text(item.artist)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.5))
                                .lineLimit(1)
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.04))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        audioManager.queueIndex = idx
                        audioManager.play(track: item)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
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
