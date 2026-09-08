import SwiftUI

struct AllPlaylistsGridView: View {
    let playlists: [Playlist]
    let library: LocalLibrary
    var onEditPlaylist: (Playlist) -> Void

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 20)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(playlists) { playlist in
                    NavigationLink {
                        let pTracks = library.tracks.filter { playlist.trackURLs.contains($0.url) }
                        SongListView(
                            tracks: pTracks,
                            allTracks: pTracks,
                            library: library,
                            playlistID: playlist.id,
                            headerView: AnyView(
                                PlaylistHeaderView(
                                    playlist: playlist,
                                    tracks: pTracks,
                                    onAddSongs: { onEditPlaylist(playlist) }
                                )
                            )
                        )
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            AbstractPlaylistCover(playlistID: playlist.id)
                                .frame(width: 160, height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                            
                            Text(playlist.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                        .frame(width: 160)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Change Cover Style") {
                            if let idx = library.playlists.firstIndex(where: { $0.id == playlist.id }) {
                                library.playlists[idx] = Playlist(id: UUID(), name: playlist.name, trackURLs: playlist.trackURLs)
                            }
                        }
                        Button("Edit Name") {
                            onEditPlaylist(playlist)
                        }
                    }
                }
            }
            .padding()
        }
    }
}
