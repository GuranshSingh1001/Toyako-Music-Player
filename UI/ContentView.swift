import SwiftUI
import Foundation

enum LibraryCategory: Hashable {
    case songs
    case albums
    case artists
    case allPlaylists
    case playlist(UUID)
}

struct ContentView: View {
    @EnvironmentObject var audioManager: AudioEngineManager
    @StateObject private var library = LocalLibrary()

    @State private var selectedCategory: LibraryCategory? = .songs
    @State private var showFilePicker = false
    @State private var showNowPlaying = false
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var searchText = ""
    @State private var playlistToEdit: Playlist?

    var body: some View {
        TabView(selection: $selectedCategory) {
            Tab("Songs", systemImage: "music.note", value: LibraryCategory.songs) {
                tabContent(for: .songs)
            }
            
            Tab("Albums", systemImage: "square.stack", value: LibraryCategory.albums) {
                tabContent(for: .albums)
            }
            
            Tab("Artists", systemImage: "music.mic", value: LibraryCategory.artists) {
                tabContent(for: .artists)
            }
            
            Tab("Playlists", systemImage: "square.grid.2x2", value: LibraryCategory.allPlaylists) {
                tabContent(for: .allPlaylists)
            }
            
            TabSection("My Playlists") {
                ForEach(library.playlists) { pl in
                    Tab(pl.name, systemImage: "music.note.list", value: LibraryCategory.playlist(pl.id)) {
                        tabContent(for: .playlist(pl.id))
                    }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // 1. Completely removes the view from hierarchy when false, allowing taps to pass through to the miniplayer
        .overlay {
            if showNowPlaying {
                NowPlayingView(isPresented: $showNowPlaying)
                    .transition(.move(edge: .bottom))
                    .ignoresSafeArea()
                    .zIndex(2)
            }
        }
        .animation(.interpolatingSpring(stiffness: 300, damping: 30), value: showNowPlaying)
        .sheet(isPresented: $showFilePicker) {
            DocumentPicker { urls in
                library.importExternalURLs(urls)
            }
        }
        .sheet(item: $playlistToEdit) { playlist in
            PlaylistAddSongsSheet(playlist: playlist, library: library)
        }
        .alert("Create Playlist", isPresented: $showNewPlaylistAlert) {
            TextField("Playlist Name", text: $newPlaylistName)
            Button("Cancel", role: .cancel) { newPlaylistName = "" }
            Button("Create") {
                if !newPlaylistName.isEmpty {
                    library.createPlaylist(name: newPlaylistName)
                    newPlaylistName = ""
                }
            }
        }
        .keyboardShortcut(" ", modifiers: [])
    }

    @ViewBuilder
    private func tabContent(for category: LibraryCategory) -> some View {
        NavigationStack {
            detailContent(for: category)
                .searchable(text: $searchText, prompt: "Search library")
                .navigationTitle(titleForCategory(category))
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button { showFilePicker = true } label: { Label("Import Audio", systemImage: "folder.badge.plus") }
                            Button { showNewPlaylistAlert = true } label: { Label("New Playlist", systemImage: "plus.rectangle.on.rectangle") }
                        } label: { Image(systemName: "plus") }
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        if searchText.isEmpty {
                            Button { library.reloadFiles() } label: { Image(systemName: "arrow.clockwise") }
                        }
                    }
                }
        }
        .safeAreaInset(edge: .bottom) {
            if audioManager.currentTrack != nil {
                MiniPlayerView()
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .shadow(color: .black.opacity(0.2), radius: 15, y: 8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showNowPlaying = true
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private func detailContent(for category: LibraryCategory) -> some View {
        switch category {
        case .songs:
            SongListView(tracks: filteredTracks, allTracks: library.tracks, library: library)
        case .albums:
            AlbumGridView(albums: filteredAlbums, library: library)
        case .artists:
            ArtistListView(artists: filteredArtists, library: library)
        case .allPlaylists:
            // 2. Pass down an action instead of mutating selectedCategory directly
            AllPlaylistsGridView(
                playlists: library.playlists, 
                library: library, 
                onEditPlaylist: { pl in playlistToEdit = pl }
            )
        case .playlist(let id):
            if let pl = library.playlists.first(where: { $0.id == id }) {
                let pTracks = library.tracks.filter { pl.trackURLs.contains($0.url) }
                let displayedPlaylistTracks = filterTracks(pTracks)

                SongListView(
                    tracks: displayedPlaylistTracks,
                    allTracks: pTracks,
                    library: library,
                    playlistID: pl.id,
                    headerView: searchText.isEmpty ? AnyView(
                        PlaylistHeaderView(
                            playlist: pl,
                            tracks: pTracks,
                            onAddSongs: { playlistToEdit = pl }
                        )
                    ) : nil
                )
            }
        }
    }

    private func titleForCategory(_ category: LibraryCategory?) -> String {
        switch category {
        case .songs, .none: return "Songs"
        case .albums: return "Albums"
        case .artists: return "Artists"
        case .allPlaylists: return "All Playlists"
        case .playlist(let id): return library.playlists.first(where: { $0.id == id })?.name ?? "Playlist"
        }
    }

    private func filterTracks(_ source: [LocalTrack]) -> [LocalTrack] {
        if searchText.isEmpty { return source }
        return source.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.artist.localizedCaseInsensitiveContains(searchText) ||
            $0.album.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredTracks: [LocalTrack] { filterTracks(library.tracks) }
    private var filteredAlbums: [AlbumGroup] {
        if searchText.isEmpty { return library.albums }
        return library.albums.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.artist.localizedCaseInsensitiveContains(searchText) }
    }
    private var filteredArtists: [ArtistGroup] {
        if searchText.isEmpty { return library.artists }
        return library.artists.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}
