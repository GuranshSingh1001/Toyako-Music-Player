import SwiftUI

struct MiniPlayerView: View {

    @EnvironmentObject var audioManager: AudioEngineManager

    let onOpenNowPlaying: () -> Void

    var body: some View {

        Button(action: onOpenNowPlaying) {

            HStack(spacing: 12) {

                artwork

                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {

                    Text(
                        audioManager.currentTrack?.title
                        ?? "Not Playing"
                    )
                    .font(
                        .subheadline.weight(.semibold)
                    )
                    .lineLimit(1)

                    Text(
                        audioManager.currentTrack?.artist
                        ?? "Unknown Artist"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                    GeometryReader { proxy in

                        Capsule()
                            .fill(
                                .primary.opacity(0.11)
                            )
                            .overlay(
                                alignment: .leading
                            ) {

                                Capsule()
                                    .fill(
                                        .primary.opacity(0.52)
                                    )
                                    .frame(
                                        width:
                                            proxy.size.width *
                                            min(
                                                max(
                                                    audioManager.playbackProgress,
                                                    0
                                                ),
                                                1
                                            )
                                    )
                            }
                    }
                    .frame(height: 2.5)
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )

                MiniPlayerActivity(
                    isPlaying:
                        audioManager.isPlaying,

                    currentTime:
                        audioManager.currentTime,

                    audioBands:
                        audioManager.audioBands
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(
            .smooth(duration: 0.22),
            value:
                audioManager.currentTrack?.id
        )
    }

    private var artwork: some View {

        Group {

            if let track =
                audioManager.currentTrack,

               let data =
                track.artworkData,

               let image =
                UIImage(data: data) {

                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: 44,
                        height: 44
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 9,
                            style: .continuous
                        )
                    )
                    .id(track.id)
                    .transition(
                        .opacity.combined(
                            with:
                                .scale(
                                    scale: 0.94
                                )
                        )
                    )

            } else {

                RoundedRectangle(
                    cornerRadius: 9,
                    style: .continuous
                )
                .fill(
                    .secondary.opacity(0.16)
                )
                .frame(
                    width: 44,
                    height: 44
                )
                .overlay {

                    Image(
                        systemName: "music.note"
                    )
                    .foregroundStyle(
                        .secondary
                    )
                }
            }
        }
    }
}


// MARK: - Mini Player Frequency Waves

private struct MiniPlayerActivity: View {

    let isPlaying: Bool

    let currentTime:
        TimeInterval

    let audioBands:
        [Float]

    var body: some View {

        VStack(spacing: 5) {

            /*
             The important difference from the previous version:

             The bars are vertically CENTERED.

             Therefore:

                     █
                     █
                     █
                ─────█─────
                     █
                     █
                     █

             instead of:

                     █
                     █
                     █
                ───────────
            */

            HStack(
                alignment: .center,
                spacing: 2.5
            ) {

                ForEach(
                    0..<5,
                    id: \.self
                ) { index in

                    Capsule()
                        .fill(
                            .primary.opacity(
                                isPlaying
                                ? 0.72
                                : 0.30
                            )
                        )
                        .frame(
                            width: 2.5,
                            height:
                                barHeight(
                                    index
                                )
                        )
                        .animation(
                            .easeOut(
                                duration: 0.055
                            ),
                            value:
                                bandValue(index)
                        )
                }
            }
            .frame(
                width: 34,
                height: 20,
                alignment: .center
            )

            Text(timeString)
                .font(
                    .system(
                        size: 9,
                        weight: .medium,
                        design: .rounded
                    )
                )
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(width: 34)
    }


    // MARK: - Frequency Value

    private func bandValue(
        _ index: Int
    ) -> Float {

        guard
            audioBands.indices.contains(
                index
            )
        else {
            return 0
        }

        return min(
            max(
                audioBands[index],
                0
            ),
            1
        )
    }


    // MARK: - Bar Height

    private func barHeight(
        _ index: Int
    ) -> CGFloat {

        guard isPlaying else {

            return 3
        }

        let value =
            bandValue(index)

        /*
         Do NOT give the bars a large fixed minimum height.

         The quietest frequency should be allowed to
         almost disappear, while a strong frequency can
         occupy nearly the entire 20pt visual area.
        */

        let minimumHeight:
            Float = 2.0

        let maximumHeight:
            Float = 20.0

        let height =
            minimumHeight +
            (
                maximumHeight -
                minimumHeight
            ) * value

        return CGFloat(height)
    }


    // MARK: - Time

    private var timeString: String {

        let seconds =
            max(
                0,
                Int(
                    currentTime.rounded()
                )
            )

        return String(
            format: "%02d:%02d",
            seconds / 60,
            seconds % 60
        )
    }
}