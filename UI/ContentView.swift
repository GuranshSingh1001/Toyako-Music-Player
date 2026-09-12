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
                homeContent
            }

            Tab(
                "Tracks",
                systemImage:
                    "music.note",
                value:
                    LibraryCategory.tracks
            ) {
                tabContent(
                    for: .tracks
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
        .transaction { transaction in
            // Do not add an implicit SwiftUI transition on top of iPadOS's
            // own Liquid Glass sidebar/pill transition. The extra animation
            // pass is what causes the glass to briefly warp when switching tabs.
            transaction.animation = nil
        }
        .overlay(alignment: .bottom) {
            // There is deliberately ONE mini-player for the entire app, rather
            // than one inside each tab's NavigationStack. That keeps the same
            // view instance alive while switching Home/Tracks/Albums/Artists/
            // Playlists, so the player cannot disappear for a frame and then
            // be recreated. Because this overlay is outside TabView, it also
            // remains above pushed playlist destinations.
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
            .frame(width: 670)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 7)
            .zIndex(10)
        }

        // MARK: - Now Playing

        .overlay {
            if showNowPlaying {
                NowPlayingView(
                    isPresented:
                        $showNowPlaying,
                )
                .ignoresSafeArea(.all)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom),
                        removal: .move(edge: .bottom)
                    )
                )
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
