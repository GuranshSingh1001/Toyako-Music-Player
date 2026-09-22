import SwiftUI
import UIKit

// MARK: - Artwork Bleeding Background
//
// This version does not use black as the base background.
// Instead, it builds the whole background from a small palette extracted
// from the artwork. The palette itself crossfades when the track changes.
//
// The blurred artwork is only a subtle texture layer. This prevents bright
// white areas in album art from turning the entire screen white.

struct ColorfulArtworkBleedBackground: View {
    let artworkData: Data?
    let accentColor: Color

    @State private var displayedArtworkData: Data?
    @State private var outgoingArtworkData: Data?

    @State private var displayedPalette = ArtworkBleedPalette.fallback
    @State private var outgoingPalette = ArtworkBleedPalette.fallback

    @State private var artworkTransition: Double = 1.0
    @State private var transitionGeneration = 0

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let width = geometry.size.width
                let height = geometry.size.height

                ZStack {
                    // MARK: Palette base
                    //
                    // There is intentionally NO Color.black underneath.
                    // The background is always derived from the artwork palette.

                    paletteBackground(
                        palette: outgoingPalette,
                        time: time,
                        width: width,
                        height: height
                    )
                    .opacity(1.0 - artworkTransition)

                    paletteBackground(
                        palette: displayedPalette,
                        time: time,
                        width: width,
                        height: height
                    )
                    .opacity(artworkTransition)

                    // MARK: Subtle artwork texture
                    //
                    // Keep this very restrained. The palette is responsible
                    // for the colour; the artwork only supplies texture.

                    if let outgoingArtworkData,
                       let image = UIImage(data: outgoingArtworkData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(
                                width: width * 1.18,
                                height: height * 1.18
                            )
                            .blur(radius: 95)
                            .saturation(1.15)
                            .brightness(-0.08)
                            .opacity((1.0 - artworkTransition) * 0.10)
                    }

                    if let displayedArtworkData,
                       let image = UIImage(data: displayedArtworkData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(
                                width: width * 1.18,
                                height: height * 1.18
                            )
                            .blur(radius: 95)
                            .saturation(1.15)
                            .brightness(-0.08)
                            .opacity(artworkTransition * 0.10)
                    }

                    // A very subtle centre wash improves lyric separation
                    // without bringing back the previous white/black fog.
                    RadialGradient(
                        colors: [
                            .white.opacity(0.045),
                            .clear,
                            .black.opacity(0.10)
                        ],
                        center: .center,
                        startRadius: min(width, height) * 0.05,
                        endRadius: max(width, height) * 0.78
                    )
                    .blendMode(.softLight)

                    // Gentle edge vignette. This is intentionally weak.
                    RadialGradient(
                        colors: [
                            .clear,
                            .clear,
                            .black.opacity(0.13)
                        ],
                        center: .center,
                        startRadius: min(width, height) * 0.38,
                        endRadius: max(width, height) * 0.88
                    )
                }
                .frame(width: width, height: height)
                .clipped()
                .drawingGroup()
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            let palette = ArtworkBleedPalette.extract(from: artworkData)
            displayedArtworkData = artworkData
            displayedPalette = palette
            outgoingPalette = palette
        }
        .onChange(of: artworkData?.hashValue, initial: false) { _, _ in
            changeArtwork(to: artworkData)
        }
    }

    // MARK: - Palette Background

    @ViewBuilder
    private func paletteBackground(
        palette: ArtworkBleedPalette,
        time: TimeInterval,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        let t = time

        let driftX =
            sin(t * 0.00019) * width * 0.11
            + cos(t * 0.00011) * width * 0.06

        let driftY =
            cos(t * 0.00016) * height * 0.10
            + sin(t * 0.00009) * height * 0.05

        ZStack {
            // Main full-screen colour field.
            LinearGradient(
                stops: [
                    .init(color: palette.dark, location: 0.00),
                    .init(color: palette.primary, location: 0.28),
                    .init(color: palette.secondary, location: 0.57),
                    .init(color: palette.deep, location: 1.00)
                ],
                startPoint: UnitPoint(
                    x: 0.05 + sin(t * 0.00007) * 0.10,
                    y: 0.05
                ),
                endPoint: UnitPoint(
                    x: 0.95,
                    y: 0.95 + cos(t * 0.00006) * 0.08
                )
            )

            // Large moving colour pools.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            palette.primary.opacity(0.95),
                            palette.primary.opacity(0.42),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: max(width, height) * 0.48
                    )
                )
                .frame(
                    width: max(width, height) * 0.90,
                    height: max(width, height) * 0.90
                )
                .offset(
                    x: -width * 0.20 + driftX,
                    y: -height * 0.10 + driftY
                )
                .blur(radius: 28)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            palette.secondary.opacity(0.82),
                            palette.secondary.opacity(0.30),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: max(width, height) * 0.52
                    )
                )
                .frame(
                    width: max(width, height) * 0.95,
                    height: max(width, height) * 0.95
                )
                .offset(
                    x: width * 0.28 - driftX * 0.72,
                    y: height * 0.13 - driftY * 0.60
                )
                .blur(radius: 34)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            palette.deep.opacity(0.75),
                            palette.deep.opacity(0.24),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: max(width, height) * 0.46
                    )
                )
                .frame(
                    width: max(width, height) * 0.85,
                    height: max(width, height) * 0.85
                )
                .offset(
                    x: width * 0.02 + driftX * 0.55,
                    y: height * 0.35 + driftY * 0.80
                )
                .blur(radius: 42)
        }
    }

    // MARK: - Artwork Transition

    private func changeArtwork(to newArtworkData: Data?) {
        let oldHash = displayedArtworkData?.hashValue
        let newHash = newArtworkData?.hashValue

        guard oldHash != newHash else { return }

        transitionGeneration += 1
        let generation = transitionGeneration

        // Preserve both the old artwork and its colours while the new
        // palette enters. This makes the entire background transition,
        // rather than only the texture layer.
        outgoingArtworkData = displayedArtworkData
        outgoingPalette = displayedPalette

        displayedArtworkData = newArtworkData
        displayedPalette = ArtworkBleedPalette.extract(from: newArtworkData)

        artworkTransition = 0

        withAnimation(
            .easeInOut(duration: 1.15)
        ) {
            artworkTransition = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
            guard generation == transitionGeneration else { return }
            outgoingArtworkData = nil
            outgoingPalette = displayedPalette
        }
    }
}

// MARK: - Artwork Palette

private struct ArtworkBleedPalette {
    let primary: Color
    let secondary: Color
    let deep: Color
    let dark: Color

    static let fallback = ArtworkBleedPalette(
        primary: Color(red: 0.28, green: 0.34, blue: 0.45),
        secondary: Color(red: 0.20, green: 0.25, blue: 0.34),
        deep: Color(red: 0.10, green: 0.13, blue: 0.19),
        dark: Color(red: 0.07, green: 0.09, blue: 0.13)
    )

    static func extract(from data: Data?) -> ArtworkBleedPalette {
        guard
            let data,
            let image = UIImage(data: data),
            let cgImage = image.cgImage
        else {
            return fallback
        }

        let sampleSize = 32
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = sampleSize * bytesPerPixel
        let bitsPerComponent = 8

        var pixels = [UInt8](
            repeating: 0,
            count: sampleSize * sampleSize * bytesPerPixel
        )

        guard let context = CGContext(
            data: &pixels,
            width: sampleSize,
            height: sampleSize,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return fallback
        }

        context.interpolationQuality = .low
        context.draw(
            cgImage,
            in: CGRect(
                x: 0,
                y: 0,
                width: sampleSize,
                height: sampleSize
            )
        )

        struct Sample {
            let r: Double
            let g: Double
            let b: Double
            let saturation: Double
            let luminance: Double
        }

        var samples: [Sample] = []
        samples.reserveCapacity(sampleSize * sampleSize)

        for y in 0..<sampleSize {
            for x in 0..<sampleSize {
                let index = (y * sampleSize + x) * 4

                let r = Double(pixels[index]) / 255.0
                let g = Double(pixels[index + 1]) / 255.0
                let b = Double(pixels[index + 2]) / 255.0

                let maxValue = max(r, g, b)
                let minValue = min(r, g, b)
                let chroma = maxValue - minValue

                let luminance =
                    0.2126 * r +
                    0.7152 * g +
                    0.0722 * b

                let saturation =
                    maxValue > 0
                    ? chroma / maxValue
                    : 0

                // Very white and very black pixels are poor bleed colours.
                // They are still allowed at low saturation so monochrome
                // artwork does not collapse into a single colour.
                let usable =
                    (luminance < 0.94 && luminance > 0.035)
                    || saturation > 0.48

                if usable {
                    samples.append(
                        Sample(
                            r: r,
                            g: g,
                            b: b,
                            saturation: saturation,
                            luminance: luminance
                        )
                    )
                }
            }
        }

        guard !samples.isEmpty else {
            return fallback
        }

        // Prefer colours that are visibly chromatic without completely
        // ignoring the overall artwork brightness.
        let sorted = samples.sorted { a, b in
            let scoreA =
                a.saturation * 0.78 +
                min(a.luminance, 0.72) * 0.22

            let scoreB =
                b.saturation * 0.78 +
                min(b.luminance, 0.72) * 0.22

            return scoreA > scoreB
        }

        var selected: [Sample] = []

        for candidate in sorted {
            let isDifferent = selected.allSatisfy { existing in
                let distance =
                    abs(candidate.r - existing.r) +
                    abs(candidate.g - existing.g) +
                    abs(candidate.b - existing.b)

                return distance > 0.32
            }

            if isDifferent {
                selected.append(candidate)
            }

            if selected.count == 5 {
                break
            }
        }

        if selected.isEmpty {
            return fallback
        }

        let average = selected.reduce(
            (r: 0.0, g: 0.0, b: 0.0)
        ) { partial, sample in
            (
                partial.r + sample.r,
                partial.g + sample.g,
                partial.b + sample.b
            )
        }

        let count = Double(selected.count)

        let averageColor = RGBColor(
            r: average.r / count,
            g: average.g / count,
            b: average.b / count
        )

        let primary = selected[0]
        let secondary =
            selected.count > 1
            ? selected[1]
            : selected[0]

        let primaryColor = RGBColor(
            r: primary.r,
            g: primary.g,
            b: primary.b
        )

        let secondaryColor = RGBColor(
            r: secondary.r,
            g: secondary.g,
            b: secondary.b
        )

        return ArtworkBleedPalette(
            primary: primaryColor.boostedColor(
                saturation: 1.12,
                brightness: 0.98
            ),
            secondary: secondaryColor.boostedColor(
                saturation: 1.08,
                brightness: 0.94
            ),
            deep: averageColor.boostedColor(
                saturation: 1.00,
                brightness: 0.56
            ),
            dark: averageColor.boostedColor(
                saturation: 0.92,
                brightness: 0.34
            )
        )
    }
}

// MARK: - RGB Helpers

private struct RGBColor {
    let r: Double
    let g: Double
    let b: Double

    func boostedColor(
        saturation saturationMultiplier: Double,
        brightness brightnessMultiplier: Double
    ) -> Color {
        let maxValue = max(r, g, b)
        let minValue = min(r, g, b)

        guard maxValue > 0.0001 else {
            return Color(
                red: 0.05,
                green: 0.05,
                blue: 0.05
            )
        }

        let originalSaturation =
            (maxValue - minValue) / maxValue

        let targetSaturation = min(
            originalSaturation * saturationMultiplier,
            1.0
        )

        let luminance =
            0.2126 * r +
            0.7152 * g +
            0.0722 * b

        let targetBrightness = min(
            max(luminance * brightnessMultiplier, 0.035),
            0.82
        )

        let hue = RGBColor.hue(
            r: r,
            g: g,
            b: b
        )

        return Color(
            hue: hue,
            saturation: targetSaturation,
            brightness: targetBrightness
        )
    }

    private static func hue(
        r: Double,
        g: Double,
        b: Double
    ) -> Double {
        let maxValue = max(r, g, b)
        let minValue = min(r, g, b)
        let delta = maxValue - minValue

        guard delta > 0.0001 else {
            return 0
        }

        var hue: Double

        if maxValue == r {
            hue = (g - b) / delta
        } else if maxValue == g {
            hue = 2.0 + (b - r) / delta
        } else {
            hue = 4.0 + (r - g) / delta
        }

        hue /= 6.0

        if hue < 0 {
            hue += 1.0
        }

        return hue
    }
}
