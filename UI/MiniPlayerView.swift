import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject var audioManager: AudioEngineManager

    @State private var playPausePressed = false
    @State private var nextPressed = false
    @State private var previousPressed = false

    var body: some View {
        HStack(spacing: 12) {

            // MARK: Artwork

            if let track = audioManager.currentTrack,
               let data = track.artworkData,
               let uiImage = UIImage(data: data) {

                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(
                        contentMode: .fill
                    )
                    .frame(
                        width: 44,
                        height: 44
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 8
                        )
                    )
                    .shadow(
                        color: .black.opacity(0.2),
                        radius: 4,
                        y: 2
                    )
                    .id(track.id)
                    .transition(
                        .opacity
                        .combined(
                            with: .scale(scale: 0.92)
                        )
                    )

            } else {
                RoundedRectangle(
                    cornerRadius: 8
                )
                .fill(
                    Color.gray.opacity(0.3)
                )
                .frame(
                    width: 44,
                    height: 44
                )
                .overlay {
                    Image(
                        systemName: "music.note"
                    )
                    .foregroundColor(
                        .white.opacity(0.8)
                    )
                }
            }

            // MARK: Track Information

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(
                    audioManager.currentTrack?.title
                    ?? "Not Playing"
                )
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)

                Text(
                    audioManager.currentTrack?.artist
                    ?? "Unknown Artist"
                )
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )

            Spacer(minLength: 0)

            // MARK: Controls

            HStack(spacing: 18) {

                Button {
                    previousPressed = true

                    audioManager.backward()

                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + 0.16
                    ) {
                        previousPressed = false
                    }
                } label: {
                    Image(
                        systemName: "backward.fill"
                    )
                    .font(
                        .system(
                            size: 17,
                            weight: .semibold
                        )
                    )
                    .scaleEffect(
                        previousPressed
                            ? 0.75
                            : 1.0
                    )
                }

                Button {
                    playPausePressed = true

                    audioManager.togglePlayPause()

                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + 0.16
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
                            size: 21,
                            weight: .medium
                        )
                    )
                    .frame(
                        width: 30,
                        height: 30
                    )
                    .scaleEffect(
                        playPausePressed
                            ? 0.72
                            : 1.0
                    )
                    .contentTransition(
                        .symbolEffect(.replace)
                    )
                }

                Button {
                    nextPressed = true

                    audioManager.forward()

                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + 0.16
                    ) {
                        nextPressed = false
                    }
                } label: {
                    Image(
                        systemName: "forward.fill"
                    )
                    .font(
                        .system(
                            size: 17,
                            weight: .semibold
                        )
                    )
                    .scaleEffect(
                        nextPressed
                            ? 0.75
                            : 1.0
                    )
                }
            }
            .foregroundColor(.primary)
            .padding(.trailing, 8)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .animation(
            .easeInOut(duration: 0.2),
            value: audioManager.currentTrack?.id
        )
    }
}