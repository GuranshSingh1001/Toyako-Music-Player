import SwiftUI

struct PlaylistHeaderView: View {
    let playlist: Playlist
    let tracks: [LocalTrack]
    let onAddSongs: () -> Void

    @EnvironmentObject var audioManager: AudioEngineManager

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 700
            let artworkSize = compact ? 170.0 : min(250.0, proxy.size.height * 0.62)

            Group {
                if compact {
                    compactHero(artworkSize: artworkSize)
                } else {
                    wideHero(artworkSize: artworkSize)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, compact ? 22 : 34)
            .padding(.top, compact ? 12 : 20)
            .padding(.bottom, 16)
        }
        .frame(minHeight: 300, idealHeight: 335, maxHeight: 370)
    }

    @ViewBuilder
    private func wideHero(artworkSize: CGFloat) -> some View {
        HStack(spacing: 28) {
            PlaylistArtwork(tracks: tracks, playlistName: playlist.name)
                .frame(width: artworkSize, height: artworkSize)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.34), radius: 24, y: 12)

            VStack(alignment: .leading, spacing: 12) {
                Text("PLAYLIST")
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)

                Text(playlist.name)
                    .font(.system(size: 42, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                Text("\(tracks.count) \(tracks.count == 1 ? "Song" : "Tracks") • \(totalDurationString)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                actionBar
            }
            .frame(maxWidth: 650, alignment: .leading)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: 1120)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func compactHero(artworkSize: CGFloat) -> some View {
        HStack(spacing: 18) {
            PlaylistArtwork(tracks: tracks, playlistName: playlist.name)
                .frame(width: artworkSize, height: artworkSize)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.32), radius: 18, y: 9)

            VStack(alignment: .leading, spacing: 8) {
                Text("PLAYLIST")
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)

                Text(playlist.name)
                    .font(.system(size: 28, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                Text("\(tracks.count) \(tracks.count == 1 ? "Song" : "Tracks") • \(totalDurationString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 3)

                actionBar
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
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
        .fixedSize(horizontal: false, vertical: true)
    }

    private var totalDurationString: String {
        let seconds = max(0, Int(tracks.reduce(0) { $0 + $1.duration }))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours) hr \(minutes) min" : "\(minutes) min"
    }
}
