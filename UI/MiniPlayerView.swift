import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject var audioManager:
        AudioEngineManager

    let onOpenNowPlaying:
        () -> Void

    @State private var
        playPausePressed = false

    @State private var
        previousPressed = false

    @State private var
        nextPressed = false

    init(
        onOpenNowPlaying:
            @escaping () -> Void
    ) {
        self.onOpenNowPlaying =
            onOpenNowPlaying
    }

    var body: some View {
        HStack(spacing: 10) {

            // IMPORTANT:
            // Only this area opens Now Playing.
            // The playback controls below do not.
            Button {
                onOpenNowPlaying()
            } label: {
                HStack(
                    spacing: 10
                ) {
                    artwork

                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text(
                            audioManager
                                .currentTrack?
                                .title
                                ?? "Not Playing"
                        )
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )
                        .lineLimit(1)

                        Text(
                            audioManager
                                .currentTrack?
                                .artist
                                ?? "Unknown Artist"
                        )
                        .font(
                            .caption
                        )
                        .foregroundColor(
                            .secondary
                        )
                        .lineLimit(1)
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
            }
            .buttonStyle(
                .plain
            )

            // MARK: - Playback Controls

            Button {
                previousPressed = true

                audioManager.backward()

                DispatchQueue.main.asyncAfter(
                    deadline:
                        .now() + 0.14
                ) {
                    previousPressed = false
                }
            } label: {
                Image(
                    systemName:
                        "backward.fill"
                )
                .font(
                    .system(
                        size: 17,
                        weight: .semibold
                    )
                )
                .frame(
                    width: 34,
                    height: 44
                )
                .scaleEffect(
                    previousPressed
                        ? 0.78
                        : 1.0
                )
            }
            .buttonStyle(
                .plain
            )

            Button {
                playPausePressed = true

                audioManager
                    .togglePlayPause()

                DispatchQueue.main.asyncAfter(
                    deadline:
                        .now() + 0.14
                ) {
                    playPausePressed = false
                }
            } label: {
                Image(
                    systemName:
                        audioManager.isPlaying
                        ? "pause.fill"
                        : "play.fill"
                )
                .font(
                    .system(
                        size: 20,
                        weight: .medium
                    )
                )
                .frame(
                    width: 34,
                    height: 44
                )
                .scaleEffect(
                    playPausePressed
                        ? 0.76
                        : 1.0
                )
                .contentTransition(
                    .symbolEffect(
                        .replace
                    )
                )
            }
            .buttonStyle(
                .plain
            )

            Button {
                nextPressed = true

                audioManager.forward()

                DispatchQueue.main.asyncAfter(
                    deadline:
                        .now() + 0.14
                ) {
                    nextPressed = false
                }
            } label: {
                Image(
                    systemName:
                        "forward.fill"
                )
                .font(
                    .system(
                        size: 17,
                        weight: .semibold
                    )
                )
                .frame(
                    width: 34,
                    height: 44
                )
                .scaleEffect(
                    nextPressed
                        ? 0.78
                        : 1.0
                )
            }
            .buttonStyle(
                .plain
            )
        }
        .padding(
            .vertical,
            7
        )
        .padding(
            .leading,
            8
        )
        .padding(
            .trailing,
            5
        )
        .foregroundColor(
            .primary
        )
        .animation(
            .easeInOut(
                duration: 0.18
            ),
            value:
                audioManager
                    .currentTrack?
                    .id
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

                Image(
                    uiImage:
                        image
                )
                .resizable()
                .scaledToFill()
                .frame(
                    width: 44,
                    height: 44
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 8,
                        style: .continuous
                    )
                )
                .id(
                    track.id
                )
                .transition(
                    .opacity
                        .combined(
                            with:
                                .scale(
                                    scale: 0.9
                                )
                        )
                )

            } else {
                RoundedRectangle(
                    cornerRadius: 8,
                    style: .continuous
                )
                .fill(
                    Color.gray.opacity(
                        0.22
                    )
                )
                .frame(
                    width: 44,
                    height: 44
                )
                .overlay {
                    Image(
                        systemName:
                            "music.note"
                    )
                    .foregroundColor(
                        .secondary
                    )
                }
            }
        }
    }
}