import SwiftUI

struct PlaylistHeaderView: View {
    let playlist: Playlist
    let tracks: [LocalTrack]
    let onAddSongs: () -> Void

    @EnvironmentObject var audioManager: AudioEngineManager
    @State private var heroVisible = true

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
                ? min(410, max(360, width * 0.31))
                : min(360, max(310, width * 0.82))

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
            // The navigation zoom handles the page entrance. Avoid another
            // large hero animation competing with the scroll view on return.
        }
        .frame(height: 410)
    }

    private func marqueeArtwork(width: CGFloat, height: CGFloat) -> some View {
        // Build the artwork as one large, staggered collage rather than a normal
        // row/column grid. The collage is deliberately larger than the header and
        // the parent clips it, matching the dense Apple-Music-style treatment in
        // the reference design.
        let tile = min(148, max(118, height * 0.37))
        let horizontalStep = tile + 16
        let verticalStep = tile + 12
        let segmentWidth = max(width * 1.55, 1180)
        let duration = 46.0 + Double(stableSeed % 7)

        guard !artworkURLs.isEmpty else {
            return Color.black
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        return ZStack {
            Color.black

            HStack(spacing: 0) {
                collageSegment(
                    width: segmentWidth,
                    height: height,
                    tile: tile,
                    horizontalStep: horizontalStep,
                    verticalStep: verticalStep,
                    seedOffset: 0
                )

                // Exact duplicate of the first segment. Repeating the same
                // geometry makes the leftward marquee loop seamless instead of
                // snapping to a different collage at the reset point.
                collageSegment(
                    width: segmentWidth,
                    height: height,
                    tile: tile,
                    horizontalStep: horizontalStep,
                    verticalStep: verticalStep,
                    seedOffset: 0
                )
            }
            .frame(width: segmentWidth * 2, height: height)
            .modifier(
                CollageMarqueeMotion(
                    distance: segmentWidth,
                    duration: duration
                )
            )
        }
        .scaleEffect(1.08)
        .clipped()
        .overlay {
            // Very light edge shading keeps the artwork rich while leaving the
            // covers themselves clearly visible.
            LinearGradient(
                colors: [
                    .black.opacity(0.03),
                    .clear,
                    .black.opacity(0.05)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func collageSegment(
        width: CGFloat,
        height: CGFloat,
        tile: CGFloat,
        horizontalStep: CGFloat,
        verticalStep: CGFloat,
        seedOffset: Int
    ) -> some View {
        let columns = Int(ceil(width / horizontalStep)) + 4
        let rowStart = -1
        let rowEnd = 3
        var generator = PlaylistHeaderRandom(seed: stableSeed &+ seedOffset)

        var tiles: [(url: URL, x: CGFloat, y: CGFloat, rotation: Double, scale: CGFloat)] = []
        tiles.reserveCapacity(columns * (rowEnd - rowStart + 1))

        let baseX = -tile * 0.45
        let baseY = -tile * 0.55

        for row in rowStart...rowEnd {
            let stagger = row.isMultiple(of: 2) ? 0.0 : horizontalStep * 0.48
            let y = baseY + CGFloat(row + 1) * verticalStep
                + CGFloat(generator.nextDouble(in: -8...8))

            for column in 0..<columns {
                let x = baseX
                    + stagger
                    + CGFloat(column) * horizontalStep
                    + CGFloat(generator.nextDouble(in: -10...10))

                let index = tiles.count % artworkURLs.count
                let rotation = generator.nextDouble(in: -8.0...8.0)
                let scale = generator.nextDouble(in: 0.94...1.05)

                tiles.append((
                    url: artworkURLs[index],
                    x: x,
                    y: y,
                    rotation: rotation,
                    scale: scale
                ))
            }
        }

        return ZStack {
            ForEach(Array(tiles.indices), id: \.self) { index in
                let tileData = tiles[index]

                LazyArtwork(
                    url: tileData.url,
                    size: tile,
                    cornerRadius: tile * 0.085
                )
                .scaleEffect(tileData.scale)
                .rotationEffect(.degrees(tileData.rotation))
                .position(
                    x: tileData.x,
                    y: tileData.y
                )
                .shadow(color: .black.opacity(0.30), radius: 8, y: 5)
                .zIndex(Double(index))
            }
        }
        .frame(width: width, height: height)
        .clipped()
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

private struct CollageMarqueeMotion: ViewModifier {
    let distance: CGFloat
    let duration: Double
    @State private var moved = false

    func body(content: Content) -> some View {
        content
            .offset(x: moved ? -distance : 0)
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
