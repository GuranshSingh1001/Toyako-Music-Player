import SwiftUI
import Foundation

enum LibraryCategory: Hashable {
    case songs
    case albums
    case artists
    case allPlaylists
}



struct ContentView: View {
    @EnvironmentObject var audioManager:
        AudioEngineManager

    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var library =
        LocalLibrary()

    @State private var
        selectedCategory:
            LibraryCategory? = .songs

    @State private var
        showFilePicker = false

    @State private var
        showNowPlaying = false

    @State private var
        showNewPlaylistAlert = false

    @State private var
        newPlaylistName = ""

    @State private var
        searchText = ""

    @State private var
        playlistToEdit:
            Playlist?

    @State private var
        playlistToRename:
            Playlist?

    @State private var
        renameText = ""

    var body: some View {
        TabView(
            selection:
                $selectedCategory
        ) {

            Tab(
                "Songs",
                systemImage:
                    "music.note",
                value:
                    LibraryCategory.songs
            ) {
                tabContent(
                    for: .songs
                )
            }

            Tab(
                "Albums",
                systemImage:
                    "square.stack",
                value:
                    LibraryCategory.albums
            ) {
                tabContent(
                    for: .albums
                )
            }

            Tab(
                "Artists",
                systemImage:
                    "music.mic",
                value:
                    LibraryCategory.artists
            ) {
                tabContent(
                    for: .artists
                )
            }

            Tab(
                "Playlists",
                systemImage:
                    "square.grid.2x2",
                value:
                    LibraryCategory.allPlaylists
            ) {
                tabContent(
                    for: .allPlaylists
                )
            }
        }
        .tabViewStyle(
            .sidebarAdaptable
        )

        // MARK: - Now Playing
        //
        // IMPORTANT:
        // Do not put Now Playing in an overlay on this root view.
        // An overlay that also hides the status bar changes the root
        // safe-area geometry, which causes sidebarAdaptable/NavigationStack
        // to recalculate and visibly jitter.
        //
        // A full-screen cover is a separate presentation layer. The library
        // underneath keeps its exact geometry while Now Playing takes over
        // the screen. This removes the root-layout resize entirely.
        .fullScreenCover(
            isPresented:
                $showNowPlaying
        ) {
            NowPlayingView(
                isPresented:
                    $showNowPlaying
            )
            .ignoresSafeArea(.all)
        }

        // MARK: - Import

        .sheet(
            isPresented:
                $showFilePicker
        ) {
            DocumentPicker { urls in
                library.importExternalURLs(
                    urls
                )
            }
        }

        // MARK: - Playlist Editing

        .sheet(
            item:
                $playlistToEdit
        ) { playlist in
            PlaylistAddSongsSheet(
                playlist:
                    playlist,
                library:
                    library
            )
        }

        .alert(
            "Create Playlist",
            isPresented:
                $showNewPlaylistAlert
        ) {
            TextField(
                "Playlist Name",
                text:
                    $newPlaylistName
            )

            Button(
                "Cancel",
                role:
                    .cancel
            ) {
                newPlaylistName =
                    ""
            }

            Button("Create") {
                let name =
                    newPlaylistName
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )

                guard !name.isEmpty
                else {
                    return
                }

                library.createPlaylist(
                    name:
                        name
                )

                newPlaylistName =
                    ""
            }
        }

        .alert(
            "Rename Playlist",
            isPresented:
                Binding(
                    get: {
                        playlistToRename
                            != nil
                    },
                    set: {
                        if !$0 {
                            playlistToRename =
                                nil
                        }
                    }
                )
        ) {
            TextField(
                "New Name",
                text:
                    $renameText
            )

            Button(
                "Cancel",
                role:
                    .cancel
            ) {
                playlistToRename =
                    nil
            }

            Button("Save") {
                let name =
                    renameText
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )

                if let playlist =
                    playlistToRename,
                   !name.isEmpty {

                    library.renamePlaylist(
                        id:
                            playlist.id,
                        newName:
                            name
                    )
                }

                playlistToRename =
                    nil
            }
        }
        .onAppear {
            audioManager.restoreIfPossible(from: library.tracks)
            audioManager.synchronizeLibrary(library.tracks)
            if let current = audioManager.currentTrack {
                library.refreshArtwork(for: current)
            }
        }
        .onChange(of: library.tracks) { _, tracks in
            // First restore playback from the cache, then refresh it with the
            // fully scanned metadata/artwork. The cache intentionally has no artwork.
            audioManager.restoreIfPossible(from: tracks)
            audioManager.synchronizeLibrary(tracks)
            if let current = audioManager.currentTrack {
                library.refreshArtwork(for: current)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                audioManager.savePlaybackState(force: true)
            }
        }
    }

    // MARK: - Tab

    @ViewBuilder
    private func tabContent(
        for category:
            LibraryCategory
    ) -> some View {

        NavigationStack {
            detailContent(
                for:
                    category
            )
            .searchable(
                text:
                    $searchText,
                prompt:
                    "Search library"
            )
            .navigationTitle(
                titleForCategory(
                    category
                )
            )
            .toolbar {

                ToolbarItem(
                    placement:
                        .primaryAction
                ) {
                    Menu {

                        Button {
                            showFilePicker =
                                true
                        } label: {
                            Label(
                                "Import Audio",
                                systemImage:
                                    "folder.badge.plus"
                            )
                        }

                        Button {
                            showNewPlaylistAlert =
                                true
                        } label: {
                            Label(
                                "New Playlist",
                                systemImage:
                                    "plus.rectangle.on.rectangle"
                            )
                        }

                    } label: {
                        Image(
                            systemName:
                                "plus"
                        )
                    }
                }

                ToolbarItem(
                    placement:
                        .navigationBarLeading
                ) {
                    if searchText.isEmpty {
                        Button {
                            library.reloadFiles()
                        } label: {
                            Image(
                                systemName:
                                    "arrow.clockwise"
                            )
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            // Exactly one mini-player is installed: only the selected tab owns
            // the inset. Its width is fixed, so the sidebar can only move it;
            // it cannot stretch or create a second copy.
            if selectedCategory == category && audioManager.currentTrack != nil {
                GeometryReader { proxy in
                    ZStack {
                        MiniPlayerView {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                                showNowPlaying = true
                            }
                        }
                        .frame(width: 670, height: 55)
                        .glassEffect(
                            .regular.interactive(),
                            in: .capsule
                        )
                        .shadow(
                            color: .black.opacity(0.15),
                            radius: 12,
                            y: 6
                        )
                    }
                    .frame(width: proxy.size.width, height: 55, alignment: .center)
                    .transaction { transaction in
                        transaction.animation = .smooth(duration: 0.30)
                    }
                }
                .frame(height: 59)
                .padding(.bottom, 6)
            }
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private func detailContent(
        for category:
            LibraryCategory
    ) -> some View {

        switch category {

        case .songs:
            SongListView(
                tracks:
                    filteredTracks,
                allTracks:
                    library.tracks,
                library:
                    library
            )

        case .albums:
            AlbumGridView(
                albums:
                    filteredAlbums,
                library:
                    library
            )

        case .artists:
            ArtistListView(
                artists:
                    filteredArtists,
                library:
                    library
            )

        case .allPlaylists:
            AllPlaylistsGridView(
                playlists:
                    library.playlists,
                library:
                    library,
                onAddSongs: {
                    playlistToEdit =
                        $0
                },
                onRename: {
                    renameText =
                        $0.name

                    playlistToRename =
                        $0
                }
            )
        }
    }

    private func titleForCategory(
        _ category:
            LibraryCategory?
    ) -> String {

        switch category {

        case .songs, .none:
            return "Songs"

        case .albums:
            return "Albums"

        case .artists:
            return "Artists"

        case .allPlaylists:
            return "All Playlists"
        }
    }

    // MARK: - Search

    private func filterTracks(
        _ source:
            [LocalTrack]
    ) -> [LocalTrack] {

        guard !searchText.isEmpty
        else {
            return source
        }

        return source.filter {
            $0.title
                .localizedCaseInsensitiveContains(
                    searchText
                )
            ||
            $0.artist
                .localizedCaseInsensitiveContains(
                    searchText
                )
            ||
            $0.album
                .localizedCaseInsensitiveContains(
                    searchText
                )
        }
    }

    private var filteredTracks:
        [LocalTrack] {
        filterTracks(
            library.tracks
        )
    }

    private var filteredAlbums:
        [AlbumGroup] {

        guard !searchText.isEmpty
        else {
            return library.albums
        }

        return library.albums.filter {
            $0.name
                .localizedCaseInsensitiveContains(
                    searchText
                )
            ||
            $0.artist
                .localizedCaseInsensitiveContains(
                    searchText
                )
        }
    }

    private var filteredArtists:
        [ArtistGroup] {

        guard !searchText.isEmpty
        else {
            return library.artists
        }

        return library.artists.filter {
            $0.name
                .localizedCaseInsensitiveContains(
                    searchText
                )
        }
    }
}