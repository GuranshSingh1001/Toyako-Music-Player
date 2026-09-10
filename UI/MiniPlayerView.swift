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

            // MARK: - Artwork + Track Information
            //
            // This area opens Now Playing.
            // Playback buttons below remain independent.

            Button {
                onOpenNowPlaying()
            } label: {
                HStack(spacing: 10) {
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
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                        .lineLimit(1)
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // MARK: - Previous

            Button {
                previousPressed = true

                audioManager.backward()

                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 0.14
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
                .animation(
                    .spring(
                        response: 0.28,
                        dampingFraction: 0.72
                    ),
                    value:
                        previousPressed
                )
            }
            .buttonStyle(.plain)

            // MARK: - Play / Pause

            Button {
                playPausePressed = true

                audioManager.togglePlayPause()

                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 0.14
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
                    .symbolEffect(.replace)
                )
                .animation(
                    .spring(
                        response: 0.28,
                        dampingFraction: 0.72
                    ),
                    value:
                        playPausePressed
                )
            }
            .buttonStyle(.plain)

            // MARK: - Next

            Button {
                nextPressed = true

                audioManager.forward()

                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 0.14
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
                .animation(
                    .spring(
                        response: 0.28,
                        dampingFraction: 0.72
                    ),
                    value:
                        nextPressed
                )
            }
            .buttonStyle(.plain)
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
        .foregroundStyle(.primary)

        // This makes the mini-player's complete
        // visual area a deliberate hit-test region.
        .contentShape(Rectangle())

        // IMPORTANT:
        // Use simultaneousGesture so the playback
        // buttons retain priority and don't accidentally
        // trigger Now Playing.
        .simultaneousGesture(
            TapGesture()
                .onEnded {
                    // The individual Button controls consume
                    // their own taps. A tap on the remaining
                    // mini-player surface opens Now Playing.
                    onOpenNowPlaying()
                }
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

    // MARK: - Artwork

    private var artwork: some View {
        Group {
            if let track =
                audioManager.currentTrack,
               let data =
                track.artworkData,
               let image =
                UIImage(data: data) {

                Image(
                    uiImage: image
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
                .id(track.id)
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
                    .foregroundStyle(
                        .secondary
                    )
                }
            }
        }
    }
}