import SwiftUI

// MARK: - LiveKit-Style Audio Visualizer

/// A five-bar audio visualizer inspired by LiveKit's
/// AgentAudioVisualizerBar.
///
/// The bars are vertically centered, so they grow equally
/// above and below the center line.
struct AudioVisualizer: View {

    let bands: [Float]
    let isPlaying: Bool

    // MARK: Appearance

    private let barCount = 5
    private let barWidth: CGFloat = 3.0
    private let spacing: CGFloat = 3.0

    /// Minimum visible height while audio is playing.
    private let minimumHeight: CGFloat = 3.0

    /// Maximum height of a single bar.
    private let maximumHeight: CGFloat = 20.0

    var body: some View {
        HStack(
            alignment: .center,
            spacing: spacing
        ) {
            ForEach(0..<barCount, id: \.self) { index in

                let level = levelForBar(index)

                Capsule()
                    .frame(
                        width: barWidth,
                        height: barHeight(for: level)
                    )
                    .animation(
                        .easeOut(duration: 0.10),
                        value: level
                    )
            }
        }
        .frame(
            height: maximumHeight,
            alignment: .center
        )
        .opacity(isPlaying ? 1.0 : 0.55)
    }

    // MARK: - Level

    private func levelForBar(_ index: Int) -> CGFloat {

        guard index < bands.count else {
            return 0
        }

        let value = bands[index]

        guard value.isFinite else {
            return 0
        }

        return CGFloat(
            min(
                max(value, 0),
                1
            )
        )
    }

    // MARK: - Bar Height

    private func barHeight(for level: CGFloat) -> CGFloat {

        guard isPlaying else {
            return minimumHeight
        }

        let height =
            minimumHeight +
            (maximumHeight - minimumHeight) * level

        return min(
            max(height, minimumHeight),
            maximumHeight
        )
    }
}


// MARK: - Preview

#Preview {
    AudioVisualizer(
        bands: [0.25, 0.65, 0.95, 0.55, 0.30],
        isPlaying: true
    )
}