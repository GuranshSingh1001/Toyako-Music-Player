import SwiftUI
import Foundation

enum LibraryCategory: Hashable {
    case home
    case tracks
    case albums
    case artists
    case allPlaylists
}



struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var library =
        LocalLibrary()

    @State private var
        selectedCategory:
            LibraryCategory? = .home

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
                "Home",
                systemImage:
                    "house",
                value:
                    LibraryCategory.home
            ) {
                tabDestination {
                    homeContent
                }
            }

            Tab(
                "Tracks",
                systemImage:
                    "music.note",
                value:
                    LibraryCategory.tracks
            ) {
                tabDestination {
                    tabContent(
                        for: .tracks
                    )
                }
            }

            Tab(
                "Albums",
                systemImage:
                    "square.stack",
                value:
                    LibraryCategory.albums
            ) {
                tabDestination {
                    tabContent(
                        for: .albums
                    )
                }
            }

            Tab(
                "Artists",
                systemImage:
                    "music.mic",
                value:
                    LibraryCategory.artists
            ) {
                tabDestination {
                    tabContent(
                        for: .artists
                    )
                }
            }

            Tab(
                "Playlists",
                systemImage:
                    "square.grid.2x2",
                value:
                    LibraryCategory.allPlaylists
            ) {
                tabDestination {
                    tabContent(
                        for: .allPlaylists
                    )
                }
            }
        }
        .tabViewStyle(
            .sidebarAdaptable
        )
        // The mini-player belongs to the tab destination, not to the outer
        // TabView. This is important for sidebarAdaptable: when the sidebar
        // opens/closes, SwiftUI animates the destination's frame. Because the
        // player is inside that destination, it follows the same slide instead
        // of remaining pinned to the window center.


        // MARK: - Now Playing

        .overlay {
            if showNowPlaying {
                NowPlayingView(
                    isPresented:
                        $showNowPlaying,
                )
                .ignoresSafeArea(.all)
                // NowPlayingView owns its dismissal animation by moving its
                // own surface off-screen. Do not apply a second parent removal
                // transition here: on Home, that extra transition forces the
                // large nested ScrollView/LazyVStack hierarchy to be reconciled
                // while the full-screen player is already animating away.
                .zIndex(100)
            }
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
        .overlay {
            AudioLifecycleObserver(library: library, scenePhase: scenePhase)
                .frame(width: 0, height: 0)
        }
    }

    @ViewBuilder
    private func tabDestination<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .overlay(alignment: .bottom) {
                GeometryReader { proxy in
                    let isCompactWindow = proxy.size.width <= 600
                    let horizontalInset: CGFloat = proxy.size.width <= 700 ? 10 : 0
                    let availableWidth = max(0, proxy.size.width - (horizontalInset * 2))
                    let playerWidth = min(670, availableWidth)

                    // When the window becomes narrow enough for the adaptable
                    // sidebar to collapse into the bottom tab bar, keep the
                    // mini-player above that bar instead of letting the two
                    // surfaces overlap. The extra inset is intentionally only
                    // enabled at the compact breakpoint so the normal iPad
                    // layout remains unchanged.
                    let bottomInset: CGFloat = isCompactWindow ? 72 : 7

                    MiniPlayerView(
                        isNowPlayingPresented: showNowPlaying,
                        onOpenNowPlaying: {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                                showNowPlaying = true
                            }
                        }
                    )
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .shadow(color: .black.opacity(0.10), radius: 15, y: 8)
                    .frame(width: playerWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, horizontalInset)
                    .padding(.bottom, bottomInset)
                }
                .zIndex(10)
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
    }

    // MARK: - Home

    private var homeContent: some View {
        NavigationStack {
            HomeAudioContainer(
                tracks: library.tracks,
                albums: library.albums,
                artists: library.artists,
                playlists: library.playlists,
                library: library,
                onImport: {
                    showFilePicker = true
                },
                onNewPlaylist: {
                    showNewPlaylistAlert = true
                }
            )
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showFilePicker = true
                        } label: {
                            Label("Import Audio", systemImage: "folder.badge.plus")
                        }

                        Button {
                            showNewPlaylistAlert = true
                        } label: {
                            Label("New Playlist", systemImage: "plus.rectangle.on.rectangle")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        library.reloadFiles()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh library")
                }
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

        case .home:
            homeContent

        case .tracks:
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

        case .home:
            return "Home"

        case .tracks, .none:
            return "Tracks"

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

private struct HomeAudioContainer: View {
    let tracks: [LocalTrack]
    let albums: [AlbumGroup]
    let artists: [ArtistGroup]
    let playlists: [Playlist]
    let library: LocalLibrary
    let onImport: () -> Void
    let onNewPlaylist: () -> Void

    @EnvironmentObject private var audioManager: AudioEngineManager

    var body: some View {
        HomeView(
            tracks: tracks,
            albums: albums,
            artists: artists,
            playlists: playlists,
            library: library,
            onImport: onImport,
            onNewPlaylist: onNewPlaylist,
            currentTrack: audioManager.currentTrack,
            isPlaying: audioManager.isPlaying,
            onPlayTrack: { index in
                audioManager.startQueue(tracks: tracks, startIndex: index)
            },
            onTogglePlayPause: {
                audioManager.togglePlayPause()
            },
            onShuffleAll: {
                guard !tracks.isEmpty else { return }
                let index = Int.random(in: tracks.indices)
                if !audioManager.isShuffle {
                    audioManager.toggleShuffle()
                }
                audioManager.startQueue(tracks: tracks, startIndex: index)
            }
        )
    }
}

private struct AudioLifecycleObserver: View {
    let library: LocalLibrary
    let scenePhase: ScenePhase

    @EnvironmentObject private var audioManager: AudioEngineManager

    var body: some View {
        Color.clear
            .onAppear {
                synchronize()
            }
            .onChange(of: library.tracks) { _, tracks in
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

    private func synchronize() {
        audioManager.restoreIfPossible(from: library.tracks)
        audioManager.synchronizeLibrary(library.tracks)
        if let current = audioManager.currentTrack {
            library.refreshArtwork(for: current)
        }
    }
}
