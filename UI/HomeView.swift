import SwiftUI

struct HomeView: View {
    let tracks: [LocalTrack]
    let albums: [AlbumGroup]
    let artists: [ArtistGroup]
    let playlists: [Playlist]
    let library: LocalLibrary
    let onImport: () -> Void
    let onNewPlaylist: () -> Void

    @EnvironmentObject var audioManager: AudioEngineManager

    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 16)
    ]

    private var featuredAlbums: [AlbumGroup] {
        Array(albums.prefix(8))
    }

    private var featuredArtists: [ArtistGroup] {
        Array(artists.prefix(8))
    }

    private var featuredPlaylists: [Playlist] {
        Array(playlists.prefix(8))
    }

    private var trackByURL: [URL: LocalTrack] {
        Dictionary(uniqueKeysWithValues: tracks.map {
            ($0.url.standardizedFileURL, $0)
        })
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                header
                quickActions

                if let current = audioManager.currentTrack {
                    continueListening(current)
                }

                if !featuredAlbums.isEmpty {
                    section("Albums") {
                        horizontalAlbums(featuredAlbums)
                    }
                }

                if !featuredArtists.isEmpty {
                    section("Artists") {
                        horizontalArtists(featuredArtists)
                    }
                }

                if !featuredPlaylists.isEmpty {
                    section("Playlists") {
                        horizontalPlaylists(featuredPlaylists)
                    }
                }

                if !tracks.isEmpty {
                    section("Your Tracks") {
                        horizontalTracks(Array(tracks.prefix(12)))
                    }
                }

                libraryOverview
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 100)
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.large)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Your Library")
                .font(.largeTitle.weight(.bold))

            Text(
                tracks.isEmpty
                    ? "Import music to start building your offline library."
                    : "\(tracks.count) \(tracks.count == 1 ? "track" : "tracks") ready to play offline."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            HomeActionButton(title: "Shuffle All", systemImage: "shuffle") {
                guard !tracks.isEmpty else { return }
                let index = Int.random(in: tracks.indices)
                if !audioManager.isShuffle {
                    audioManager.toggleShuffle()
                }
                audioManager.startQueue(tracks: tracks, startIndex: index)
            }

            HomeActionButton(title: "Import", systemImage: "plus") {
                onImport()
            }

            HomeActionButton(title: "Playlist", systemImage: "text.badge.plus") {
                onNewPlaylist()
            }
        }
    }

    private func continueListening(_ track: LocalTrack) -> some View {
        section("Continue Listening") {
            Button {
                if audioManager.currentTrack?.id == track.id {
                    audioManager.togglePlayPause()
                } else if let index = tracks.firstIndex(where: { $0.id == track.id }) {
                    audioManager.startQueue(tracks: tracks, startIndex: index)
                }
            } label: {
                HStack(spacing: 14) {
                    TrackArtwork(track: track, size: 68)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if audioManager.currentTrack?.id == track.id {
                            Text(audioManager.isPlaying ? "Playing now" : "Paused")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .background(.thinMaterial, in: Circle())
                }
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.bold))
            content()
        }
    }

    private func horizontalTracks(_ items: [LocalTrack]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                ForEach(items) { track in
                    Button {
                        if let index = tracks.firstIndex(where: { $0.id == track.id }) {
                            audioManager.startQueue(tracks: tracks, startIndex: index)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            TrackArtwork(track: track, size: 145)
                            Text(track.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(track.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(width: 145, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func horizontalAlbums(_ items: [AlbumGroup]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                ForEach(items) { album in
                    NavigationLink {
                        AlbumDetailView(album: album, library: library)
                            .navigationTitle(album.name)
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            AlbumArtwork(artworkData: album.artworkData)
                                .frame(width: 145, height: 145)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Text(album.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(album.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(width: 145, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func horizontalArtists(_ items: [ArtistGroup]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 16) {
                ForEach(items) { artist in
                    NavigationLink {
                        SongListView(
                            tracks: artist.tracks,
                            allTracks: artist.tracks,
                            library: library
                        )
                        .navigationTitle(artist.name)
                    } label: {
                        VStack(spacing: 8) {
                            Circle()
                                .fill(.thinMaterial)
                                .frame(width: 100, height: 100)
                                .overlay {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 34))
                                        .foregroundStyle(.secondary)
                                }

                            Text(artist.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                        }
                        .frame(width: 110)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func horizontalPlaylists(_ items: [Playlist]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                ForEach(items) { playlist in
                    let playlistTracks = playlist.trackURLs.compactMap {
                        trackByURL[$0.standardizedFileURL]
                    }

                    NavigationLink {
                        SongListView(
                            tracks: playlistTracks,
                            allTracks: playlistTracks,
                            library: library,
                            playlistID: playlist.id
                        )
                        .navigationTitle(playlist.name)
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            PlaylistArtwork(
                                tracks: playlistTracks,
                                playlistName: playlist.name
                            )
                            .frame(width: 145, height: 145)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                            Text(playlist.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)

                            Text("\(playlistTracks.count) tracks")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 145, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var libraryOverview: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            HomeStatCard(title: "Tracks", value: tracks.count, systemImage: "music.note.list")
            HomeStatCard(title: "Albums", value: albums.count, systemImage: "square.stack")
            HomeStatCard(title: "Artists", value: artists.count, systemImage: "music.mic")
            HomeStatCard(title: "Playlists", value: playlists.count, systemImage: "rectangle.stack")
        }
    }
}

private struct HomeActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct HomeStatCard: View {
    let title: String
    let value: Int
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)")
                    .font(.headline)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(13)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct TrackArtwork: View {
    let track: LocalTrack
    let size: CGFloat

    var body: some View {
        Group {
            if let data = track.artworkData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
