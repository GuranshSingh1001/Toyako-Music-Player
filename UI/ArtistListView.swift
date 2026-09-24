import SwiftUI

struct ArtistListView: View {
    let artists: [ArtistGroup]
    let library: LocalLibrary
    @EnvironmentObject var audioManager: AudioEngineManager

    var body: some View {
        List {
            Section {
                ForEach(artists) { artist in
                    NavigationLink {
                        SongListView(tracks: artist.tracks, allTracks: artist.tracks, library: library)
                            .navigationTitle(artist.name)
                    } label: {
                        HStack(spacing: 14) {
                            ArtistArtworkView(artistName: artist.name, size: 54)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(artist.name)
                                    .font(.headline)
                                    .lineLimit(1)

                                Text(artist.tracks.count == 1 ? "1 Track" : "\(artist.tracks.count) Tracks")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 8)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("\(artists.count) Artists")
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: audioManager.currentTrack != nil ? 80 : 0)
        }
    }
}
