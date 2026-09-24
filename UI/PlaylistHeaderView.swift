import SwiftUI

struct PlaylistHeaderView: View {
    let playlist: Playlist
    let tracks: [LocalTrack]
    let onAddSongs: () -> Void

    @EnvironmentObject var audioManager: AudioEngineManager
    @State private var heroVisible = false

    private var artworkURLs: [URL] {
        guard !tracks.isEmpty else { return [] }
        // Use a long repeating stream so the marquee always feels full,
        // including for playlists with only a few tracks.
        return (0..<72).map { index in
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
            let height: CGFloat = wide
                ? min(390, max(330, width * 0.30))
                : min(350, max(290, width * 0.76))

            ZStack(alignment: .bottomLeading) {
                marqueeArtwork(width: width, height: height)

                // Keep the artwork visible while giving the metadata a clean,
                // readable area instead of placing text directly over large covers.
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.02), location: 0.0),
                        .init(color: .black.opacity(0.04), location: 0.38),
                        .init(color: .black.opacity(0.40), location: 0.66),
                        .init(color: .black.opacity(0.90), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("PLAYLIST")
                        .font(.caption.weight(.bold))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.70))

                    Text(playlist.name)
                        .font(.system(size: wide ? 38 : 30, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)

                    Text("\(tracks.count) \(tracks.count == 1 ? "Song" : "Tracks") • \(totalDurationString)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.78))

                    HStack(spacing: 9) {
                        playButton
                        shuffleButton
                        addButton
                    }
                    .padding(.top, 3)
                }
                .padding(.horizontal, wide ? 34 : 20)
                .padding(.bottom, wide ? 24 : 18)
                .frame(maxWidth: wide ? 560 : .infinity, alignment: .leading)
                .background {
                    // A subtle local scrim makes the text readable without
                    // turning the entire collage into a dark block.
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.black.opacity(0.22))
                        .blur(radius: 0.2)
                        .padding(.leading, wide ? 22 : 10)
                        .padding(.trailing, wide ? 80 : 10)
                        .padding(.vertical, -8)
                }
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
        let tile = min(156, max(118, height * 0.37))
        let rowSpacing = -tile * 0.16

        return ZStack {
            Color.black

            VStack(spacing: rowSpacing) {
                ForEach(0..<3, id: \.self) { row in
                    marqueeRow(tile: tile, row: row, direction: row.isMultiple(of: 2) ? -1 : 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .rotationEffect(.degrees(-0.8))
            .scaleEffect(1.08)
        }
        .overlay {
            LinearGradient(
                colors: [
                    .black.opacity(0.04),
                    .clear,
                    .black.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func marqueeRow(tile: CGFloat, row: Int, direction: CGFloat) -> some View {
        var generator = PlaylistHeaderRandom(seed: stableSeed &+ row * 7919)
        let count = 8
        var sequence: [URL] = []
        sequence.reserveCapacity(count)

        var shuffled = artworkURLs
        generator.shuffle(&shuffled)

        for index in 0..<count {
            sequence.append(shuffled[index % shuffled.count])
        }

        let spacing = -tile * 0.055
        let totalWidth = tile * CGFloat(count) + spacing * CGFloat(count - 1)
        let startOffset = CGFloat(generator.nextDouble(in: -0.28...0.04)) * tile

        return HStack(spacing: spacing) {
            ForEach(Array(sequence.enumerated()), id: \.offset) { index, url in
                let verticalJitter = CGFloat(generator.nextDouble(in: -0.045...0.045)) * tile
                let rotation = generator.nextDouble(in: -3.2...3.2)

                LazyArtwork(
                    url: url,
                    size: tile,
                    cornerRadius: tile * 0.10
                )
                .rotationEffect(.degrees(rotation))
                .offset(y: verticalJitter)
                .shadow(color: .black.opacity(0.24), radius: 7, y: 4)
                .zIndex(Double(index))
            }
        }
        .frame(width: totalWidth, height: tile, alignment: .center)
        .offset(x: startOffset)
        .modifier(
            MarqueeMotion(
                direction: direction,
                distance: tile * 2.4,
                duration: 18 + Double((stableSeed + row * 5) % 7)
            )
        )
        .frame(maxWidth: .infinity)
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


private struct PlaylistHeaderRandom {
    private var state: UInt64

    init(seed: Int) {
        let unsigned = UInt64(bitPattern: Int64(seed))
        state = unsigned == 0 ? 0x9E3779B97F4A7C15 : unsigned
    }

    mutating func nextUInt() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func nextDouble(in range: ClosedRange<Double>) -> Double {
        let value = Double(nextUInt() % 1_000_000) / 1_000_000.0
        return range.lowerBound + value * (range.upperBound - range.lowerBound)
    }

    mutating func shuffle<T>(_ array: inout [T]) {
        guard array.count > 1 else { return }
        for index in stride(from: array.count - 1, through: 1, by: -1) {
            let target = Int(nextUInt() % UInt64(index + 1))
            array.swapAt(index, target)
        }
    }
}
