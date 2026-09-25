import SwiftUI

struct PlaylistHeaderView: View {
    let playlist: Playlist
    let tracks: [LocalTrack]
    let onAddSongs: () -> Void

    @EnvironmentObject var audioManager: AudioEngineManager

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 760

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 6)

                HStack(alignment: .bottom, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(playlist.name)
                            .font(.system(size: compact ? 42 : 54, weight: .bold))
                            .tracking(-1.2)
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)

                        Text("\(tracks.count) \(tracks.count == 1 ? "Song" : "Tracks") • \(totalDurationString)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 20)

                    actionBar
                }
                .frame(maxWidth: .infinity, alignment: .bottom)

                Spacer(minLength: 26)
            }
            .frame(maxWidth: 1320)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, compact ? 28 : 38)
        }
        .frame(minHeight: 205, idealHeight: 235, maxHeight: 270)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                guard !tracks.isEmpty else { return }
                audioManager.startQueue(tracks: tracks, startIndex: 0)
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.subheadline.bold())
            }
            .buttonStyle(ToyakoPrimaryButtonStyle())

            Button {
                guard !tracks.isEmpty else { return }
                if !audioManager.isShuffle {
                    audioManager.toggleShuffle()
                }
                audioManager.startQueue(
                    tracks: tracks,
                    startIndex: Int.random(in: 0..<tracks.count)
                )
            } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .font(.subheadline.bold())
            }
            .buttonStyle(ToyakoSecondaryButtonStyle())

            Button(action: onAddSongs) {
                Label("Add Songs", systemImage: "plus")
                    .font(.subheadline.bold())
            }
            .buttonStyle(ToyakoSecondaryButtonStyle())
        }
    }

    private var totalDurationString: String {
        let seconds = max(0, Int(tracks.reduce(0) { $0 + $1.duration }))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours) hr \(minutes) min" : "\(minutes) min"
    }
}
