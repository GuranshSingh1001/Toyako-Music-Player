import SwiftUI

/// Slow, ambient artwork field used behind playlist details.
///
/// The artwork is rendered as two identical, deterministic segments. A single
/// horizontal translation moves the complete field, which is considerably
/// cheaper than animating every cover independently.
struct PlaylistArtworkMarquee: View {
    let artworkURLs: [URL]
    let seed: Int

    @State private var isMoving = false

    private let animationDuration: Double = 72

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let height = max(proxy.size.height, 1)
            let tile = max(118, min(172, height * 0.36))
            let horizontalGap = max(10, tile * 0.07)
            let verticalGap = max(12, tile * 0.10)
            let stepX = tile + horizontalGap
            let segmentWidth = max(width + tile * 2, stepX * 11)

            ZStack {
                Color.black

                if !artworkURLs.isEmpty {
                    HStack(spacing: 0) {
                        segment(
                            width: segmentWidth,
                            height: height,
                            tile: tile,
                            stepX: stepX,
                            verticalGap: verticalGap
                        )

                        segment(
                            width: segmentWidth,
                            height: height,
                            tile: tile,
                            stepX: stepX,
                            verticalGap: verticalGap
                        )
                    }
                    .frame(width: segmentWidth * 2, height: height)
                    .offset(x: isMoving ? -segmentWidth : 0)
                    .onAppear {
                        guard !isMoving else { return }
                        withAnimation(.linear(duration: animationDuration).repeatForever(autoreverses: false)) {
                            isMoving = true
                        }
                    }
                }

                // Keep the playlist metadata readable without hiding the collage.
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.10), location: 0),
                        .init(color: .black.opacity(0.02), location: 0.38),
                        .init(color: .black.opacity(0.30), location: 0.72),
                        .init(color: .black.opacity(0.78), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: width, height: height)
            .clipped()
        }
    }

    private func segment(
        width: CGFloat,
        height: CGFloat,
        tile: CGFloat,
        stepX: CGFloat,
        verticalGap: CGFloat
    ) -> some View {
        let rowStep = tile + verticalGap
        let rowCenters = [
            -tile * 0.26,
            height * 0.48,
            height + tile * 0.18
        ]
        let columns = Int(ceil(width / stepX)) + 3

        let items = makeItems(
            columns: columns,
            rowCenters: rowCenters,
            tile: tile,
            stepX: stepX,
            rowStep: rowStep
        )

        return ZStack {
            ForEach(items) { item in
                LazyArtwork(
                    url: item.url,
                    size: tile,
                    cornerRadius: tile * 0.065
                )
                .rotationEffect(.degrees(item.rotation))
                .position(x: item.x, y: item.y)
                .shadow(color: .black.opacity(0.28), radius: 6, y: 3)
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }

    private func makeItems(
        columns: Int,
        rowCenters: [CGFloat],
        tile: CGFloat,
        stepX: CGFloat,
        rowStep: CGFloat
    ) -> [MarqueeArtworkItem] {
        var generator = SeededGenerator(seed: seed &* 31 &+ 0x4D595DF4)
        var items: [MarqueeArtworkItem] = []
        items.reserveCapacity(columns * rowCenters.count)

        for row in rowCenters.indices {
            // Alternating offsets prevent the artwork from reading as a grid.
            let rowOffset: CGFloat
            switch row {
            case 1: rowOffset = stepX * 0.34
            case 2: rowOffset = -stepX * 0.18
            default: rowOffset = 0
            }

            for column in 0..<columns {
                let artworkIndex = (row * columns + column) % artworkURLs.count
                let jitterY = CGFloat(generator.nextDouble(in: -tile * 0.10...tile * 0.10))
                let jitterX = CGFloat(generator.nextDouble(in: -tile * 0.07...tile * 0.07))
                let rotation = generator.nextDouble(in: -7.0...7.0)

                items.append(
                    MarqueeArtworkItem(
                        id: row * columns + column,
                        url: artworkURLs[artworkIndex],
                        x: -tile * 0.45 + rowOffset + CGFloat(column) * stepX + jitterX,
                        y: rowCenters[row] + jitterY,
                        rotation: rotation
                    )
                )
            }
        }

        return items
    }
}

private struct MarqueeArtworkItem: Identifiable {
    let id: Int
    let url: URL
    let x: CGFloat
    let y: CGFloat
    let rotation: Double
}

private struct SeededGenerator {
    private var state: UInt64

    init(seed: Int) {
        let value = UInt64(bitPattern: Int64(seed))
        state = value == 0 ? 0x9E3779B97F4A7C15 : value
    }

    private mutating func nextUInt() -> UInt64 {
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
