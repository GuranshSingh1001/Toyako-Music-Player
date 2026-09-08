import SwiftUI

struct PlaylistHeaderView: View {
    let playlist: Playlist
    let tracks: [LocalTrack]
    let onAddSongs: () -> Void
    @EnvironmentObject var audioManager: AudioEngineManager

    var body: some View {
        HStack(spacing: 24) {
            playlistArtwork
                .frame(width: 130, height: 130)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.3), radius: 10, y: 5)

            VStack(alignment: .leading, spacing: 8) {
                Text("PLAYLIST").font(.caption.bold()).foregroundColor(.secondary)
                Text(playlist.name).font(.title.bold()).lineLimit(1)
                Text("\(tracks.count) Songs • \(totalDurationString)")
                    .font(.subheadline).foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Button {
                        if !tracks.isEmpty { audioManager.startQueue(tracks: tracks, startIndex: 0) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                            Text("Play")
                        }
                        .font(.subheadline.bold())
                        .foregroundColor(.blue) // Ensure icon and text are visible
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassEffect(.regular) // Safely inferring the iOS 26 material

                    Button {
                        if !tracks.isEmpty {
                            if !audioManager.isShuffle { audioManager.toggleShuffle() }
                            audioManager.startQueue(tracks: tracks, startIndex: Int.random(in: 0..<tracks.count))
                        }
                    } label: {
                        Label("Shuffle", systemImage: "shuffle").font(.subheadline.bold())
                    }.buttonStyle(.bordered)

                    Button(action: onAddSongs) {
                        Label("Add Songs", systemImage: "plus.circle").font(.subheadline.bold())
                    }.buttonStyle(.bordered)
                }
                .padding(.top, 4)
            }
            Spacer()
        }
        .padding(20)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var playlistArtwork: some View {
        let arts = tracks.compactMap { $0.artworkData }
        if arts.count >= 4 {
            VStack(spacing: 0) {
                HStack(spacing: 0) { artSquare(data: arts[0]); artSquare(data: arts[1]) }
                HStack(spacing: 0) { artSquare(data: arts[2]); artSquare(data: arts[3]) }
            }
        } else if let first = arts.first {
            artSquare(data: first)
        } else {
            Rectangle().fill(Color.gray.opacity(0.2))
                .overlay(Image(systemName: "music.note.list").font(.system(size: 40)).foregroundColor(.secondary))
        }
    }

    private func artSquare(data: Data) -> some View {
        Group {
            if let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Color.gray.opacity(0.3)
            }
        }
    }

    private var totalDurationString: String {
        let total = tracks.reduce(0) { $0 + $1.duration }
        return "\(Int(total) / 60) mins"
    }
}
