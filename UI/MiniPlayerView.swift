import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject var audioManager: AudioEngineManager
    let onOpenNowPlaying: () -> Void

    var body: some View {
        Button(action: onOpenNowPlaying) {
            HStack(spacing: 12) {
                artwork

                VStack(alignment: .leading, spacing: 4) {
                    Text(audioManager.currentTrack?.title ?? "Not Playing")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Text(audioManager.currentTrack?.artist ?? "Unknown Artist")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    GeometryReader { proxy in
                        Capsule()
                            .fill(.primary.opacity(0.11))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(.primary.opacity(0.52))
                                    .frame(width: proxy.size.width * min(max(audioManager.playbackProgress, 0), 1))
                            }
                    }
                    .frame(height: 2.5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                MiniPlayerActivity(
                    isPlaying: audioManager.isPlaying,
                    currentTime: audioManager.currentTime,
                    audioBands: audioManager.audioBands
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.22), value: audioManager.currentTrack?.id)
    }

    private var artwork: some View {
        Group {
            if let track = audioManager.currentTrack,
               let data = track.artworkData,
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .id(track.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            } else {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.secondary.opacity(0.16))
                    .frame(width: 44, height: 44)
                    .overlay { Image(systemName: "music.note").foregroundStyle(.secondary) }
            }
        }
    }
}

private struct MiniPlayerActivity: View {
    let isPlaying: Bool
    let currentTime: TimeInterval
    let audioBands: [Float]

    var body: some View {
        VStack(spacing: 5) {
            HStack(alignment: .bottom, spacing: 2.5) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(.primary.opacity(isPlaying ? 0.70 : 0.30))
                        .frame(width: 2.5, height: barHeight(index))
                        .animation(.easeOut(duration: 0.08), value: audioBands)
                }
            }
            .frame(height: 20, alignment: .bottom)

            Text(timeString)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(width: 34)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        guard isPlaying else { return 7 }

        // Each bar is driven by a different part of the actual spectrum:
        // bass -> low-mid -> mid -> upper-mid -> treble.
        let response = index < audioBands.count ? audioBands[index] : 0
        return CGFloat(4.5 + min(max(response, 0), 1) * 15.5)
    }

    private var timeString: String {
        let seconds = max(0, Int(currentTime.rounded()))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
