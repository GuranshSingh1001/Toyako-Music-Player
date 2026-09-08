import SwiftUI

struct AllPlaylistsGridView: View {
    let playlists: [Playlist]
    let library: LocalLibrary
    @Binding var selectedCategory: LibraryCategory?

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 20)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(playlists) { playlist in
                    Button {
                        selectedCategory = .playlist(playlist.id)
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