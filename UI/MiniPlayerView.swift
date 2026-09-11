import SwiftUI
import UIKit

struct MiniPlayerView: View {
    @EnvironmentObject var audioManager: AudioEngineManager
    let onOpenNowPlaying: () -> Void

    private var progress: Double {
        guard
            let duration = audioManager.currentTrack?.duration,
            duration.isFinite,
            duration > 0,
            audioManager.currentTime.isFinite
        else {
            return 0
        }

        return min(
            max(audioManager.currentTime / duration, 0),
            1
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpenNowPlaying) {
                HStack(spacing: 10) {
                    artwork

                    VStack(alignment: .leading, spacing: 2) {
                        Text(audioManager.currentTrack?.title ?? "Not Playing")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)

                        Text(audioManager.currentTrack?.artist ?? "Unknown Artist")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(.primary.opacity(0.11))

                                Capsule()
                                    .fill(.primary.opacity(0.52))
                                    .frame(width: proxy.size.width * progress)
                            }
                            // Playback position is a live value. It must never
                            // inherit a layout animation from the surrounding view.
                            .transaction { transaction in
                                transaction.animation = nil
                            }
                        }
                        .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 0) {
                Button {
                    audioManager.backward()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    audioManager.togglePlayPause()
                } label: {
                    Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 34, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    audioManager.forward()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.primary)
            .disabled(audioManager.currentTrack == nil)
            .opacity(audioManager.currentTrack == nil ? 0.45 : 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        // Only animate actual control/content changes. Do not animate the
        // high-frequency playback time/progress updates.
        .animation(.smooth(duration: 0.20), value: audioManager.currentTrack?.id)
        .animation(.smooth(duration: 0.14), value: audioManager.isPlaying)
    }

    @ViewBuilder
    private var artwork: some View {
        if let track = audioManager.currentTrack,
           let data = track.artworkData,
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .id(track.id)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.secondary.opacity(0.16))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
        }
    }
}
