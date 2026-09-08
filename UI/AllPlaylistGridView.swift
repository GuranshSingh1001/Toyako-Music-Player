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
                    // 1. Uses NavigationLink to push the detail view over the grid with a Back button
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
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 160, height: 160)
                                .overlay(
                                    Image(systemName: "music.note.list")
                                        .font(.largeTitle)
                                        .foregroundColor(.gray)
                                )
                            
                            Text(playlist.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                        .frame(width: 160)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }
}
