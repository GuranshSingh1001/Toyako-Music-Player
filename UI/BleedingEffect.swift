import SwiftUI
import UIKit

// MARK: - Album Artwork Bleeding Background
//
// Cloudy artwork bleed with smooth track transitions.
//
// Important:
// • Keeps the soft, cloudy blob appearance of the original version.
// • The background is derived from the artwork palette instead of pure black.
// • Track changes interpolate the palette itself, rather than crossfading two
//   complete bright backgrounds. This prevents the "flash-bang" effect.
// • White/near-white artwork pixels are excluded from the dominant palette.
// • The artwork texture remains very subtle.

struct ColorfulArtworkBleedBackground: View {
    let artworkData: Data?
    let accentColor: Color

    @AppStorage(ToyakoPreferences.bleedingEffectKey) private var bleedingEffect = true

    @State private var currentPalette = ArtworkBleedPalette.fallback
    @State private var targetPalette = ArtworkBleedPalette.fallback
    @State private var transitionProgress: CGFloat = 1.0
    @State private var transitionID = 0

    var body: some View {
        GeometryReader { geometry in
            if !bleedingEffect {
                Color.black
                    .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let size = geometry.size

                // Interpolate the colours themselves.
                //
                // We do NOT stack the old and new cloudy fields. This is what
                // prevents bright artwork from causing a transition flash.
                let palette = ArtworkBleedPalette.interpolate(
                    from: currentPalette,
                    to: targetPalette,
                    progress: transitionProgress
                )

                ZStack {
                    // Artwork-derived dark base.
                    palette.baseColor

                    animatedColorField(
                        colors: palette.colors.map(\.swiftColor),
                        time: time,
                        size: size
                    )

                    // Very faint artwork texture. The cloudy palette remains
                    // the main visual effect.
                    if let artworkData,
                       let image = UIImage(data: artworkData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(
                                width: size.width * 1.35,
                                height: size.height * 1.35
                            )
                            .saturation(1.25)
                            .brightness(-0.28)
                            .opacity(0.045)
                            .blur(radius: 105)
                            .scaleEffect(1.06)
                    }

                    // Gentle centre/edge treatment. No white wash.
                    RadialGradient(
                        colors: [
                            Color.black.opacity(0.015),
                            Color.black.opacity(0.08),
                            Color.black.opacity(0.26)
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
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .task(id: artworkData?.hashValue) {
            let newPalette = await Task.detached(priority: .userInitiated) {
                ArtworkBleedPalette.extract(from: artworkData)
            }.value

            updatePalette(to: newPalette)
        }
    }

    // MARK: - Cloudy Colour Field

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

                let x =
                    sin(time * speed + phase) * size.width * 0.34 +
                    cos(time * speed * 0.61 + phase * 1.7)
                    * size.width * 0.14

                let y =
                    cos(time * speed * 0.82 + phase) * size.height * 0.30 +
                    sin(time * speed * 0.47 + phase * 0.8)
                    * size.height * 0.15

                let blobWidth =
                    size.width * (0.72 + CGFloat(index % 3) * 0.10)

                let blobHeight =
                    size.height * (0.62 + CGFloat((index + 1) % 3) * 0.09)

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
                .frame(
                    width: blobWidth,
                    height: blobHeight
                )
                .offset(x: x, y: y)
                .blur(radius: 28)
            }
        }
        .saturation(1.18)
    }

    // MARK: - Palette Transition

    private func updatePalette(to newPalette: ArtworkBleedPalette) {
        // Ignore duplicate artwork updates.
        guard newPalette != targetPalette else { return }

        transitionID += 1
        let id = transitionID

        // If another transition is already running, begin from the exact
        // palette currently visible on screen rather than jumping back to
        // the previous track.
        let visiblePalette = ArtworkBleedPalette.interpolate(
            from: currentPalette,
            to: targetPalette,
            progress: transitionProgress
        )

        currentPalette = visiblePalette
        targetPalette = newPalette
        transitionProgress = 0

        withAnimation(
            .easeInOut(duration: 1.10)
        ) {
            transitionProgress = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.16) {
            guard id == transitionID else { return }

            currentPalette = targetPalette
            transitionProgress = 1.0
        }
    }
}

// MARK: - Artwork Palette

private struct ArtworkBleedPalette: Equatable {
    struct PaletteColor: Equatable {
        let r: Double
        let g: Double
        let b: Double

        var swiftColor: Color {
            Color(
                red: r,
                green: g,
                blue: b
            )
        }

        var uiColor: UIColor {
            UIColor(
                red: r,
                green: g,
                blue: b,
                alpha: 1
            )
        }
    }

    let colors: [PaletteColor]
    let baseColor: Color

    static let fallback = ArtworkBleedPalette(
        colors: [
            PaletteColor(r: 0.20, g: 0.25, b: 0.34),
            PaletteColor(r: 0.16, g: 0.22, b: 0.30),
            PaletteColor(r: 0.13, g: 0.18, b: 0.25),
            PaletteColor(r: 0.11, g: 0.15, b: 0.21),
            PaletteColor(r: 0.09, g: 0.13, b: 0.18),
            PaletteColor(r: 0.075, g: 0.10, b: 0.15)
        ],
        baseColor: Color(
            red: 0.055,
            green: 0.065,
            blue: 0.085
        )
    )

    // Keep all palettes the same length so each cloudy blob has a matching
    // colour during a track transition.
    static func interpolate(
        from: ArtworkBleedPalette,
        to: ArtworkBleedPalette,
        progress: CGFloat
    ) -> ArtworkBleedPalette {
        let p = min(max(Double(progress), 0), 1)

        let source = normalizedColors(from.colors, count: 6)
        let destination = normalizedColors(to.colors, count: 6)

        let colors = zip(source, destination).map { a, b in
            PaletteColor(
                r: a.r + (b.r - a.r) * p,
                g: a.g + (b.g - a.g) * p,
                b: a.b + (b.b - a.b) * p
            )
        }

        let baseA = from.baseRGB
        let baseB = to.baseRGB

        let base = PaletteColor(
            r: baseA.r + (baseB.r - baseA.r) * p,
            g: baseA.g + (baseB.g - baseA.g) * p,
            b: baseA.b + (baseB.b - baseA.b) * p
        )

        return ArtworkBleedPalette(
            colors: colors,
            baseColor: base.swiftColor
        )
    }

    private var baseRGB: PaletteColor {
        let ui = UIColor(baseColor)

        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        if ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return PaletteColor(
                r: Double(r),
                g: Double(g),
                b: Double(b)
            )
        }

        return PaletteColor(
            r: 0.055,
            g: 0.065,
            b: 0.085
        )
    }

    private static func normalizedColors(
        _ colors: [PaletteColor],
        count: Int
    ) -> [PaletteColor] {
        guard !colors.isEmpty else {
            return Array(
                repeating: PaletteColor(r: 0.12, g: 0.16, b: 0.22),
                count: count
            )
        }

        if colors.count >= count {
            return Array(colors.prefix(count))
        }

        var result = colors

        while result.count < count {
            result.append(result[result.count % colors.count])
        }

        return result
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
            return fallback
        }

        context.interpolationQuality = .low
        context.draw(
            cgImage,
            in: CGRect(
                x: 0,
                y: 0,
                width: targetSize,
                height: targetSize
            )
        )

        guard
            let buffer = context.data?.assumingMemoryBound(to: UInt8.self)
        else {
            return fallback
        }

        struct Sample {
            let r: CGFloat
            let g: CGFloat
            let b: CGFloat
            let weight: CGFloat
        }

        var samples: [Sample] = []
        samples.reserveCapacity(targetSize * targetSize)

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

                // Exclude the white parts which caused the flash-bang.
                // Keep a little more mid-tone range than the previous version
                // so the cloudy effect still has enough colour information.
                guard brightness < 0.88 else { continue }
                guard brightness > 0.045 else { continue }
                guard spread > 0.045 else { continue }

                let weight =
                    0.65 + min(spread * 2.2, 0.90)

                samples.append(
                    Sample(
                        r: r,
                        g: g,
                        b: b,
                        weight: weight
                    )
                )
            }
        }

        guard !samples.isEmpty else {
            return fallback
        }

        // Quantize colours into coarse buckets, just like the original
        // implementation. This keeps the palette varied and cloudy.
        var buckets: [
            Int: (
                r: CGFloat,
                g: CGFloat,
                b: CGFloat,
                weight: CGFloat
            )
        ] = [:]

        for sample in samples {
            let qr = Int(sample.r * 5)
            let qg = Int(sample.g * 5)
            let qb = Int(sample.b * 5)

            let key = qr * 36 + qg * 6 + qb

            if let existing = buckets[key] {
                buckets[key] = (
                    existing.r + sample.r * sample.weight,
                    existing.g + sample.g * sample.weight,
                    existing.b + sample.b * sample.weight,
                    existing.weight + sample.weight
                )
            } else {
                buckets[key] = (
                    sample.r * sample.weight,
                    sample.g * sample.weight,
                    sample.b * sample.weight,
                    sample.weight
                )
            }
        }

        let ranked = buckets.values
            .sorted { $0.weight > $1.weight }
            .prefix(8)

        var extracted: [PaletteColor] = []

        for bucket in ranked {
            let r = bucket.r / bucket.weight
            let g = bucket.g / bucket.weight
            let b = bucket.b / bucket.weight

            // Limit the luminance of extracted colours. This keeps the
            // original cloudy look without turning the screen neon.
            let controlled = controlColor(
                r: r,
                g: g,
                b: b
            )

            extracted.append(controlled)
        }

        guard !extracted.isEmpty else {
            return fallback
        }

        let normalized = normalizedColors(
            extracted,
            count: 6
        )

        // Build the base from the darker average of the extracted palette.
        // This is no longer pure black, so the "black underneath" disappears.
        let average = normalized.reduce(
            (r: 0.0, g: 0.0, b: 0.0)
        ) { result, color in
            (
                result.r + color.r,
                result.g + color.g,
                result.b + color.b
            )
        }

        let count = Double(normalized.count)

        let base = PaletteColor(
            r: max((average.r / count) * 0.42, 0.035),
            g: max((average.g / count) * 0.42, 0.040),
            b: max((average.b / count) * 0.42, 0.045)
        )

        return ArtworkBleedPalette(
            colors: normalized,
            baseColor: base.swiftColor
        )
    }

    private static func controlColor(
        r: CGFloat,
        g: CGFloat,
        b: CGFloat
    ) -> PaletteColor {
        let maxValue = max(r, max(g, b))
        let minValue = min(r, min(g, b))
        let spread = maxValue - minValue

        let luminance =
            0.2126 * r +
            0.7152 * g +
            0.0722 * b

        // Keep the colour's hue/saturation, but pull very bright colours
        // down before they enter the cloudy field.
        let brightnessScale: CGFloat

        if luminance > 0.68 {
            brightnessScale = 0.68 / luminance
        } else {
            brightnessScale = 0.92
        }

        let saturationBoost: CGFloat =
            spread > 0.20 ? 1.04 : 0.96

        let centreR = (r - luminance) * saturationBoost + luminance
        let centreG = (g - luminance) * saturationBoost + luminance
        let centreB = (b - luminance) * saturationBoost + luminance

        return PaletteColor(
            r: Double(min(max(centreR * brightnessScale, 0.035), 0.72)),
            g: Double(min(max(centreG * brightnessScale, 0.035), 0.72)),
            b: Double(min(max(centreB * brightnessScale, 0.035), 0.72))
        )
    }
}

// MARK: - Shared page artwork bleed

struct ArtworkBleedPageBackground: View {
    let artworkURL: URL?

    @AppStorage(ToyakoPreferences.bleedingEffectKey) private var bleedingEffect = true
    @State private var artworkData: Data?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black

                if bleedingEffect {

                if let artworkData, let image = UIImage(data: artworkData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: proxy.size.width * 1.18,
                            height: proxy.size.height * 1.18
                        )
                        .blur(radius: 72)
                        .saturation(1.18)
                        .opacity(0.22)
                        .scaleEffect(1.08)

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: proxy.size.width * 1.04,
                            height: proxy.size.height * 1.04
                        )
                        .blur(radius: 115)
                        .saturation(1.05)
                        .opacity(0.13)
                }

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.52),
                        Color.black.opacity(0.30),
                        Color.black.opacity(0.62)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                RadialGradient(
                    colors: [
                        Color.black.opacity(0.08),
                        Color.black.opacity(0.34)
                    ],
                    center: .center,
                    startRadius: 80,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.78
                )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .task(id: artworkURL) {
            guard let artworkURL else {
                artworkData = nil
                return
            }

            let loaded = await ArtworkStore.shared.data(for: artworkURL)
            guard !Task.isCancelled else { return }
            artworkData = loaded
        }
    }
}
