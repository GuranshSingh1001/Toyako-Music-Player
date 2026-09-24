import SwiftUI

struct AllPlaylistsGridView: View {
    let playlists: [Playlist]
    let library: LocalLibrary

    var onAddSongs:
        (Playlist) -> Void

    var onRename:
        (Playlist) -> Void

    var onDelete:
        (Playlist) -> Void

    private let columns = [
        GridItem(
            .adaptive(
                minimum: 160
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
                                        onAddSongs:
                                            {
                                                onAddSongs(
                                                    playlist
                                                )
                                            }
                                    )
                                )
                        )
                        .navigationTitle(
                            playlist.name
                        )
                        .navigationBarTitleDisplayMode(
                            .inline
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
                                    playlist.name,
                                playlistID:
                                    playlist.id
                            )
                            .frame(
                                width:
                                    160,
                                height:
                                    160
                            )
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius:
                                        16,
                                    style:
                                        .continuous
                                )
                            )
                            .shadow(
                                color:
                                    .black.opacity(
                                        0.20
                                    ),
                                radius:
                                    10,
                                y:
                                    5
                            )

                            Text(
                                playlist.name
                            )
                            .font(
                                .headline
                            )
                            .foregroundColor(
                                .primary
                            )
                            .lineLimit(
                                1
                            )
                        }
                        .frame(
                            width:
                                160,
                            alignment:
                                .leading
                        )
                    }
                    .buttonStyle(
                        .plain
                    )
                    .overlay(alignment: .topTrailing) {
                        Menu {
                            Button {
                                onAddSongs(playlist)
                            } label: {
                                Label("Add Songs", systemImage: "plus")
                            }

                            Button {
                                onRename(playlist)
                            } label: {
                                Label("Edit Name", systemImage: "pencil")
                            }

                            Divider()

                            Button(role: .destructive) {
                                onDelete(playlist)
                            } label: {
                                Label("Delete Playlist", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.45), radius: 5)
                                .padding(7)
                                .background(.black.opacity(0.28), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(6)
                    }
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

                        Button(role: .destructive) {
                            onDelete(playlist)
                        } label: {
                            Label("Delete Playlist", systemImage: "trash")
                        }
                    }
                }
            }
            .padding()
            .padding(
                .bottom,
                80
            )
        }
    }
}

// MARK: - Playlist Artwork

struct PlaylistArtwork: View {
    let tracks: [LocalTrack]
    let playlistName: String
    var playlistID: UUID? = nil

    private var urls: [URL] {
        Array(tracks.prefix(4)).map(\.url)
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.thinMaterial)

                if urls.isEmpty {
                    emptyArtwork
                } else {
                    ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                        collageCard(
                            url: url,
                            index: index,
                            count: urls.count,
                            side: side
                        )
                    }
                }

                // A very subtle glass highlight keeps the collage looking like
                // one designed cover instead of four unrelated square images.
                LinearGradient(
                    colors: [
                        .white.opacity(0.14),
                        .clear,
                        .black.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .allowsHitTesting(false)
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
            )
        }
    }

    @ViewBuilder
    private func collageCard(
        url: URL,
        index: Int,
        count: Int,
        side: CGFloat
    ) -> some View {
        let cardSize: CGFloat = {
            switch count {
            case 1:
                return side * 0.82
            case 2:
                return side * 0.68
            default:
                return side * 0.62
            }
        }()

        LazyArtwork(
            url: url,
            size: cardSize,
            cornerRadius: 14
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(
            color: .black.opacity(0.28),
            radius: 7,
            y: 4
        )
        .rotationEffect(.degrees(rotation(for: index, count: count)))
        .offset(offset(for: index, count: count, side: side))
        .zIndex(Double(index))
    }

    private func rotation(for index: Int, count: Int) -> Double {
        switch count {
        case 1:
            return 0
        case 2:
            return index == 0 ? -5 : 5
        case 3:
            return [-6, 5, -2][index]
        default:
            return [-5, 4, 3, -4][index]
        }
    }

    private func offset(
        for index: Int,
        count: Int,
        side: CGFloat
    ) -> CGSize {
        switch count {
        case 1:
            return .zero
        case 2:
            let amount = side * 0.14
            return index == 0
                ? CGSize(width: -amount, height: amount * 0.35)
                : CGSize(width: amount, height: -amount * 0.35)
        case 3:
            let amount = side * 0.16
            switch index {
            case 0:
                return CGSize(width: -amount, height: amount * 0.50)
            case 1:
                return CGSize(width: amount, height: amount * 0.25)
            default:
                return CGSize(width: 0, height: -amount)
            }
        default:
            let amount = side * 0.17
            switch index {
            case 0:
                return CGSize(width: -amount, height: -amount)
            case 1:
                return CGSize(width: amount, height: -amount)
            case 2:
                return CGSize(width: -amount, height: amount)
            default:
                return CGSize(width: amount, height: amount)
            }
        }
    }

    private var emptyArtwork: some View {
        AbstractPlaylistCover(playlistID: playlistID ?? UUID())
            .overlay {
                Text(playlistName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(12)
                    .background(.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(12)
            }
    }
}

