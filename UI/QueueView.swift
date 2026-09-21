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
            onMove: { from, to in audioManager.moveQueue(from: IndexSet(integer: from), to: to) },
            onDismiss: { dismiss() }
        )
    }
}

private struct QueueContent: View {
    let currentTrack: LocalTrack?
    let queue: [LocalTrack]
    let queueIndex: Int
    let isPlaying: Bool

    let onSelect: (Int) -> Void
    let onRemove: (Int) -> Void
    let onClear: () -> Void
    let onMove: (Int, Int) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let start = min(queueIndex + 1, queue.count)

                    if let currentTrack {
                        sectionTitle("Playing")
                        QueueRow(
                            track: currentTrack,
                            current: true,
                            isPlaying: isPlaying,
                            onSelect: nil,
                            onRemove: nil,
                            reorderIndex: nil,
                            queueStartIndex: start,
                            onMove: nil
                        )
                    }

                    if start < queue.count {
                        sectionTitle("Up Next")
                            .padding(.top, 22)

                        ForEach(Array(queue[start...].enumerated()), id: \.element.id) { offset, track in
                            let index = start + offset
                            QueueRow(
                                track: track,
                                current: false,
                                isPlaying: false,
                                onSelect: { onSelect(index) },
                                onRemove: { onRemove(index) },
                                reorderIndex: index,
                                queueStartIndex: start,
                                onMove: onMove
                            )
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
    let reorderIndex: Int?
    let queueStartIndex: Int
    let onMove: ((Int, Int) -> Void)?

    @State private var isReordering = false
    @State private var dragStartIndex: Int?
    @State private var lastTranslationY: CGFloat = 0

    private let rowHeight: CGFloat = 64

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

            if let reorderIndex, onMove != nil {
                ReorderHandle(
                    isActive: isReordering,
                    onChanged: { translation in
                        handleReorderChange(translation: translation, index: reorderIndex)
                    },
                    onEnded: {
                        finishReordering()
                    }
                )
            }

            if current {
                Image(systemName: isPlaying ? "waveform" : "pause.fill")
                    .foregroundStyle(.tint)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .frame(minHeight: rowHeight)
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

    private func handleReorderChange(translation: CGFloat, index: Int) {
        guard let onMove, !current else { return }

        if !isReordering {
            isReordering = true
            dragStartIndex = index
            lastTranslationY = 0
        }

        guard let workingIndex = dragStartIndex else { return }

        let delta = translation - lastTranslationY
        guard abs(delta) >= rowHeight * 0.48 else { return }

        let direction = delta > 0 ? 1 : -1
        let destination = workingIndex + direction

        guard destination >= queueStartIndex else { return }
        onMove(workingIndex, destination)
        dragStartIndex = destination
        lastTranslationY = translation
    }

    private func finishReordering() {
        isReordering = false
        dragStartIndex = nil
        lastTranslationY = 0
    }

    private var artwork: some View {
        LazyArtwork(url: track.url, size: 44, cornerRadius: 8)
    }
}

private struct ReorderHandle: View {
    let isActive: Bool
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isActive ? .primary : .secondary)
            .frame(width: 40, height: 44)
            .contentShape(Rectangle())
            .scaleEffect(isActive ? 1.08 : 1)
            .animation(.easeOut(duration: 0.16), value: isActive)
            .gesture(
                LongPressGesture(minimumDuration: 0.24)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onChanged { value in
                        switch value {
                        case .first(true):
                            break
                        case .second(true, let drag):
                            onChanged(drag?.translation.height ?? 0)
                        default:
                            break
                        }
                    }
                    .onEnded { _ in
                        onEnded()
                    }
            )
            .accessibilityLabel("Reorder")
            .accessibilityHint("Hold and slide up or down to change the song order")
    }
}
