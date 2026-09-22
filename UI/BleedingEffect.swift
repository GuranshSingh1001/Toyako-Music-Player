import SwiftUI
import UIKit

// MARK: - Artwork Bleeding Background
//
// A soft, layered "liquid glass" bleed inspired by modern music players.
// The album artwork is never displayed as a recognizable background image.
// Instead, several oversized, highly blurred copies of the artwork slowly
// drift independently. A dark color wash prevents bright artwork (especially
// white covers) from turning the whole screen into a white haze.

struct ColorfulArtworkBleedBackground: View {
    let artworkData: Data?
    let accentColor: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                if let artworkData,
                   let image = UIImage(data: artworkData) {

                    AnimatedArtworkLayer(
                        image: image,
                        size: geometry.size,
                        phase: 0.0,
                        speed: 0.030,
                        scale: 1.55,
                        blur: 95,
                        opacity: 0.82,
                        movement: 42
                    )

                    AnimatedArtworkLayer(
                        image: image,
                        size: geometry.size,
                        phase: 2.15,
                        speed: 0.021,
                        scale: 1.85,
                        blur: 135,
                        opacity: 0.54,
                        movement: 92
                    )
                    .blendMode(.screen)

                    AnimatedArtworkLayer(
                        image: image,
                        size: geometry.size,
                        phase: 4.45,
                        speed: 0.016,
                        scale: 2.15,
                        blur: 175,
                        opacity: 0.38,
                        movement: 145
                    )
                    .blendMode(.plusLighter)

                    // A broad tint keeps the artwork palette present even when
                    // the source cover contains large neutral/white regions.
                    RadialGradient(
                        colors: [
                            accentColor.opacity(0.34),
                            accentColor.opacity(0.12),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: max(geometry.size.width, geometry.size.height) * 0.78
                    )
                    .blendMode(.screen)

                    // Darken the centre and edges slightly. This is important
                    // for covers with white backgrounds or white clothing.
                    LinearGradient(
                        colors: [
                            .black.opacity(0.18),
                            .clear,
                            .black.opacity(0.30)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    RadialGradient(
                        colors: [
                            .clear,
                            .black.opacity(0.16)
                        ],
                        center: .center,
                        startRadius: min(geometry.size.width, geometry.size.height) * 0.18,
                        endRadius: max(geometry.size.width, geometry.size.height) * 0.78
                    )
                } else {
                    LinearGradient(
                        colors: [
                            .black,
                            Color(white: 0.045),
                            .black
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.7), value: artworkData?.hashValue)
    }
}

// MARK: - Animated Artwork Layer

private struct AnimatedArtworkLayer: View {
    let image: UIImage
    let size: CGSize
    let phase: Double
    let speed: Double
    let scale: CGFloat
    let blur: CGFloat
    let opacity: Double
    let movement: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let t = time * speed + phase

            let x =
                sin(t * 0.73) * movement +
                sin(t * 0.31 + 1.2) * movement * 0.35 +
                cos(t * 0.17 + 2.6) * movement * 0.18

            let y =
                cos(t * 0.59 + 0.7) * movement * 0.72 +
                sin(t * 0.27 + 2.4) * movement * 0.38 +
                cos(t * 0.13 + 4.0) * movement * 0.20

            let breathing =
                1.0 +
                sin(t * 0.22 + phase) * 0.045 +
                cos(t * 0.11 + phase * 0.7) * 0.018

            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(
                    width: size.width * 1.72,
                    height: size.height * 1.72
                )
                .scaleEffect(scale * breathing)
                .offset(x: x, y: y)
                .saturation(2.25)
                .contrast(1.22)
                .brightness(-0.07)
                .blur(radius: blur, opaque: true)
                .opacity(opacity)
                .frame(width: size.width, height: size.height)
                .clipped()
        }
    }
}
