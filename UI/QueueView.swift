import SwiftUI
import UIKit

struct QueueView: View {
    @EnvironmentObject private var audioManager: AudioEngineManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if audioManager.queue.isEmpty {
                    ContentUnavailableView(
                        "Queue is Empty",
                        systemImage: "list.bullet",
                        description: Text("Songs you add to the queue will appear here.")
                    )
                } else {
                    List {
                        Section("Playing") {
                            if let current = audioManager.currentTrack {
                                queueRow(current, current: true)
                            }
                        }

                        let upcoming = Array(
                            audioManager.queue.dropFirst(min(audioManager.queueIndex + 1, audioManager.queue.count))
                        )

                        if !upcoming.isEmpty {
                            Section("Up Next") {
                                ForEach(upcoming) { track in
                                    if let index = audioManager.queue.firstIndex(where: { $0.id == track.id }) {
                                        queueRow(track, current: false, index: index)
                                    }
                                }
                                .onDelete { offsets in
                                    let actual = offsets.map { $0 + audioManager.queueIndex + 1 }
                                    audioManager.removeFromQueue(at: IndexSet(actual))
                                }
                                .onMove { offsets, destination in
                                    let base = audioManager.queueIndex + 1
                                    let actualSource = IndexSet(offsets.map { $0 + base })
                                    let actualDestination = destination + base
                                    audioManager.moveQueue(from: actualSource, to: actualDestination)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                }
            }
            .background(Color.clear)
            .navigationTitle("Queue")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if audioManager.queue.count > 1 {
                        Button("Clear", role: .destructive) {
                            audioManager.clearQueue()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func queueRow(
        _ track: LocalTrack,
        current: Bool,
        index: Int? = nil
    ) -> some View {
        Button {
            if let index {
                audioManager.playQueuedTrack(at: index)
            }
        } label: {
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
                Spacer()
                if current {
                    Image(systemName: audioManager.isPlaying ? "waveform" : "pause.fill")
                        .foregroundStyle(.tint)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func artwork(for track: LocalTrack) -> some View {
        if let data = track.artworkData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.secondary.opacity(0.14))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                }
        }
    }
}
