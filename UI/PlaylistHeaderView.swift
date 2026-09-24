import SwiftUI

struct PlaylistHeaderView: View {
    let playlist: Playlist
    let tracks: [LocalTrack]
    let onAddSongs: () -> Void

    @EnvironmentObject var audioManager: AudioEngineManager
    @State private var heroVisible = true

    private var artworkURLs: [URL] {
        guard !tracks.isEmpty else { return [] }

        // Use each track artwork once before repeating anything. This keeps the
        // visible collage varied instead of producing obvious repeated patterns.
        var urls = tracks.map(\.url)
        var generator = PlaylistHeaderRandom(seed: stableSeed)
        generator.shuffle(&urls)

        let minimumCount = 72
        if urls.count < minimumCount {
            let original = urls
            var index = 0
            while urls.count < minimumCount {
                urls.append(original[index % original.count])
                index += 1
            }
        }

        return urls
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
                ? min(460, max(430, width * 0.33))
                : min(390, max(350, width * 0.82))

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
        .frame(height: wideFrameHeight)
    }

    private var wideFrameHeight: CGFloat {
        476
    }

    @ViewBuilder
    private func marqueeArtwork(width: CGFloat, height: CGFloat) -> some View {
        let tile = min(188, max(156, height * 0.39))
        let gap: CGFloat = min(24, max(16, tile * 0.10))
        let step = tile + gap
        let rowGap: CGFloat = min(24, max(14, tile * 0.09))
        let segmentWidth = max(width * 1.30, step * 9.0)
        let duration = 44.0 + Double(stableSeed % 7)

        if artworkURLs.isEmpty {
            Color.black
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack {
                Color.black

                // One oversized canvas contains every cover. Moving this single
                // canvas means every cover travels left at exactly the same speed.
                HStack(spacing: 0) {
                    playlistCollageSegment(
                        width: segmentWidth,
                        height: height,
                        tile: tile,
                        step: step,
                        rowGap: rowGap
                    )

                    // An exact copy makes the marquee loop without a visual jump.
                    playlistCollageSegment(
                        width: segmentWidth,
                        height: height,
                        tile: tile,
                        step: step,
                        rowGap: rowGap
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
        }
    }

    private func playlistCollageSegment(
        width: CGFloat,
        height: CGFloat,
        tile: CGFloat,
        step: CGFloat,
        rowGap: CGFloat
    ) -> some View {
        let columns = Int(ceil(width / step)) + 3
        let rowHeight = tile + rowGap
        let top = -tile * 0.48
        let middle = top + rowHeight
        let bottom = middle + rowHeight
        let rowCenters = [top, middle, bottom]

        var generator = PlaylistHeaderRandom(seed: stableSeed &* 31 &+ 17)
        var items: [(url: URL, x: CGFloat, y: CGFloat, rotation: Double)] = []
        items.reserveCapacity(columns * rowCenters.count)

        for row in 0..<rowCenters.count {
            // Stagger the rows like the sketch, but keep their vertical spacing
            // stable so the result reads as a collage rather than a grid.
            let rowOffset = row == 1 ? step * 0.42 : (row == 2 ? step * -0.20 : 0)

            for column in 0..<columns {
                let index = items.count % artworkURLs.count
                let x = -tile * 0.52 + rowOffset + CGFloat(column) * step
                let y = rowCenters[row] + CGFloat(generator.nextDouble(in: -8...8))
                let rotation = generator.nextDouble(in: -8.0...8.0)

                items.append((
                    url: artworkURLs[index],
                    x: x,
                    y: y,
                    rotation: rotation
                ))
            }
        }

        return ZStack {
            ForEach(Array(items.indices), id: \.self) { index in
                let item = items[index]

                LazyArtwork(
                    url: item.url,
                    size: tile,
                    cornerRadius: tile * 0.085
                )
                .rotationEffect(.degrees(item.rotation))
                .position(x: item.x, y: item.y)
                .shadow(color: .black.opacity(0.32), radius: 7, y: 4)
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
