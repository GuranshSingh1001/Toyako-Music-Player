import SwiftUI

/// Slow, continuously scrolling artwork collage used by playlist detail pages.
///
/// The layout is generated once from the playlist's track URLs, so SwiftUI body
/// updates do not reshuffle the artwork while the marquee is moving.
struct PlaylistArtworkMarquee: View {
    let tracks: [LocalTrack]
    let width: CGFloat
    let height: CGFloat
    let seed: Int

    private var artworkURLs: [URL] {
        var result: [URL] = []
        var seen = Set<URL>()

        for track in tracks {
            let url = track.url.standardizedFileURL
            if seen.insert(url).inserted {
                result.append(url)
            }
        }

        return result
    }

    private var tileSize: CGFloat {
        min(158, max(118, height * 0.36))
    }

    private var horizontalStep: CGFloat {
        tileSize * 0.90
    }

    private var verticalStep: CGFloat {
        tileSize * 0.78
    }

    private var segmentWidth: CGFloat {
        // Make the repeated segment wider than the viewport. The second copy
        // starts exactly where the first copy ends, so the loop is seamless.
        max(width * 1.35, horizontalStep * 11.0)
    }

    private var animationDuration: Double {
        // Deliberately slow: roughly 20–24 points/second on typical iPad widths.
        68.0 + Double(abs(seed) % 9)
    }

    var body: some View {
        ZStack {
            Color.black

            if artworkURLs.isEmpty {
                EmptyView()
            } else {
                HStack(spacing: 0) {
                    collageSegment(width: segmentWidth)
                    collageSegment(width: segmentWidth)
                }
                .frame(width: segmentWidth * 2, height: height)
                .modifier(PlaylistMarqueeMotion(
                    distance: segmentWidth,
                    duration: animationDuration
                ))
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .drawingGroup()
        .accessibilityHidden(true)
    }

    private func collageSegment(width: CGFloat) -> some View {
        let columns = Int(ceil(width / horizontalStep)) + 2
        let rows = max(3, Int(ceil(height / verticalStep)) + 1)

        var generator = PlaylistMarqueeRandom(seed: seed &* 31 &+ 0x4D2)
        var items: [ArtworkTile] = []
        items.reserveCapacity(columns * rows)

        for row in 0..<rows {
            // The alternating offsets create the loose, hand-arranged feel of
            // the reference instead of a rigid rectangular grid.
            let rowOffset: CGFloat
            switch row % 3 {
            case 0:
                rowOffset = -horizontalStep * 0.38
            case 1:
                rowOffset = horizontalStep * 0.18
            default:
                rowOffset = -horizontalStep * 0.12
            }

            let y = -tileSize * 0.48 + CGFloat(row) * verticalStep

            for column in 0..<columns {
                let x = -tileSize * 0.55 + rowOffset + CGFloat(column) * horizontalStep
                let artworkIndex = (row * columns + column) % artworkURLs.count

                items.append(
                    ArtworkTile(
                        url: artworkURLs[artworkIndex],
                        x: x,
                        y: y + CGFloat(generator.nextDouble(in: -7...7)),
                        rotation: generator.nextDouble(in: -7...7)
                    )
                )
            }
        }

        return ZStack {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                LazyArtwork(
                    url: item.url,
                    size: tileSize,
                    cornerRadius: tileSize * 0.07
                )
                .rotationEffect(.degrees(item.rotation))
                .position(x: item.x, y: item.y)
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }
}

private struct ArtworkTile {
    let url: URL
    let x: CGFloat
    let y: CGFloat
    let rotation: Double
}

private struct PlaylistMarqueeMotion: ViewModifier {
    let distance: CGFloat
    let duration: Double

    @State private var hasStarted = false

    func body(content: Content) -> some View {
        content
            .offset(x: hasStarted ? -distance : 0)
            .onAppear {
                guard !hasStarted else { return }
                withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                    hasStarted = true
                }
            }
    }
}

private struct PlaylistMarqueeRandom {
    private var state: UInt64

    init(seed: Int) {
        let value = UInt64(bitPattern: Int64(seed))
        state = value == 0 ? 0x9E3779B97F4A7C15 : value
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
}
