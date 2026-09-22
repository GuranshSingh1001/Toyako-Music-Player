import SwiftUI
import UIKit

// MARK: - Artwork Bleeding Background
//
// Full-screen artwork-colour background with:
// • No pure-black base layer
// • No additive crossfade (prevents flash-bang transitions)
// • Controlled luminance so white artwork cannot wash out the UI
// • Controlled saturation so red artwork cannot become neon red
// • Smooth 1.15s palette transition between tracks
// • Subtle moving colour pools
// • Very subtle artwork texture

struct ColorfulArtworkBleedBackground: View {
    let artworkData: Data?
    let accentColor: Color

    @State private var currentPalette = ArtworkBleedPalette.fallback
    @State private var targetPalette = ArtworkBleedPalette.fallback

    @State private var currentArtworkData: Data?
    @State private var targetArtworkData: Data?

    @State private var transitionProgress: CGFloat = 1.0
    @State private var transitionGeneration = 0

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate

                // Interpolate ONE background instead of stacking two
                // backgrounds. This is the important fix for the flash-bang.
                let palette = ArtworkBleedPalette.interpolate(
                    from: currentPalette,
                    to: targetPalette,
                    progress: transitionProgress
                )

                ZStack {
                    paletteBackground(
                        palette: palette,
                        time: time,
                        size: geometry.size
                    )

                    // Artwork texture is also crossfaded, but kept extremely
                    // subtle so bright artwork cannot dominate the background.
                    if let image = UIImage(data: currentArtworkData ?? Data()) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(
                                width: geometry.size.width * 1.18,
                                height: geometry.size.height * 1.18
                            )
                            .blur(radius: 105)
                            .saturation(1.08)
                            .brightness(-0.20)
                            .opacity(0.055 * (1.0 - transitionProgress))
                    }

                    if let image = UIImage(data: targetArtworkData ?? Data()) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(
                                width: geometry.size.width * 1.18,
                                height: geometry.size.height * 1.18
                            )
                            .blur(radius: 105)
                            .saturation(1.08)
                            .brightness(-0.20)
                            .opacity(0.055 * transitionProgress)
                    }

                    // Keep the centre readable without introducing a white
                    // overlay. This is neutral and extremely subtle.
                    RadialGradient(
                        colors: [
                            .white.opacity(0.025),
                            .clear,
                            .black.opacity(0.10)
                        ],
                        center: .center,
                        startRadius: min(geometry.size.width, geometry.size.height) * 0.05,
                        endRadius: max(geometry.size.width, geometry.size.height) * 0.82
                    )
                    .blendMode(.softLight)

                    // Soft edge falloff.
                    RadialGradient(
                        colors: [
                            .clear,
                            .clear,
                            .black.opacity(0.12)
                        ],
                        center: .center,
                        startRadius: min(geometry.size.width, geometry.size.height) * 0.40,
                        endRadius: max(geometry.size.width, geometry.size.height) * 0.90
                    )
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .drawingGroup()
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            let palette = ArtworkBleedPalette.extract(from: artworkData)

            currentPalette = palette
            targetPalette = palette

            currentArtworkData = artworkData
            targetArtworkData = artworkData

            transitionProgress = 1.0
        }
        .onChange(of: artworkData?.hashValue, initial: false) { _, _ in
            changeArtwork(to: artworkData)
        }
    }

    // MARK: - Background

    @ViewBuilder
    private func paletteBackground(
        palette: ArtworkBleedPalette,
        time: TimeInterval,
        size: CGSize
    ) -> some View {
        let width = size.width
        let height = size.height

        let driftX =
            sin(time * 0.00019) * width * 0.10 +
            cos(time * 0.00011) * width * 0.055

        let driftY =
            cos(time * 0.00016) * height * 0.09 +
            sin(time * 0.00009) * height * 0.045

        ZStack {
            // The base itself is an artwork-derived colour.
            LinearGradient(
                colors: [
                    palette.dark,
                    palette.deep,
                    palette.dark
                ],
                startPoint: UnitPoint(
                    x: 0.02 + sin(time * 0.00007) * 0.08,
                    y: 0.02
                ),
                endPoint: UnitPoint(
                    x: 0.98,
                    y: 0.98 + cos(time * 0.00006) * 0.06
                )
            )

            // Primary colour pool.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            palette.primary.opacity(0.82),
                            palette.primary.opacity(0.38),
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
                .blur(radius: 32)

            // Secondary colour pool.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            palette.secondary.opacity(0.70),
                            palette.secondary.opacity(0.30),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: max(width, height) * 0.50
                    )
                )
                .frame(
                    width: max(width, height) * 0.92,
                    height: max(width, height) * 0.92
                )
                .offset(
                    x: width * 0.28 - driftX * 0.70,
                    y: height * 0.12 - driftY * 0.60
                )
                .blur(radius: 38)

            // Deep colour pool.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            palette.deep.opacity(0.70),
                            palette.deep.opacity(0.25),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: max(width, height) * 0.46
                    )
                )
                .frame(
                    width: max(width, height) * 0.84,
                    height: max(width, height) * 0.84
                )
                .offset(
                    x: width * 0.02 + driftX * 0.50,
                    y: height * 0.34 + driftY * 0.75
                )
                .blur(radius: 44)
        }
    }

    // MARK: - Track Change

    private func changeArtwork(to newArtworkData: Data?) {
        guard newArtworkData?.hashValue != targetArtworkData?.hashValue else {
            return
        }

        transitionGeneration += 1
        let generation = transitionGeneration

        // Freeze the currently displayed/interpolated palette as the new
        // starting point. This makes rapid track changes smooth too.
        let startingPalette = ArtworkBleedPalette.interpolate(
            from: currentPalette,
            to: targetPalette,
            progress: transitionProgress
        )

        currentPalette = startingPalette
        targetPalette = ArtworkBleedPalette.extract(from: newArtworkData)

        currentArtworkData = targetArtworkData
        targetArtworkData = newArtworkData

        transitionProgress = 0

        withAnimation(.easeInOut(duration: 1.15)) {
            transitionProgress = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.22) {
            guard generation == transitionGeneration else { return }

            currentPalette = targetPalette
            currentArtworkData = targetArtworkData
        }
    }
}

// MARK: - Palette

private struct ArtworkBleedPalette {
    let primary: Color
    let secondary: Color
    let deep: Color
    let dark: Color

    static let fallback = ArtworkBleedPalette(
        primary: Color(red: 0.20, green: 0.27, blue: 0.38),
        secondary: Color(red: 0.15, green: 0.21, blue: 0.30),
        deep: Color(red: 0.10, green: 0.14, blue: 0.21),
        dark: Color(red: 0.075, green: 0.10, blue: 0.15)
    )

    static func interpolate(
        from a: ArtworkBleedPalette,
        to b: ArtworkBleedPalette,
        progress: CGFloat
    ) -> ArtworkBleedPalette {
        let p = min(max(Double(progress), 0), 1)

        return ArtworkBleedPalette(
            primary: blend(a.primary, b.primary, p),
            secondary: blend(a.secondary, b.secondary, p),
            deep: blend(a.deep, b.deep, p),
            dark: blend(a.dark, b.dark, p)
        )
    }

    private static func blend(
        _ a: Color,
        _ b: Color,
        _ progress: Double
    ) -> Color {
        let ca = UIColor(a)
        let cb = UIColor(b)

        var ar: CGFloat = 0
        var ag: CGFloat = 0
        var ab: CGFloat = 0
        var aa: CGFloat = 0

        var br: CGFloat = 0
        var bg: CGFloat = 0
        var bb: CGFloat = 0
        var ba: CGFloat = 0

        ca.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        cb.getRed(&br, green: &bg, blue: &bb, alpha: &ba)

        return Color(
            red: Double(ar + (br - ar) * CGFloat(progress)),
            green: Double(ag + (bg - ag) * CGFloat(progress)),
            blue: Double(ab + (bb - ab) * CGFloat(progress)),
            opacity: Double(aa + (ba - aa) * CGFloat(progress))
        )
    }

    // MARK: Extraction

    static func extract(from data: Data?) -> ArtworkBleedPalette {
        guard
            let data,
            let image = UIImage(data: data),
            let cgImage = image.cgImage
        else {
            return fallback
        }

        let sampleSize = 32
        let bytesPerPixel = 4
        let bytesPerRow = sampleSize * bytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        var pixels = [UInt8](
            repeating: 0,
            count: sampleSize * sampleSize * bytesPerPixel
        )

        guard let context = CGContext(
            data: &pixels,
            width: sampleSize,
            height: sampleSize,
            bitsPerComponent: 8,
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
                let i = (y * sampleSize + x) * 4

                let r = Double(pixels[i]) / 255.0
                let g = Double(pixels[i + 1]) / 255.0
                let b = Double(pixels[i + 2]) / 255.0

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

                // Critical fix:
                // Ignore very bright low-saturation pixels.
                //
                // This prevents white album artwork from producing a
                // white background during the transition.
                let usable =
                    luminance >= 0.045 &&
                    luminance <= 0.76 &&
                    (
                        saturation >= 0.12 ||
                        luminance <= 0.48
                    )

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

        // Strongly favour colour while avoiding neon extremes.
        let ranked = samples.sorted { a, b in
            let scoreA =
                a.saturation * 0.72 +
                min(a.luminance, 0.62) * 0.28

            let scoreB =
                b.saturation * 0.72 +
                min(b.luminance, 0.62) * 0.28

            return scoreA > scoreB
        }

        var selected: [Sample] = []

        for candidate in ranked {
            let sufficientlyDifferent = selected.allSatisfy { existing in
                let distance =
                    abs(candidate.r - existing.r) +
                    abs(candidate.g - existing.g) +
                    abs(candidate.b - existing.b)

                return distance > 0.26
            }

            if sufficientlyDifferent {
                selected.append(candidate)
            }

            if selected.count >= 5 {
                break
            }
        }

        if selected.isEmpty {
            return fallback
        }

        let average = selected.reduce(
            (r: 0.0, g: 0.0, b: 0.0)
        ) { result, sample in
            (
                result.r + sample.r,
                result.g + sample.g,
                result.b + sample.b
            )
        }

        let count = Double(selected.count)

        let averageRGB = RGBColor(
            r: average.r / count,
            g: average.g / count,
            b: average.b / count
        )

        let primarySample = selected[0]
        let secondarySample =
            selected.count > 1
            ? selected[1]
            : selected[0]

        let primaryRGB = RGBColor(
            r: primarySample.r,
            g: primarySample.g,
            b: primarySample.b
        )

        let secondaryRGB = RGBColor(
            r: secondarySample.r,
            g: secondarySample.g,
            b: secondarySample.b
        )

        return ArtworkBleedPalette(
            primary: primaryRGB.backgroundColor(
                saturationMultiplier: 0.88,
                brightness: 0.48
            ),
            secondary: secondaryRGB.backgroundColor(
                saturationMultiplier: 0.84,
                brightness: 0.40
            ),
            deep: averageRGB.backgroundColor(
                saturationMultiplier: 0.82,
                brightness: 0.27
            ),
            dark: averageRGB.backgroundColor(
                saturationMultiplier: 0.72,
                brightness: 0.16
            )
        )
    }
}

// MARK: - RGB Helpers

private struct RGBColor {
    let r: Double
    let g: Double
    let b: Double

    func backgroundColor(
        saturationMultiplier: Double,
        brightness targetBrightness: Double
    ) -> Color {
        let maxValue = max(r, g, b)
        let minValue = min(r, g, b)

        guard maxValue > 0.0001 else {
            return Color(
                red: targetBrightness,
                green: targetBrightness,
                blue: targetBrightness
            )
        }

        let originalSaturation =
            (maxValue - minValue) / maxValue

        let saturation = min(
            max(originalSaturation * saturationMultiplier, 0.05),
            0.82
        )

        let hue = Self.hue(r: r, g: g, b: b)

        // The background is deliberately capped.
        // This is what prevents the KICK BACK screenshot from becoming
        // an almost pure #FF0000 screen.
        let brightness = min(
            max(targetBrightness, 0.045),
            0.50
        )

        return Color(
            hue: hue,
            saturation: saturation,
            brightness: brightness
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

        var h: Double

        if maxValue == r {
            h = (g - b) / delta
        } else if maxValue == g {
            h = 2.0 + (b - r) / delta
        } else {
            h = 4.0 + (r - g) / delta
        }

        h /= 6.0

        if h < 0 {
            h += 1
        }

        return h
    }
}
