import SwiftUI
import UIKit

/// Read-only playback queue. Queue editing was intentionally removed because
/// manual reordering/removal was causing inconsistent queueIndex state.
/// The queue remains fully visible, and tapping an upcoming track still plays it.
struct QueueView: View {
    var embedded: Bool = false
    var preloadedArtwork: [URL: Data] = [:]
    @EnvironmentObject private var audioManager: AudioEngineManager

    var body: some View {
        VStack(spacing: 0) {
            if !embedded {
                HStack {
                    Spacer()
                    Text("Queue").font(ToyakoDesign.Typography.item)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)
            }

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let start = min(audioManager.queueIndex + 1, audioManager.queue.count)

                    if let current = audioManager.currentTrack {
                        Text("Playing")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.bottom, 8)

                        QueueRow(
                            track: current,
                            current: true,
                            isPlaying: audioManager.isPlaying,
                            artworkData: preloadedArtwork[current.url.standardizedFileURL]
                        )
                    }

                    if start < audioManager.queue.count {
                        Text("Up Next")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.top, 22)
                            .padding(.bottom, 8)

                        ForEach(Array(audioManager.queue[start...].enumerated()), id: \.element.id) { offset, track in
                            let index = start + offset
                            QueueRow(
                                track: track,
                                current: false,
                                isPlaying: false,
                                artworkData: preloadedArtwork[track.url.standardizedFileURL],
                                onSelect: {
                                    audioManager.playQueuedTrack(at: index)
                                }
                            )
                        }
                    } else if audioManager.currentTrack != nil {
                        Text("No more songs in the queue")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 20)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 18)
                // Give the embedded queue a little breathing room below the Now Playing header.
                .padding(.top, embedded ? 20 : 0)
                .padding(.bottom, 22)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .clipShape(RoundedRectangle(cornerRadius: ToyakoDesign.Metrics.cardRadius, style: .continuous))
        .background {
            if !embedded {
                RoundedRectangle(cornerRadius: ToyakoDesign.Metrics.cardRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
        .overlay {
            if !embedded {
                RoundedRectangle(cornerRadius: ToyakoDesign.Metrics.cardRadius, style: .continuous)
                    .stroke(.primary.opacity(0.12), lineWidth: 1)
            }
        }
        .padding(embedded ? 0 : 8)
        .background(Color.clear)
    }
}

private struct QueueRow: View {
    let track: LocalTrack
    let current: Bool
    let isPlaying: Bool
    var artworkData: Data? = nil
    var onSelect: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            LazyArtwork(url: track.url, size: ToyakoArtworkSize.row, cornerRadius: ToyakoDesign.Metrics.artworkSmallRadius, initialData: artworkData)

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.body.weight(current ? .semibold : .regular))
                    .lineLimit(1)

                Text(track.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if current {
                Image(systemName: isPlaying ? "waveform" : "pause.fill")
                    .foregroundStyle(.tint)
                    .contentTransition(.symbolEffect(.replace))
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(minHeight: 88)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect?()
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.primary.opacity(0.09))
                .frame(height: 0.5)
                .padding(.leading, 56)
        }
    }
}
