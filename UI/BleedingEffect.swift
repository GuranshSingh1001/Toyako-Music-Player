import SwiftUI
import UIKit

// MARK: - Album Artwork Bleeding Background
//
// The background is intentionally built from the artwork's COLOR PALETTE rather
// than a heavily blurred copy of the artwork itself. This prevents white areas
// in album covers from producing the large white bloom that can wash out lyrics.

struct ColorfulArtworkBleedBackground: View {
    let artworkData: Data?
    let accentColor: Color

    @State private var palette: [Color] = []

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let size = geometry.size

                ZStack {
                    // Keep a dark base so the bleed never becomes a white sheet.
                    Color(red: 0.055, green: 0.055, blue: 0.065)

                    if !palette.isEmpty {
                        animatedColorField(
                            colors: palette,
                            time: time,
                            size: size
                        )
                    } else {
                        accentColor
                            .opacity(0.22)
                            .blur(radius: 100)
                    }

                    // A very faint blurred artwork texture gives the background
                    // some connection to the cover without allowing white pixels
                    // to dominate it.
                    if let artworkData,
                       let image = UIImage(data: artworkData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(
                                width: size.width * 1.35,
                                height: size.height * 1.35
                            )
                            .saturation(1.35)
                            .brightness(-0.20)
                            .opacity(0.065)
                            .blur(radius: 95)
                            .scaleEffect(1.06)
                    }

                    // Gentle centre wash for lyric readability. This is much
                    // weaker than the previous white bloom.
                    RadialGradient(
                        colors: [
                            Color.black.opacity(0.02),
                            Color.black.opacity(0.10),
                            Color.black.opacity(0.28)
                        ],
                        center: .center,
                        startRadius: min(size.width, size.height) * 0.10,
                        endRadius: max(size.width, size.height) * 0.82
                    )
                }
                .frame(width: size.width, height: size.height)
                .clipped()
                .drawingGroup()
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .task(id: artworkData) {
            palette = await Task.detached(priority: .userInitiated) {
                ArtworkBleedPalette.extract(from: artworkData)
            }.value
        }
    }

    @ViewBuilder
    private func animatedColorField(
        colors: [Color],
        time: TimeInterval,
        size: CGSize
    ) -> some View {
        let count = min(colors.count, 6)

        ZStack {
            ForEach(0..<count, id: \.self) { index in
                let phase = Double(index) * 1.73
                let speed = 0.055 + Double(index % 3) * 0.012

                let x = sin(time * speed + phase) * size.width * 0.34
                    + cos(time * speed * 0.61 + phase * 1.7) * size.width * 0.14

                let y = cos(time * speed * 0.82 + phase) * size.height * 0.30
                    + sin(time * speed * 0.47 + phase * 0.8) * size.height * 0.15

                let blobWidth = size.width * (0.72 + CGFloat(index % 3) * 0.10)
                let blobHeight = size.height * (0.62 + CGFloat((index + 1) % 3) * 0.09)

                RadialGradient(
                    colors: [
                        colors[index].opacity(0.72),
                        colors[index].opacity(0.40),
                        colors[index].opacity(0.0)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: max(blobWidth, blobHeight) * 0.56
                )
                .frame(width: blobWidth, height: blobHeight)
                .offset(x: x, y: y)
                .blur(radius: 28)
            }
        }
        .saturation(1.18)
    }
}

// MARK: - Palette Extraction

private enum ArtworkBleedPalette {
    static func extract(from data: Data?) -> [Color] {
        guard let data,
              let image = UIImage(data: data),
              let cgImage = image.cgImage else {
            return []
        }

        let targetSize = 28
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = targetSize * bytesPerPixel
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: targetSize,
            height: targetSize,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return []
        }

        context.interpolationQuality = .low
        context.draw(
            cgImage,
            in: CGRect(x: 0, y: 0, width: targetSize, height: targetSize)
        )

        guard let buffer = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return []
        }

        struct Sample {
            let color: UIColor
            let weight: CGFloat
        }

        var samples: [Sample] = []

        for y in 0..<targetSize {
            for x in 0..<targetSize {
                let offset = (y * targetSize + x) * bytesPerPixel
                let r = CGFloat(buffer[offset]) / 255
                let g = CGFloat(buffer[offset + 1]) / 255
                let b = CGFloat(buffer[offset + 2]) / 255
                let a = CGFloat(buffer[offset + 3]) / 255

                guard a > 0.15 else { continue }

                let maxValue = max(r, max(g, b))
                let minValue = min(r, min(g, b))
                let brightness = (maxValue + minValue) * 0.5
                let spread = maxValue - minValue

                // White, near-white and very dark pixels are deliberately
                // excluded. They are the main cause of the previous bloom.
                guard brightness < 0.88, brightness > 0.055 else { continue }
                guard spread > 0.045 else { continue }

                // More saturated pixels get slightly more influence.
                let weight = 0.65 + min(spread * 2.2, 0.9)
                samples.append(
                    Sample(
                        color: UIColor(red: r, green: g, blue: b, alpha: 1),
                        weight: weight
                    )
                )
            }
        }

        guard !samples.isEmpty else { return [] }

        // Quantize colours into coarse buckets and retain the most represented
        // saturated regions of the artwork.
        var buckets: [Int: (r: CGFloat, g: CGFloat, b: CGFloat, weight: CGFloat)] = [:]

        for sample in samples {
            var r: CGFloat = 0
            var g: CGFloat = 0
            var b: CGFloat = 0
            var a: CGFloat = 0
            sample.color.getRed(&r, green: &g, blue: &b, alpha: &a)

            let qr = Int(r * 5)
            let qg = Int(g * 5)
            let qb = Int(b * 5)
            let key = qr * 36 + qg * 6 + qb

            if let existing = buckets[key] {
                buckets[key] = (
                    existing.r + r * sample.weight,
                    existing.g + g * sample.weight,
                    existing.b + b * sample.weight,
                    existing.weight + sample.weight
                )
            } else {
                buckets[key] = (
                    r * sample.weight,
                    g * sample.weight,
                    b * sample.weight,
                    sample.weight
                )
            }
        }

        let ranked = buckets.values
            .sorted { $0.weight > $1.weight }
            .prefix(8)

        var result: [Color] = []

        for bucket in ranked {
            let r = bucket.r / bucket.weight
            let g = bucket.g / bucket.weight
            let b = bucket.b / bucket.weight

            result.append(
                Color(
                    red: Double(r),
                    green: Double(g),
                    blue: Double(b)
                )
            )
        }

        return result
    }
}
