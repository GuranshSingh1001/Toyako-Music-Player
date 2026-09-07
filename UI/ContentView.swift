import SwiftUI
import Foundation
import UIKit

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
        // 1. Wrap the entire app in a ZStack for seamless overlay
        ZStack {
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
                        .searchable(text: $searchText, prompt: "Search songs, albums, artists")

                    if audioManager.currentTrack != nil {
                        MiniPlayerView()
                            .onTapGesture {
                                showNowPlaying = true // Triggers slide-up naturally
                            }
                            .padding(.bottom, 12)
                    }
                }
                .navigationTitle(titleForCategory())
                .toolbar {
                    if !searchText.isEmpty {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button {
                                searchText = ""
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                    Text("Back")
                                }
                                .font(.body.weight(.medium))
                            }
                        }
                    }

                    ToolbarItem(placement: .primaryAction) {
                        Button { showFilePicker = true } label: {
                            Image(systemName: "plus")
                        }
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        if searchText.isEmpty {
                            Button { library.reloadFiles() } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                    }
                }
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
            
            // 2. Direct ZStack Overlay (Replaces .fullScreenCover)
            if showNowPlaying {
                NowPlayingView(isPresented: $showNowPlaying)
                    .zIndex(2) // Ensures it sits perfectly on top without system transition glitches
            }
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
                let displayedPlaylistTracks = filterTracks(pTracks)

                VStack(spacing: 0) {
                    if searchText.isEmpty {
                        PlaylistHeaderView(
                            playlist: pl,
                            tracks: pTracks,
                            onAddSongs: { playlistToEdit = pl }
                        )
                    }
                    SongListView(tracks: displayedPlaylistTracks, allTracks: pTracks, library: library, playlistID: pl.id)
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

    private func filterTracks(_ source: [LocalTrack]) -> [LocalTrack] {
        if searchText.isEmpty { return source }
        return source.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.artist.localizedCaseInsensitiveContains(searchText) ||
            $0.album.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredTracks: [LocalTrack] {
        filterTracks(library.tracks)
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

// MARK: - Playlists & Utility Views

struct PlaylistHeaderView: View {
    let playlist: Playlist
    let tracks: [LocalTrack]
    let onAddSongs: () -> Void
    @EnvironmentObject var audioManager: AudioEngineManager

    var body: some View {
        HStack(spacing: 24) {
            playlistArtwork
                .frame(width: 130, height: 130)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.3), radius: 10, y: 5)

            VStack(alignment: .leading, spacing: 8) {
                Text("PLAYLIST")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                Text(playlist.name)
                    .font(.title.bold())
                    .lineLimit(1)

                Text("\(tracks.count) Songs • \(totalDurationString)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Button {
                        if !tracks.isEmpty {
                            audioManager.startQueue(tracks: tracks, startIndex: 0)
                        }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        if !tracks.isEmpty {
                            if !audioManager.isShuffle {
                                audioManager.toggleShuffle()
                            }
                            audioManager.startQueue(tracks: tracks, startIndex: 0)
                        }
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.bordered)

                    Button(action: onAddSongs) {
                        Label("Add Songs", systemImage: "plus.circle")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 4)
            }
            Spacer()
        }
        .padding(20)
    }

    @ViewBuilder
    private var playlistArtwork: some View {
        let arts = tracks.compactMap { $0.artworkData }
        if arts.count >= 4 {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    artSquare(data: arts[0])
                    artSquare(data: arts[1])
                }
                HStack(spacing: 0) {
                    artSquare(data: arts[2])
                    artSquare(data: arts[3])
                }
            }
        } else if let first = arts.first {
            artSquare(data: first)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .overlay(
                    Image(systemName: "music.note.list")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                )
        }
    }

    private func artSquare(data: Data) -> some View {
        Group {
            if let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.gray.opacity(0.3)
            }
        }
    }

    private var totalDurationString: String {
        let total = tracks.reduce(0) { $0 + $1.duration }
        let mins = Int(total) / 60
        return "\(mins) mins"
    }
}

struct PlaylistAddSongsSheet: View {
    let playlist: Playlist
    let library: LocalLibrary
    @Environment(\.dismiss) var dismiss
    @State private var selectedURLs: Set<URL> = []
    @State private var navigationPath: [URL] = []

    private var rootDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            FolderBrowserView(
                currentURL: rootDirectory,
                rootURL: rootDirectory,
                library: library,
                selectedURLs: $selectedURLs,
                onNavigate: { folderURL in
                    navigationPath.append(folderURL)
                }
            )
            .navigationDestination(for: URL.self) { folderURL in
                FolderBrowserView(
                    currentURL: folderURL,
                    rootURL: rootDirectory,
                    library: library,
                    selectedURLs: $selectedURLs,
                    onNavigate: { nextURL in
                        navigationPath.append(nextURL)
                    }
                )
            }
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done (\(selectedURLs.count))") {
                        library.addTracksToPlaylist(playlistID: playlist.id, trackURLs: Array(selectedURLs))
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .onAppear {
            selectedURLs = Set(playlist.trackURLs)
        }
    }
}

struct FolderBrowserView: View {
    let currentURL: URL
    let rootURL: URL
    let library: LocalLibrary
    @Binding var selectedURLs: Set<URL>
    let onNavigate: (URL) -> Void

    enum SelectionState {
        case none, partial, all
    }

    struct SubfolderInfo: Identifiable {
        var id: URL { url }
        let name: String
        let url: URL
        let allTracks: [LocalTrack]
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.blue)
                        Text(breadcrumbPath)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if !allTracksUnderCurrent.isEmpty {
                        HStack {
                            Text("\(allTracksUnderCurrent.count) total songs")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer()

                            Button(allCurrentSelected ? "Deselect All" : "Select All in Folder") {
                                toggleCurrentFolder()
                            }
                            .font(.caption.bold())
                            .buttonStyle(.bordered)
                            .tint(allCurrentSelected ? .red : .blue)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            if !subfolders.isEmpty {
                Section("Folders") {
                    ForEach(subfolders) { folder in
                        HStack(spacing: 12) {
                            Button {
                                onNavigate(folder.url)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "folder.fill")
                                        .font(.title3)
                                        .foregroundColor(.accentColor)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(folder.name)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Text("\(folder.allTracks.count) songs")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.bold())
                                        .foregroundColor(Color(UIColor.tertiaryLabel))
                                }
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .frame(height: 24)

                            Button {
                                toggleFolder(folder)
                            } label: {
                                Image(systemName: folderStateIcon(for: folder))
                                    .font(.title3)
                                    .foregroundColor(folderStateColor(for: folder))
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if !directTracks.isEmpty {
                Section("Songs") {
                    ForEach(directTracks) { track in
                        HStack(spacing: 12) {
                            if let data = track.artworkData, let img = UIImage(data: data) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 40, height: 40)
                                    .cornerRadius(6)
                            } else {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Image(systemName: "music.note")
                                            .foregroundColor(.gray)
                                    )
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .font(.subheadline.bold())
                                    .lineLimit(1)
                                Text(track.artist)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Image(systemName: selectedURLs.contains(track.url) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundColor(selectedURLs.contains(track.url) ? .blue : .gray)
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
                }
            }

            if subfolders.isEmpty && directTracks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No audio files in this folder")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
    }

    private var breadcrumbPath: String {
        let rootPath = rootURL.standardizedFileURL.path
        let currPath = currentURL.standardizedFileURL.path
        if currPath == rootPath { return "Documents" }
        let relative = currPath.replacingOccurrences(of: rootPath, with: "")
        return "Documents" + relative.replacingOccurrences(of: "/", with: " / ")
    }

    private var allTracksUnderCurrent: [LocalTrack] {
        let currentPath = currentURL.standardizedFileURL.path
        return library.tracks.filter { track in
            let trackPath = track.url.standardizedFileURL.path
            return trackPath == currentPath || trackPath.hasPrefix(currentPath + "/")
        }
    }

    private var directTracks: [LocalTrack] {
        let currentPath = currentURL.standardizedFileURL.path
        return library.tracks.filter { track in
            track.url.deletingLastPathComponent().standardizedFileURL.path == currentPath
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var subfolders: [SubfolderInfo] {
        let currentPath = currentURL.standardizedFileURL.path
        var folderMap: [String: (URL, [LocalTrack])] = [:]

        for track in allTracksUnderCurrent {
            let trackPath = track.url.standardizedFileURL.path
            guard trackPath.hasPrefix(currentPath + "/") else { continue }
            let relative = String(trackPath.dropFirst(currentPath.count + 1))
            let components = relative.split(separator: "/")

            if components.count > 1 {
                let folderName = String(components[0])
                let folderURL = currentURL.appendingPathComponent(folderName).standardizedFileURL

                if folderMap[folderName] != nil {
                    folderMap[folderName]?.1.append(track)
                } else {
                    folderMap[folderName] = (folderURL, [track])
                }
            }
        }

        return folderMap.map { name, tuple in
            SubfolderInfo(name: name, url: tuple.0, allTracks: tuple.1)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var allCurrentSelected: Bool {
        guard !allTracksUnderCurrent.isEmpty else { return false }
        return allTracksUnderCurrent.allSatisfy { selectedURLs.contains($0.url) }
    }

    private func toggleCurrentFolder() {
        let urls = allTracksUnderCurrent.map { $0.url }
        if allCurrentSelected {
            for url in urls { selectedURLs.remove(url) }
        } else {
            for url in urls { selectedURLs.insert(url) }
        }
    }

    private func folderSelectionState(for folder: SubfolderInfo) -> SelectionState {
        let folderURLs = Set(folder.allTracks.map { $0.url })
        let intersection = folderURLs.intersection(selectedURLs)
        if intersection.isEmpty { return .none }
        if intersection.count == folderURLs.count { return .all }
        return .partial
    }

    private func folderStateIcon(for folder: SubfolderInfo) -> String {
        switch folderSelectionState(for: folder) {
        case .none: return "circle"
        case .partial: return "minus.circle.fill"
        case .all: return "checkmark.circle.fill"
        }
    }

    private func folderStateColor(for folder: SubfolderInfo) -> Color {
        switch folderSelectionState(for: folder) {
        case .none: return .gray
        case .partial, .all: return .blue
        }
    }

    private func toggleFolder(_ folder: SubfolderInfo) {
        let folderURLs = folder.allTracks.map { $0.url }
        let state = folderSelectionState(for: folder)
        if state == .all {
            for url in folderURLs { selectedURLs.remove(url) }
        } else {
            for url in folderURLs { selectedURLs.insert(url) }
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

            if audioManager.currentTrack != nil {
                Spacer(minLength: 70)
                    .listRowBackground(Color.clear)
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
            .padding(.bottom, audioManager.currentTrack != nil ? 70 : 0)
        }
    }
}

struct ArtistListView: View {
    let artists: [ArtistGroup]
    let library: LocalLibrary
    @EnvironmentObject var audioManager: AudioEngineManager

    var body: some View {
        List {
            ForEach(artists) { artist in
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

            if audioManager.currentTrack != nil {
                Spacer(minLength: 70)
                    .listRowBackground(Color.clear)
            }
        }
    }
}
