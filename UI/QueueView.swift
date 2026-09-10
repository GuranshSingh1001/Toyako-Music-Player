import SwiftUI
import UIKit

struct QueueView: View {
    @EnvironmentObject private var audioManager: AudioEngineManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.clear

            VStack(spacing: 0) {
                header

                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if let current = audioManager.currentTrack {
                            sectionTitle("Playing")
                            queueRow(current, current: true)
                        }

                        let start = min(
                            audioManager.queueIndex + 1,
                            audioManager.queue.count
                        )
                        let upcoming = Array(audioManager.queue.dropFirst(start))

                        if !upcoming.isEmpty {
                            sectionTitle("Up Next")
                                .padding(.top, 22)

                            ForEach(upcoming) { track in
                                if let index = audioManager.queue.firstIndex(where: { $0.id == track.id }) {
                                    queueRow(track, current: false, index: index)
                                }
                            }
                        } else if audioManager.currentTrack != nil {
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
                .transaction { transaction in
                    // Do not let row animations participate in scrolling.
                    transaction.animation = nil
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .glassEffect(
                .regular.interactive(),
                in: RoundedRectangle(cornerRadius: 30, style: .continuous)
            )
            .padding(8)
        }
        .background(Color.clear)
    }

    private var header: some View {
        HStack {
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.glass)

            Spacer()

            Text("Queue")
                .font(.headline.weight(.semibold))

            Spacer()

            if audioManager.queue.count > 1 {
                Button("Clear", role: .destructive) {
                    audioManager.clearQueue()
                }
                .buttonStyle(.glass)
            } else {
                // Keep the title visually centered.
                Color.clear
                    .frame(width: 64, height: 1)
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

    @ViewBuilder
    private func queueRow(
        _ track: LocalTrack,
        current: Bool,
        index: Int? = nil
    ) -> some View {
        HStack(spacing: 12) {
            artwork(for: track)

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
                Image(systemName: audioManager.isPlaying ? "waveform" : "pause.fill")
                    .foregroundStyle(.tint)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .onTapGesture {
            if let index {
                audioManager.playQueuedTrack(at: index)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if let index, !current {
                Button(role: .destructive) {
                    audioManager.removeFromQueue(at: IndexSet(integer: index))
                } label: {
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
    private func artwork(for track: LocalTrack) -> some View {
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
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                }
        }
    }
}
