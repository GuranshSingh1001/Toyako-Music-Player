import SwiftUI

struct AllPlaylistsGridView: View {
    let playlists: [Playlist]
    let library: LocalLibrary

    var onAddSongs: (Playlist) -> Void
    var onRename: (Playlist) -> Void

    @EnvironmentObject private var audioManager: AudioEngineManager
    @AppStorage(ToyakoPreferences.libraryArtworkSizeKey) private var libraryArtworkSize = 180.0

    private let columns = [
        GridItem(.adaptive(minimum: 180), spacing: 18)
    ]

    private var bleedArtworkURL: URL? {
        audioManager.currentTrack.flatMap { library.artworkURL(for: $0) }
            ?? playlists
                .first
                .flatMap { playlist in
                    library.tracks.first(where: { playlist.trackURLs.contains($0.url) })
                }
                .flatMap { library.artworkURL(for: $0) }
    }

    var body: some View {
        ZStack {
            ArtworkBleedPageBackground(artworkURL: bleedArtworkURL)

            GeometryReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    CenteredLibraryGrid(
                    items: playlists,
                    availableWidth: proxy.size.width - (ToyakoDesign.Metrics.screenHorizontal * 2),
                    minimumItemWidth: CGFloat(libraryArtworkSize) + 24,
                    rowSpacing: 24,
                    columnSpacing: 18
                ) { playlist in
                    let playlistTracks = library.tracks.filter {
                        playlist.trackURLs.contains($0.url)
                    }

                    NavigationLink {
                        PlaylistDetailView(
                            playlist: playlist,
                            tracks: playlistTracks,
                            library: library,
                            onAddSongs: { onAddSongs(playlist) }
                        )
                    } label: {
                        PlaylistCard(
                            playlist: playlist,
                            tracks: playlistTracks,
                            artworkSize: CGFloat(libraryArtworkSize)
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
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
                    }
                }
                .padding(.horizontal, ToyakoDesign.Metrics.screenHorizontal)
                .padding(.top, ToyakoDesign.Metrics.screenTop)
                .padding(.bottom, ToyakoDesign.Metrics.screenBottom + 24)
            }
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            }
        }
    }
}

// MARK: - Playlist Card

private struct PlaylistCard: View {
    let playlist: Playlist
    let tracks: [LocalTrack]
    let artworkSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            PlaylistArtwork(
                tracks: tracks,
                playlistName: playlist.name
            )
            .frame(
                width: artworkSize,
                height: artworkSize
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: ToyakoDesign.Metrics.artworkSmallRadius,
                    style: .continuous
                )
            )

            Text(playlist.name)
                .font(.headline)
                .lineLimit(1)

            Text(
                "\(tracks.count) " + (tracks.count == 1 ? "Song" : "Tracks")
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            HStack(spacing: 6) {
                Text("Playlist")
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(formatPlaylistDuration)
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .frame(width: artworkSize + 24, alignment: .leading)
        .toyakoCard(cornerRadius: ToyakoDesign.Metrics.cardRadius)
    }

    private var formatPlaylistDuration: String {
        let seconds = max(0, Int(tracks.reduce(0) { $0 + $1.duration }.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
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


// MARK: - Playlist Detail

struct PlaylistDetailView: View {
    let playlist: Playlist
    let tracks: [LocalTrack]
    let library: LocalLibrary
    let onAddSongs: () -> Void

    @EnvironmentObject private var audioManager: AudioEngineManager

    // Use the exact same artwork-selection rule as the Playlists page so the
    // bleed does not visually change when navigating into a playlist.
    private var bleedArtworkURL: URL? {
        audioManager.currentTrack.flatMap { library.artworkURL(for: $0) }
            ?? tracks.first.flatMap { library.artworkURL(for: $0) }
    }

    var body: some View {
        ZStack {
            ArtworkBleedPageBackground(artworkURL: bleedArtworkURL)

            SongListView(
                tracks: tracks,
                allTracks: tracks,
                library: library,
                playlistID: playlist.id,
                headerView: AnyView(
                    PlaylistHeaderView(
                        playlist: playlist,
                        tracks: tracks,
                        library: library,
                        onAddSongs: onAddSongs
                    )
                )
            )
        }
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
