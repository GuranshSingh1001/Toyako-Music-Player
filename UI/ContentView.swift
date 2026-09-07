import SwiftUI

enum LibraryCategory: Hashable {
    case songs
    case albums
    case artists
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
        NavigationSplitView {
            List(selection: $selectedCategory) {
                Section("Library") {
                    NavigationLink(value: LibraryCategory.songs) {
                        Label("Songs", systemImage: "music.note")
                    }
                    NavigationLink(value: LibraryCategory.albums) {
                        Label("Albums", systemImage: "square.stack")
                    }
                    NavigationLink(value: LibraryCategory.artists) {
                        Label("Artists", systemImage: "music.mic")
                    }
                }

                Section("Playlists") {
                    ForEach(library.playlists) { pl in
                        NavigationLink(value: LibraryCategory.playlist(pl.id)) {
                            Label(pl.name, systemImage: "music.note.list")
                        }
                    }
                    Button {
                        showNewPlaylistAlert = true
                    } label: {
                        Label("New Playlist...", systemImage: "plus")
                    }
                }

                Section("Status") {
                    Text(library.statusMessage)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Library")
        } detail: {
            ZStack(alignment: .bottom) {
                detailContent
                    .searchable(text: $searchText, prompt: "Search tracks, albums, artists")

                if audioManager.currentTrack != nil {
                    MiniPlayerView()
                        .onTapGesture { showNowPlaying = true }
                        .padding(.bottom, 12)
                }
            }
            .navigationTitle(titleForCategory())
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showFilePicker = true } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { library.reloadFiles() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showNowPlaying) {
            NowPlayingView()
        }
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
        .onAppear {
            library.reloadFiles()
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedCategory {
        case .songs, .none:
            SongListView(tracks: filteredTracks, allTracks: library.tracks, library: library)
        case .albums:
            AlbumGridView(albums: filteredAlbums, library: library)
        case .artists:
            ArtistListView(artists: filteredArtists, library: library)
        case .playlist(let id):
            if let pl = library.playlists.first(where: { $0.id == id }) {
                let pTracks = library.tracks.filter { pl.trackURLs.contains($0.url) }
                VStack(spacing: 0) {
                    HStack {
                        Button {
                            playlistToEdit = pl
                        } label: {
                            Label("Add Multiple Songs", systemImage: "text.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    SongListView(tracks: pTracks, allTracks: pTracks, library: library, playlistID: pl.id)
                }
            }
        }
    }

    private func titleForCategory() -> String {
        switch selectedCategory {
        case .songs, .none: return "Songs"
        case .albums: return "Albums"
        case .artists: return "Artists"
        case .playlist(let id): return library.playlists.first(where: { $0.id == id })?.name ?? "Playlist"
        }
    }

    private var filteredTracks: [LocalTrack] {
        if searchText.isEmpty { return library.tracks }
        return library.tracks.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.artist.localizedCaseInsensitiveContains(searchText) ||
            $0.album.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredAlbums: [AlbumGroup] {
        if searchText.isEmpty { return library.albums }
        return library.albums.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.artist.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredArtists: [ArtistGroup] {
        if searchText.isEmpty { return library.artists }
        return library.artists.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }
}

struct PlaylistAddSongsSheet: View {
    let playlist: Playlist
    let library: LocalLibrary
    @Environment(\.dismiss) var dismiss
    @State private var selectedURLs: Set<URL> = []

    var body: some View {
        NavigationStack {
            List(library.tracks) { track in
                HStack {
                    VStack(alignment: .leading) {
                        Text(track.title).font(.headline)
                        Text(track.artist).font(.subheadline).foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: selectedURLs.contains(track.url) ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selectedURLs.contains(track.url) ? .blue : .gray)
                        .font(.title3)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if selectedURLs.contains(track.url) {
                        selectedURLs.remove(track.url)
                    } else {
                        selectedURLs.insert(track.url)
                    }
                }
            }
            .navigationTitle("Add to \(playlist.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        library.addTracksToPlaylist(playlistID: playlist.id, trackURLs: Array(selectedURLs))
                        dismiss()
                    }
                }
            }
            .onAppear {
                selectedURLs = Set(playlist.trackURLs)
            }
        }
    }
}

struct SongListView: View {
    let tracks: [LocalTrack]
    let allTracks: [LocalTrack]
    let library: LocalLibrary
    var playlistID: UUID? = nil
    @EnvironmentObject var audioManager: AudioEngineManager

    var body: some View {
        List {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                HStack(spacing: 12) {
                    if let data = track.artworkData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .cornerRadius(6)
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 44, height: 44)
                            .overlay(Image(systemName: "music.note").foregroundColor(.gray))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text("\(track.artist) — \(track.album)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(formatTime(track.duration))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    audioManager.startQueue(tracks: allTracks, startIndex: index)
                }
                .contextMenu {
                    if let pID = playlistID {
                        Button(role: .destructive) {
                            library.removeTrackFromPlaylist(playlistID: pID, trackURL: track.url)
                        } label: {
                            Label("Remove from Playlist", systemImage: "trash")
                        }
                    }
                    Menu("Add to Playlist") {
                        ForEach(library.playlists) { pl in
                            Button(pl.name) {
                                library.addTracksToPlaylist(playlistID: pl.id, trackURLs: [track.url])
                            }
                        }
                    }
                }
            }
        }
    }

    private func formatTime(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

struct AlbumGridView: View {
    let albums: [AlbumGroup]
    let library: LocalLibrary
    @EnvironmentObject var audioManager: AudioEngineManager

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 20)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(albums) { album in
                    VStack(alignment: .leading, spacing: 8) {
                        if let data = album.artworkData, let img = UIImage(data: data) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 160, height: 160)
                                .cornerRadius(12)
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 160, height: 160)
                                .overlay(Image(systemName: "square.stack").font(.largeTitle).foregroundColor(.gray))
                        }
                        Text(album.name)
                            .font(.headline)
                            .lineLimit(1)
                        Text(album.artist)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .frame(width: 160)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        audioManager.startQueue(tracks: album.tracks, startIndex: 0)
                    }
                }
            }
            .padding()
        }
    }
}

struct ArtistListView: View {
    let artists: [ArtistGroup]
    let library: LocalLibrary

    var body: some View {
        List(artists) { artist in
            NavigationLink {
                SongListView(tracks: artist.tracks, allTracks: artist.tracks, library: library)
                    .navigationTitle(artist.name)
            } label: {
                HStack {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 48, height: 48)
                        .overlay(Image(systemName: "person.fill").foregroundColor(.secondary))
                    VStack(alignment: .leading) {
                        Text(artist.name)
                            .font(.headline)
                        Text("\(artist.tracks.count) Songs")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 6)
                }
            }
        }
    }
}
