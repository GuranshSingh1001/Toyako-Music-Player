import SwiftUI

struct ArtistListView: View {
    let artists: [ArtistGroup]
    let library: LocalLibrary
    @EnvironmentObject var audioManager: AudioEngineManager

    var body: some View {
        List {
            ForEach(artists) { artist in
                NavigationLink {
                    SongListView(tracks: artist.tracks, allTracks: artist.tracks, library: library)
                        .navigationTitle(artist.name)
                } label: {
                    HStack {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 48, height: 48)
                            .overlay(Image(systemName: "person.fill").foregroundColor(.secondary))
                        VStack(alignment: .leading) {
                            Text(artist.name).font(.headline)
                            Text("\(artist.tracks.count) Songs").font(.caption).foregroundColor(.secondary)
                        }
                        .padding(.leading, 6)
                    }
                }
            }

            if audioManager.currentTrack != nil {
                Spacer(minLength: 70).listRowBackground(Color.clear)
            }
        }
    }
}
