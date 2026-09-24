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
                : min(400, max(340, width * 0.50))

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
        .frame(height: 400)
    }

    private func marqueeArtwork(width: CGFloat, height: CGFloat) -> some View {
        // The artwork is intentionally built as one oversized rectangular sheet:
        // several rows of individually tilted square covers with real gaps between
        // them. The sheet is larger than the header and the header clips its edges.
        let tile = min(168, max(126, height * 0.42))
        let horizontalSpacing = min(18, max(11, tile * 0.085))
        let verticalSpacing = min(20, max(12, tile * 0.10))
        let rowHeight = tile + verticalSpacing
        let rowCount = 4

        return ZStack {
            Color.black

            VStack(spacing: verticalSpacing) {
                ForEach(0..<rowCount, id: \.self) { row in
                    marqueeRow(
                        tile: tile,
                        row: row,
                        width: width,
                        spacing: horizontalSpacing
                    )
                    .frame(height: tile)
                }
            }
            .frame(
                width: width + tile * 2,
                height: rowHeight * CGFloat(rowCount),
                alignment: .leading
            )
            .offset(y: -tile * 0.62)
            .rotationEffect(.degrees(-1.15))
            .scaleEffect(1.06)
        }
        .overlay {
            LinearGradient(
                colors: [
                    .black.opacity(0.02),
                    .clear,
                    .black.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func marqueeRow(
        tile: CGFloat,
        row: Int,
        width: CGFloat,
        spacing: CGFloat
    ) -> some View {
        var generator = PlaylistHeaderRandom(seed: stableSeed &+ row * 7919)

        // A segment contains enough covers to extend well beyond both edges.
        // Two extra copies make the leftward animation wrap without a blank edge.
        let baseCount = max(7, Int(ceil((width + tile * 2) / (tile + spacing))) + 1)
        let segmentWidth = tile * CGFloat(baseCount) + spacing * CGFloat(baseCount - 1)

        var shuffled = artworkURLs
        generator.shuffle(&shuffled)

        var rotations: [Double] = []
        var verticalOffsets: [CGFloat] = []
        rotations.reserveCapacity(baseCount)
        verticalOffsets.reserveCapacity(baseCount)

        for index in 0..<baseCount {
            // Strong enough to be visibly tilted, but not so strong that the
            // covers look chaotic.
            let baseRotation = generator.nextDouble(in: -7.0...7.0)
            let alternatingBias = row.isMultiple(of: 2) ? 0.8 : -0.8
            rotations.append(baseRotation + alternatingBias)
            verticalOffsets.append(
                CGFloat(generator.nextDouble(in: -0.045...0.045)) * tile
            )
            _ = index
        }

        let startOffset = CGFloat(generator.nextDouble(in: -0.45...0.05)) * tile
        let verticalJitter = CGFloat(generator.nextDouble(in: -0.025...0.025)) * tile
        let duration = 41.0 + Double((stableSeed + row * 13) % 8)

        return HStack(spacing: spacing) {
            // Three identical segments are rendered, but only one segment is
            // travelled per animation cycle. This gives a continuous marquee.
            ForEach(0..<(baseCount * 3), id: \.self) { index in
                let baseIndex = index % baseCount
                let url = shuffled[baseIndex % shuffled.count]

                LazyArtwork(
                    url: url,
                    size: tile,
                    cornerRadius: tile * 0.095
                )
                .rotationEffect(.degrees(rotations[baseIndex]))
                .offset(y: verticalOffsets[baseIndex])
                .shadow(color: .black.opacity(0.32), radius: 8, y: 4)
                .zIndex(Double(baseCount * 3 - index))
            }
        }
        .frame(width: segmentWidth * 3, height: tile, alignment: .leading)
        .offset(x: startOffset)
        .modifier(
            MarqueeMotion(
                distance: segmentWidth,
                duration: duration
            )
        )
        .offset(y: verticalJitter)
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
