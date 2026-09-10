import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject var audioManager: AudioEngineManager
    let onOpenNowPlaying: () -> Void

    var body: some View {
        Button {
            onOpenNowPlaying()
        } label: {
            HStack(spacing: 11) {
                artwork
                    .padding(.leading, 5)

                VStack(alignment: .leading, spacing: 3) {
                    Text(audioManager.currentTrack?.title ?? "Not Playing")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Text(audioManager.currentTrack?.artist ?? "Unknown Artist")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    GeometryReader { proxy in
                        Capsule()
                            .fill(.primary.opacity(0.12))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(.primary.opacity(0.55))
                                    .frame(width: proxy.size.width * min(max(audioManager.playbackProgress, 0), 1))
                            }
                    }
                    .frame(height: 2.5)
                    .clipped()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                MiniPlayerActivity(
                    isPlaying: audioManager.isPlaying,
                    progress: audioManager.playbackProgress,
                    currentTime: audioManager.currentTime
                )
                .padding(.trailing, 10)
            }
            .padding(.vertical, 7)
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: audioManager.currentTrack?.id)
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
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .id(track.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.secondary.opacity(0.16))
                    .frame(width: 44, height: 44)
                    .overlay { Image(systemName: "music.note").foregroundStyle(.secondary) }
            }
        }
    }
}

private struct MiniPlayerActivity: View {
    let isPlaying: Bool
    let progress: Double
    let currentTime: TimeInterval

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            VStack(spacing: 6) {
                HStack(alignment: .bottom, spacing: 2.5) {
                    ForEach(0..<5, id: \.self) { index in
                        Capsule()
                            .fill(.primary.opacity(isPlaying ? 0.72 : 0.32))
                            .frame(width: 2.5, height: barHeight(index, time: context.date.timeIntervalSinceReferenceDate))
                    }
                }
                .frame(height: 18, alignment: .bottom)

                Text(timeString)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(width: 30)
        }
    }

    private func barHeight(_ index: Int, time: TimeInterval) -> CGFloat {
        guard isPlaying else { return 7 }
        let phase = time * (1.8 + Double(index) * 0.12) + Double(index) * 1.35
        return CGFloat(8 + 7 * ((sin(phase) + 1) * 0.5) + progress * 2)
    }

    private var timeString: String {
        let seconds = max(0, Int(currentTime.rounded()))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
