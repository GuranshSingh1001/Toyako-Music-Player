import SwiftUI

struct SongListView: View {
    let tracks: [LocalTrack]
    let allTracks: [LocalTrack]
    let library: LocalLibrary
    var playlistID: UUID? = nil
    var headerView: AnyView? = nil
    @EnvironmentObject var audioManager: AudioEngineManager

    var body: some View {
        List {
            if let header = headerView {
                header
            }

            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                HStack(spacing: 12) {
                    if let data = track.artworkData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .cornerRadius(6)
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 44, height: 44)
                            .overlay(Image(systemName: "music.note").foregroundColor(.gray))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title).font(.headline).lineLimit(1)
                        Text("\(track.artist) — \(track.album)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(formatTime(track.duration))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    audioManager.startQueue(tracks: allTracks, startIndex: index)
                }
                .contextMenu {
                    if let pID = playlistID {
                        Button(role: .destructive) {
                            library.removeTrackFromPlaylist(playlistID: pID, trackURL: track.url)
                        } label: {
                            Label("Remove from Playlist", systemImage: "trash")
                        }
                    }
                    Menu("Add to Playlist") {
                        ForEach(library.playlists) { pl in
                            Button(pl.name) {
                                library.addTracksToPlaylist(playlistID: pl.id, trackURLs: [track.url])
                            }
                        }
                    }
                }
            }

            if audioManager.currentTrack != nil {
                Spacer(minLength: 70).listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
    }

    private func formatTime(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
