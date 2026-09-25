import SwiftUI

struct PlaylistHeaderView: View {
    let playlist: Playlist
    let tracks: [LocalTrack]
    let onAddSongs: () -> Void

    @EnvironmentObject var audioManager: AudioEngineManager

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 720
            let artworkSize = min(
                compact ? 190 : 240,
                max(150, proxy.size.width * (compact ? 0.52 : 0.26))
            )

            VStack(spacing: compact ? 16 : 20) {
                PlaylistArtwork(
                    tracks: tracks,
                    playlistName: playlist.name
                )
                .frame(width: artworkSize, height: artworkSize)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: ToyakoDesign.Metrics.artworkRadius,
                        style: .continuous
                    )
                )
                .shadow(color: .black.opacity(0.30), radius: 22, y: 12)

                VStack(spacing: 7) {
                    Text("PLAYLIST")
                        .font(.caption.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)

                    Text(playlist.name)
                        .font(
                            compact
                                ? .system(size: 30, weight: .bold)
                                : ToyakoDesign.Typography.screenTitle
                        )
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)

                    Text(
                        "\(tracks.count) \(tracks.count == 1 ? "Song" : "Tracks") • \(totalDurationString)"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 620)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, compact ? 20 : ToyakoDesign.Metrics.screenHorizontal)
            .padding(.top, compact ? 16 : 22)
            .padding(.bottom, 78)
        }
        .frame(minHeight: 360, idealHeight: 410, maxHeight: 450)
        .overlay(alignment: .bottom) {
            actionBar
                .padding(.horizontal, ToyakoDesign.Metrics.screenHorizontal)
                .padding(.bottom, 14)
        }
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
                let index = Int.random(in: 0..<tracks.count)
                audioManager.startQueue(tracks: tracks, startIndex: index)
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
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
    }

    private var totalDurationString: String {
        let seconds = max(0, Int(tracks.reduce(0) { $0 + $1.duration }))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours > 0 {
            return "\(hours) hr \(minutes) min"
        }

        return "\(minutes) min"
    }
}
