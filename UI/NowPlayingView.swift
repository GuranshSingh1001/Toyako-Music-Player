import SwiftUI

struct NowPlayingView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var audioManager: AudioEngineManager
    @State private var showingQueue = false

    var body: some View {
        GeometryReader { geo in
            let isSplit = geo.size.width > 700

            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)

                if isSplit {
                    HStack(spacing: 40) {
                        artworkPane
                            .frame(width: geo.size.width * 0.45)
                        rightPane
                            .frame(width: geo.size.width * 0.50)
                    }
                    .padding(32)
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
                        .font(.title)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(24)
                }
            }
            .overlay(alignment: .topTrailing) {
                Button { showingQueue.toggle() } label: {
                    Image(systemName: showingQueue ? "quote.bubble.fill" : "list.bullet.circle.fill")
                        .font(.title)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(24)
                }
            }
        }
    }

    private var artworkPane: some View {
        VStack(spacing: 20) {
            Spacer()
            if let data = audioManager.currentTrack?.artworkData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.5), radius: 24)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(Image(systemName: "music.note").font(.system(size: 60)).foregroundColor(.white.opacity(0.4)))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(audioManager.currentTrack?.title ?? "Unknown Title")
                    .font(.title.bold())
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("\(audioManager.currentTrack?.artist ?? "Unknown Artist") — \(audioManager.currentTrack?.album ?? "Unknown Album")")
                    .font(.title3)
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

            HStack(spacing: 50) {
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
        ScrollViewReader { proxy in
            if audioManager.currentLyrics.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "text.bubble")
                        .font(.largeTitle)
                        .foregroundColor(.white.opacity(0.3))
                    Text("No Lyrics Available")
                        .foregroundColor(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 28) {
                        ForEach(audioManager.currentLyrics) { line in
                            let active = line.id == activeLineId()
                            Text(line.text)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(active ? .white : .white.opacity(0.2))
                                .scaleEffect(active ? 1.05 : 1.0, anchor: .leading)
                                .id(line.id)
                                .onTapGesture {
                                    audioManager.seek(to: line.time)
                                }
                        }
                    }
                    .padding(.vertical, 160)
                    .padding(.horizontal, 24)
                }
                .onChange(of: audioManager.currentTime) { _, _ in
                    if let activeId = activeLineId() {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            proxy.scrollTo(activeId, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private var queuePane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Playing Next")
                .font(.title2.bold())
                .foregroundColor(.white)
                .padding(.horizontal)

            List {
                ForEach(Array(audioManager.queue.enumerated()), id: \.element.id) { idx, item in
                    HStack {
                        Text("\(idx + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.gray)
                            .frame(width: 24)
                        VStack(alignment: .leading) {
                            Text(item.title)
                                .font(.headline)
                                .foregroundColor(idx == audioManager.queueIndex ? .accentColor : .primary)
                            Text(item.artist)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        audioManager.queueIndex = idx
                        audioManager.play(track: item)
                    }
                }
            }
            .listStyle(.plain)
            .cornerRadius(12)
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
