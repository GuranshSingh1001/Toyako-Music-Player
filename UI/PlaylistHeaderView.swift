import SwiftUI

struct PlaylistHeaderView: View {
    let playlist: Playlist
    let tracks: [LocalTrack]
    let onAddSongs: () -> Void

    @EnvironmentObject var audioManager: AudioEngineManager
    @State private var heroVisible = false

    private var artworkURLs: [URL] {
        guard !tracks.isEmpty else { return [] }
        return (0..<24).map { index in
            tracks[(index * 5 + stableSeed) % tracks.count].url
        }
    }

    private var stableSeed: Int {
        var value = 0
        for byte in playlist.id.uuidString.utf8 {
            value = (value &* 31) &+ Int(byte)
        }
        return abs(value)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let wide = width >= 820
            let height = wide ? min(390, max(320, width * 0.34)) : min(360, max(300, width * 0.82))

            ZStack(alignment: .bottomLeading) {
                marqueeArtwork(width: width, height: height)

                LinearGradient(
                    colors: [
                        .black.opacity(0.04),
                        .black.opacity(0.18),
                        .black.opacity(0.88)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 9) {
                    Text("PLAYLIST")
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.72))

                    Text(playlist.name)
                        .font(.system(size: wide ? 40 : 32, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)

                    Text("\(tracks.count) \(tracks.count == 1 ? "Song" : "Tracks") • \(totalDurationString)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.78))

                    HStack(spacing: 10) {
                        playButton
                        shuffleButton
                        addButton
                    }
                    .padding(.top, 5)
                }
                .padding(.horizontal, wide ? 34 : 22)
                .padding(.bottom, wide ? 28 : 22)
                .opacity(heroVisible ? 1 : 0)
                .offset(y: heroVisible ? 0 : 14)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.28), radius: 18, y: 9)
            .padding(.horizontal, wide ? 24 : 16)
            .padding(.top, 16)
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                    heroVisible = true
                }
            }
        }
        .frame(height: 390)
    }

    private func marqueeArtwork(width: CGFloat, height: CGFloat) -> some View {
        let tile = min(132, max(88, height * 0.34))
        let rowGap = tile * 0.10

        return ZStack {
            Color.black

            VStack(spacing: rowGap) {
                marqueeRow(tile: tile, rotationSeed: 0, direction: -1, width: width)
                marqueeRow(tile: tile, rotationSeed: 7, direction: 1, width: width)
                marqueeRow(tile: tile, rotationSeed: 13, direction: -1, width: width)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .overlay {
            LinearGradient(
                colors: [.black.opacity(0.08), .clear, .black.opacity(0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func marqueeRow(tile: CGFloat, rotationSeed: Int, direction: CGFloat, width: CGFloat) -> some View {
        let rowURLs = Array(artworkURLs.dropFirst(rotationSeed % max(1, artworkURLs.count))) + artworkURLs
        let sequence = Array(rowURLs.prefix(16))

        return GeometryReader { proxy in
            HStack(spacing: -tile * 0.12) {
                ForEach(Array(sequence.enumerated()), id: \.offset) { index, url in
                    LazyArtwork(url: url, size: tile, cornerRadius: tile * 0.08)
                        .rotationEffect(.degrees(Double(((index + rotationSeed) % 7) - 3)))
                        .shadow(color: .black.opacity(0.32), radius: 7, y: 4)
                }
            }
            .frame(height: tile)
            .offset(x: direction < 0 ? -tile * 2.2 : -tile * 0.7)
            .modifier(MarqueeMotion(direction: direction, distance: tile * 3.8, duration: 22 + Double(rotationSeed % 5)))
        }
        .frame(height: tile)
    }

    private var playButton: some View {
        Button {
            guard !tracks.isEmpty else { return }
            audioManager.startQueue(tracks: tracks, startIndex: 0, shuffle: false)
        } label: {
            Label("Play", systemImage: "play.fill")
                .font(.subheadline.bold())
        }
        .buttonStyle(.borderedProminent)
        .tint(.white)
        .foregroundStyle(.black)
    }

    private var shuffleButton: some View {
        Button {
            guard !tracks.isEmpty else { return }
            audioManager.startQueue(
                tracks: tracks,
                startIndex: Int.random(in: 0..<tracks.count),
                shuffle: true
            )
        } label: {
            Label("Shuffle", systemImage: "shuffle")
                .font(.subheadline.bold())
        }
        .buttonStyle(.bordered)
        .tint(.white)
        .foregroundStyle(.white)
    }

    private var addButton: some View {
        Button(action: onAddSongs) {
            Label("Add Songs", systemImage: "plus")
                .font(.subheadline.bold())
        }
        .buttonStyle(.bordered)
        .tint(.white)
        .foregroundStyle(.white)
    }

    private var totalDurationString: String {
        let total = tracks.reduce(0) { $0 + $1.duration }
        let seconds = max(0, Int(total))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours) hr \(minutes) min" : "\(minutes) min"
    }
}

private struct MarqueeMotion: ViewModifier {
    let direction: CGFloat
    let distance: CGFloat
    let duration: Double
    @State private var moved = false

    func body(content: Content) -> some View {
        content
            .offset(x: moved ? direction * distance : 0)
            .onAppear {
                withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                    moved = true
                }
            }
    }
}
