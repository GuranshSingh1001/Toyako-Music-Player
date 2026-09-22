import SwiftUI
import UIKit

// MARK: - Artwork Bleeding Effect
//
// The background is deliberately cross-faded when the artwork changes.
// The old palette remains visible while the new palette fades in, so
// switching tracks feels like a continuous transition instead of a hard cut.

struct ColorfulArtworkBleedBackground: View {
    let artworkData: Data?
    let accentColor: Color

    @State private var displayedArtworkData: Data?
    @State private var outgoingArtworkData: Data?
    @State private var artworkTransition: Double = 1.0
    @State private var transitionGeneration = 0

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let width = geometry.size.width
                let height = geometry.size.height

                ZStack {
                    Color.black

                    // Previous artwork stays underneath during a track change.
                    if let outgoingArtworkData,
                       let image = UIImage(data: outgoingArtworkData) {
                        artworkPaletteField(
                            image: image,
                            time: time,
                            width: width,
                            height: height,
                            phase: -0.35,
                            speed: 0.055,
                            scale: 1.30,
                            blur: 72,
                            opacity: (1.0 - artworkTransition) * 0.88,
                            movement: 52
                        )
                        .transition(.opacity)
                    }

                    // New artwork fades in over the old artwork instead of
                    // replacing it immediately.
                    if let displayedArtworkData,
                       let image = UIImage(data: displayedArtworkData) {
                        artworkPaletteField(
                            image: image,
                            time: time,
                            width: width,
                            height: height,
                            phase: 0,
                            speed: 0.055,
                            scale: 1.30,
                            blur: 72,
                            opacity: artworkTransition * 0.88,
                            movement: 52
                        )

                        artworkPaletteField(
                            image: image,
                            time: time,
                            width: width,
                            height: height,
                            phase: 2.7,
                            speed: 0.032,
                            scale: 1.55,
                            blur: 115,
                            opacity: artworkTransition * 0.42,
                            movement: 105
                        )
                    }

                    accentColor
                        .opacity(0.055)
                        .blendMode(.screen)

                    // Keeps lyrics readable without producing the large white
                    // bloom that the previous implementation created.
                    RadialGradient(
                        colors: [
                            .clear,
                            .black.opacity(0.035),
                            .black.opacity(0.17)
                        ],
                        center: .center,
                        startRadius: min(width, height) * 0.18,
                        endRadius: max(width, height) * 0.82
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
            displayedArtworkData = artworkData
        }
        .onChange(of: artworkData?.hashValue, initial: false) { _, _ in
            changeArtwork(to: artworkData)
        }
    }

    // MARK: - Track Artwork Transition

    private func changeArtwork(to newArtworkData: Data?) {
        let oldHash = displayedArtworkData?.hashValue
        let newHash = newArtworkData?.hashValue

        guard oldHash != newHash else { return }

        transitionGeneration += 1
        let generation = transitionGeneration

        // Keep the currently visible artwork alive underneath the incoming one.
        outgoingArtworkData = displayedArtworkData
        displayedArtworkData = newArtworkData
        artworkTransition = 0

        // A slightly longer crossfade gives the artwork's colours time to
        // blend naturally instead of producing a visible snap.
        withAnimation(.easeInOut(duration: 1.15)) {
            artworkTransition = 1.0
        }

        // Remove the outgoing layer only after the crossfade has completed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard generation == transitionGeneration else { return }
            outgoingArtworkData = nil
        }
    }

    // MARK: - Animated Palette Field

    @ViewBuilder
    private func artworkPaletteField(
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
