import SwiftUI
import UIKit

struct QueueView: View {
    @EnvironmentObject private var audioManager: AudioEngineManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        QueueContent(
            currentTrack: audioManager.currentTrack,
            queue: audioManager.queue,
            queueIndex: audioManager.queueIndex,
            isPlaying: audioManager.isPlaying,
            onSelect: { index in audioManager.playQueuedTrack(at: index) },
            onRemove: { index in audioManager.removeFromQueue(at: IndexSet(integer: index)) },
            onClear: { audioManager.clearQueue() },
            onDismiss: { dismiss() }
        )
        .equatable()
    }
}

private struct QueueContent: View, Equatable {
    let currentTrack: LocalTrack?
    let queue: [LocalTrack]
    let queueIndex: Int
    let isPlaying: Bool

    let onSelect: (Int) -> Void
    let onRemove: (Int) -> Void
    let onClear: () -> Void
    let onDismiss: () -> Void

    static func == (lhs: QueueContent, rhs: QueueContent) -> Bool {
        lhs.queueIndex == rhs.queueIndex &&
        lhs.isPlaying == rhs.isPlaying &&
        trackFingerprint(lhs.currentTrack) == trackFingerprint(rhs.currentTrack) &&
        lhs.queue.map(trackFingerprint) == rhs.queue.map(trackFingerprint)
    }

    private static func trackFingerprint(_ track: LocalTrack?) -> String {
        guard let track else { return "nil" }
        return "\(track.id.uuidString)|\(track.title)|\(track.artist)|\(track.album)|\(track.artworkData != nil)"
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let currentTrack {
                        sectionTitle("Playing")
                        QueueRow(
                            track: currentTrack,
                            current: true,
                            isPlaying: isPlaying,
                            onSelect: nil,
                            onRemove: nil
                        )
                    }

                    let start = min(queueIndex + 1, queue.count)
                    if start < queue.count {
                        sectionTitle("Up Next")
                            .padding(.top, 22)

                        ForEach(Array(queue[start...])) { track in
                            if let index = queue.firstIndex(where: { $0.id == track.id }) {
                                QueueRow(
                                    track: track,
                                    current: false,
                                    isPlaying: false,
                                    onSelect: { onSelect(index) },
                                    onRemove: { onRemove(index) }
                                )
                            }
                        }
                    } else if currentTrack != nil {
                        Text("No more songs in the queue")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 20)
                            .padding(.horizontal, 22)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 22)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .glassEffect(
            .regular.interactive(),
            in: RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
        .padding(8)
        .background(Color.clear)
    }

    private var header: some View {
        HStack {
            Button("Done", action: onDismiss)
                .buttonStyle(.glass)

            Spacer()

            Text("Queue")
                .font(.headline.weight(.semibold))

            Spacer()

            if queue.count > 1 {
                Button("Clear", role: .destructive, action: onClear)
                    .buttonStyle(.glass)
            } else {
                Color.clear.frame(width: 64, height: 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .foregroundStyle(.primary)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
    }
}

private struct QueueRow: View {
    let track: LocalTrack
    let current: Bool
    let isPlaying: Bool
    let onSelect: (() -> Void)?
    let onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            artwork

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
            }
        }
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .onTapGesture { onSelect?() }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if let onRemove {
                Button(role: .destructive, action: onRemove) {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.primary.opacity(0.09))
                .frame(height: 0.5)
                .padding(.leading, 56)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let data = track.artworkData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.secondary.opacity(0.14))
                .frame(width: 44, height: 44)
                .overlay { Image(systemName: "music.note").foregroundStyle(.secondary) }
        }
    }
}
