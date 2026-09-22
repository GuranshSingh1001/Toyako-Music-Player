import SwiftUI
import UIKit

// MARK: - Artwork Bleeding Effect
//
// The complete album-artwork bleed effect lives in this file so NowPlayingView
// only has to compose the view. The artwork itself is never shown sharply;
// only heavily blurred colour information is used for the background.

struct ColorfulArtworkBleedBackground: View {
    let artworkData: Data?
    let accentColor: Color

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let width = geometry.size.width
                let height = geometry.size.height

                ZStack {
                    Color.black

                    if let artworkData,
                       let image = UIImage(data: artworkData) {

                        // Primary artwork field. This carries most of the
                        // visible colour and keeps the artwork's palette
                        // recognizable while remaining heavily blurred.
                        artworkColorField(
                            image: image,
                            time: time,
                            width: width,
                            height: height,
                            phase: 0,
                            speed: 0.055,
                            scale: 1.30,
                            blur: 72,
                            opacity: 0.88,
                            movement: 52
                        )

                        // Secondary field adds depth and slow colour movement
                        // without turning the background into a flat gradient.
                        artworkColorField(
                            image: image,
                            time: time,
                            width: width,
                            height: height,
                            phase: 2.7,
                            speed: 0.032,
                            scale: 1.55,
                            blur: 115,
                            opacity: 0.42,
                            movement: 105
                        )

                        // Keep the existing artwork tint as a subtle supporting
                        // colour instead of allowing it to wash over the image.
                        accentColor
                            .opacity(0.07)
                            .blendMode(.screen)

                        // A restrained vignette keeps the lyric area readable
                        // without destroying the artwork's saturation.
                        RadialGradient(
                            colors: [
                                .clear,
                                .black.opacity(0.06),
                                .black.opacity(0.18)
                            ],
                            center: .center,
                            startRadius: min(width, height) * 0.18,
                            endRadius: max(width, height) * 0.82
                        )
                    } else {
                        LinearGradient(
                            colors: [
                                .black,
                                Color(white: 0.055),
                                .black
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
                .frame(width: width, height: height)
                .clipped()
                .drawingGroup()
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(
            .easeInOut(duration: 0.8),
            value: artworkData?.hashValue
        )
    }

    @ViewBuilder
    private func artworkColorField(
        image: UIImage,
        time: TimeInterval,
        width: CGFloat,
        height: CGFloat,
        phase: Double,
        speed: Double,
        scale: CGFloat,
        blur: CGFloat,
        opacity: Double,
        movement: CGFloat
    ) -> some View {
        let t = time * speed + phase

        let x =
            sin(t * 0.72) * movement
            + cos(t * 0.41 + 1.7) * movement * 0.42
            + sin(t * 0.19 + 3.0) * movement * 0.22

        let y =
            cos(t * 0.61 + 0.8) * movement * 0.72
            + sin(t * 0.37 + 2.2) * movement * 0.44
            + cos(t * 0.17 + 4.4) * movement * 0.20

        let breathing =
            1.0
            + sin(t * 0.21 + phase) * 0.035
            + cos(t * 0.13 + 1.4) * 0.018

        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(
                width: width * 1.55,
                height: height * 1.55
            )
            .scaleEffect(
                scale * breathing,
                anchor: .center
            )
            .offset(
                x: CGFloat(x),
                y: CGFloat(y)
            )
            .blur(radius: blur, opaque: true)
            .saturation(2.0)
            .contrast(1.16)
            .brightness(-0.015)
            .opacity(opacity)
    }
}
