import SwiftUI

struct HomeView: View {
    let tracks: [LocalTrack]
    let albums: [AlbumGroup]
    let artists: [ArtistGroup]
    let playlists: [Playlist]
    let recentlyPlayed: [LocalTrack]
    let library: LocalLibrary
    let onImport: () -> Void
    let onNewPlaylist: () -> Void
    let currentTrack: LocalTrack?
    let isPlaying: Bool
    let onPlayTrack: (Int) -> Void
    let onTogglePlayPause: () -> Void
    let onShuffleAll: () -> Void

    @State private var recommendationSeed = UInt64.random(in: 1...UInt64.max)

    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 16)
    ]

    private var recommendedAlbums: [AlbumGroup] {
        var rng = SeededGenerator(seed: recommendationSeed)
        return Array(albums.shuffled(using: &rng).prefix(8))
    }

    private var recommendedArtists: [ArtistGroup] {
        var rng = SeededGenerator(seed: recommendationSeed &+ 17)
        return Array(artists.shuffled(using: &rng).prefix(8))
    }

    private var recommendedPlaylists: [Playlist] {
        var rng = SeededGenerator(seed: recommendationSeed &+ 31)
        return Array(playlists.shuffled(using: &rng).prefix(8))
    }

    private var recommendedTracks: [LocalTrack] {
        var rng = SeededGenerator(seed: recommendationSeed &+ 53)
        return Array(tracks.shuffled(using: &rng).prefix(12))
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 28) {
                header
                quickActions

                if let current = currentTrack {
                    continueListening(current)
                }

                let recent = recentlyPlayed.filter { $0.id != currentTrack?.id }
                if !recent.isEmpty {
                    section("Recently Played") {
                        horizontalTracks(Array(recent.prefix(12)))
                    }
                }

                if !recommendedAlbums.isEmpty {
                    section("Recommended Albums") {
                        horizontalAlbums(recommendedAlbums)
                    }
                }

                if !recommendedArtists.isEmpty {
                    section("Recommended Artists") {
                        horizontalArtists(recommendedArtists)
                    }
                }

                if !recommendedPlaylists.isEmpty {
                    section("For You") {
                        horizontalPlaylists(recommendedPlaylists)
                    }
                }

                if !recommendedTracks.isEmpty {
                    section("Recommended for You") {
                        horizontalTracks(recommendedTracks)
                    }
                }

                libraryOverview
            }
            .toyakoScreenPadding()
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.large)

    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Your Library")
                .font(ToyakoDesign.Typography.screenTitle)

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
                onShuffleAll()
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
                if currentTrack?.id == track.id {
                    onTogglePlayPause()
                } else if let index = tracks.firstIndex(where: { $0.id == track.id }) {
                    onPlayTrack(index)
                }
            } label: {
                HStack(spacing: 14) {
                    LazyArtwork(url: library.artworkURL(for: track), size: 68)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if currentTrack?.id == track.id {
                            Text(isPlaying ? "Playing now" : "Paused")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .background(.thinMaterial, in: Circle())
                }
                .padding(14)
                .toyakoCard()
            }
            .buttonStyle(.plain)
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ToyakoDesign.Metrics.itemSpacing) {
            ToyakoSectionHeader(title)
            content()
        }
    }

    private func horizontalTracks(_ items: [LocalTrack]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            // These sections are intentionally small (12 items max). A regular
            // HStack avoids the repeated child measurement/prefetch work of a
            // nested LazyHStack inside the vertical LazyVStack, which makes
            // scrolling and artwork arrival noticeably more stable.
            HStack(spacing: 14) {
                ForEach(items) { track in
                    Button {
                        if let index = tracks.firstIndex(where: { $0.id == track.id }) {
                            onPlayTrack(index)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            LazyArtwork(url: library.artworkURL(for: track), size: ToyakoArtworkSize.homeCard)
                            Text(track.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(track.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(width: ToyakoArtworkSize.homeCard, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func horizontalAlbums(_ items: [AlbumGroup]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(items) { album in
                    NavigationLink {
                        AlbumDetailView(album: album, library: library)
                            .navigationTitle(album.name)
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            LazyAlbumArtwork(url: album.artworkURL)
                                .frame(width: ToyakoArtworkSize.homeCard, height: ToyakoArtworkSize.homeCard)
                                .toyakoArtwork()
                            Text(album.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(album.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(width: ToyakoArtworkSize.homeCard, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func horizontalArtists(_ items: [ArtistGroup]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
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
                            ArtistArtworkView(artistName: artist.name, size: 100)

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
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func horizontalPlaylists(_ items: [Playlist]) -> some View {
        // Build the lookup once per Home body evaluation. The previous
        // implementation searched the entire library for every track URL in
        // every featured playlist (O(playlists × playlistTracks × libraryTracks)).
        // Home can therefore become disproportionately expensive to reconcile
        // when its overlay is dismissed on a large library.
        let tracksByURL = Dictionary(
            uniqueKeysWithValues: tracks.map {
                ($0.url.standardizedFileURL, $0)
            }
        )

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(items) { playlist in
                    let playlistTracks = playlist.trackURLs.compactMap { playlistURL in
                        tracksByURL[playlistURL.standardizedFileURL]
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
                            .frame(width: ToyakoArtworkSize.homeCard, height: ToyakoArtworkSize.homeCard)
                            .toyakoArtwork()

                            Text(playlist.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)

                            Text("\(playlistTracks.count) tracks")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: ToyakoArtworkSize.homeCard, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
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
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ToyakoSecondaryButtonStyle())
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
        .toyakoCard(cornerRadius: ToyakoDesign.Metrics.controlRadius)
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed ^ 0x9E3779B97F4A7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

