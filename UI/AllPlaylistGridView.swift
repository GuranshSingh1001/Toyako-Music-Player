import SwiftUI

struct AllPlaylistsGridView: View {
    let playlists: [Playlist]
    let library: LocalLibrary

    var onAddSongs:
        (Playlist) -> Void

    var onRename:
        (Playlist) -> Void

    private let columns = [
        GridItem(
            .adaptive(
                minimum: ToyakoArtworkSize.playlistCard
            ),
            spacing: 20
        )
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns:
                    columns,
                spacing:
                    24
            ) {

                ForEach(
                    playlists
                ) { playlist in

                    let playlistTracks =
                        library.tracks.filter {
                            playlist.trackURLs
                                .contains(
                                    $0.url
                                )
                        }

                    NavigationLink {
                        SongListView(
                            tracks:
                                playlistTracks,
                            allTracks:
                                playlistTracks,
                            library:
                                library,
                            playlistID:
                                playlist.id,
                            headerView:
                                AnyView(
                                    PlaylistHeaderView(
                                        playlist:
                                            playlist,
                                        tracks:
                                            playlistTracks,
                                        library:
                                            library,
                                        onAddSongs:
                                            {
                                                onAddSongs(
                                                    playlist
                                                )
                                            }
                                    )
                                )
                        )
                    } label: {

                        VStack(
                            alignment:
                                .leading,
                            spacing:
                                8
                        ) {

                            PlaylistArtwork(
                                tracks:
                                    playlistTracks,
                                playlistName:
                                    playlist.name
                            )
                            .frame(
                                width:
                                    ToyakoArtworkSize.playlistCard,
                                height:
                                    ToyakoArtworkSize.playlistCard
                            )
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius:
                                        ToyakoDesign.Metrics.artworkRadius,
                                    style:
                                        .continuous
                                )
                            )


                            Text(
                                playlist.name
                            )
                            .font(ToyakoDesign.Typography.item)
                            .foregroundStyle(.primary)
                            .lineLimit(
                                1
                            )
                        }
                        .frame(
                            width:
                                ToyakoArtworkSize.playlistCard,
                            alignment:
                                .leading
                        )
                    }
                    .buttonStyle(
                        .plain
                    )
                    .contextMenu {

                        Button {
                            onAddSongs(
                                playlist
                            )
                        } label: {
                            Label(
                                "Add Songs",
                                systemImage:
                                    "plus"
                            )
                        }

                        Button {
                            onRename(
                                playlist
                            )
                        } label: {
                            Label(
                                "Edit Name",
                                systemImage:
                                    "pencil"
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, ToyakoDesign.Metrics.screenHorizontal)
            .padding(.top, ToyakoDesign.Metrics.screenTop)
            .padding(.bottom, ToyakoDesign.Metrics.screenBottom)
        }
    }
}

// MARK: - Playlist Artwork

struct PlaylistArtwork: View {
    let tracks: [LocalTrack]
    let playlistName: String

    private var urls: [URL] {
        Array(tracks.prefix(4)).map(\.url)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width / 2
            let height = proxy.size.height / 2

            if urls.isEmpty {
                emptyArtwork
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        tile(index: 0, width: width, height: height)
                        tile(index: 1, width: width, height: height)
                    }
                    HStack(spacing: 0) {
                        tile(index: 2, width: width, height: height)
                        tile(index: 3, width: width, height: height)
                    }
                }
            }
        }
    }

    private func tile(index: Int, width: CGFloat, height: CGFloat) -> some View {
        LazyArtwork(
            url: urls[index % urls.count],
            size: max(width, height),
            cornerRadius: 0
        )
        .frame(width: width, height: height)
        .clipped()
    }

    private var emptyArtwork: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.thinMaterial)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 38, weight: .medium))
                    Text(playlistName)
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .foregroundStyle(.secondary)
            }
    }
}
