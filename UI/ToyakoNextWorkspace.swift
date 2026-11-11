import SwiftUI

enum ToyakoNextDestination: String, CaseIterable, Identifiable {
    case home
    case tracks
    case albums
    case artists
    case playlists
    case statistics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Overview"
        case .tracks: "Tracks"
        case .albums: "Albums"
        case .artists: "Artists"
        case .playlists: "Playlists"
        case .statistics: "Statistics"
        }
    }

    var symbol: String {
        switch self {
        case .home: "square.grid.2x2"
        case .tracks: "music.note.list"
        case .albums: "square.stack"
        case .artists: "person.2"
        case .playlists: "text.line.first.and.arrowtriangle.forward"
        case .statistics: "chart.bar"
        }
    }
}

/// iPad-first workspace for Toyako Next. Classic remains implemented by the
/// original TabView and its original destination hierarchy.
struct ToyakoNextWorkspace: View {
    let library: LocalLibrary
    let onImport: () -> Void
    let onNewPlaylist: () -> Void
    let onEditPlaylist: (Playlist) -> Void
    let onRenamePlaylist: (Playlist) -> Void
    let onSettings: () -> Void
    let onOpenNowPlaying: () -> Void
    let onRefresh: () -> Void

    @EnvironmentObject private var audioManager: AudioEngineManager
    @State private var selection: ToyakoNextDestination? = .home
    @State private var searchText = ""
    @State private var isQueueVisible = true
    @State private var isCompactLayout = false
    @State private var showCompactQueue = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var filteredTracks: [LocalTrack] {
        SmartLibrarySearch.rank(library.tracks, query: searchText)
    }

    private var filteredAlbums: [AlbumGroup] {
        guard !searchText.isEmpty else { return library.albums }
        return library.albums.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.artist.localizedCaseInsensitiveContains(searchText)
                || !SmartLibrarySearch.rank($0.tracks, query: searchText).isEmpty
        }
    }

    private var filteredArtists: [ArtistGroup] {
        guard !searchText.isEmpty else { return library.artists }
        return library.artists.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 238, max: 280)
        } detail: {
            NavigationStack {
                GeometryReader { detailGeometry in
                    HStack(spacing: 0) {
                        mainWorkspace
                        // Keep the queue beside the workspace on wide iPad
                        // layouts; let it become a summoned panel in portrait
                        // and compact Stage Manager windows.
                        if isQueueVisible && detailGeometry.size.width >= 880 {
                            Rectangle()
                                .fill(ToyakoDesign.Color.divider)
                                .frame(width: 1)
                            ToyakoNextQueuePanel()
                                .frame(minWidth: 250, idealWidth: 292, maxWidth: 360)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .background(ToyakoDesign.Color.canvas)
                    .onAppear { isCompactLayout = detailGeometry.size.width < 880 }
                    .onChange(of: detailGeometry.size.width) { _, width in
                        isCompactLayout = width < 880
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.24)) {
                                columnVisibility = columnVisibility == .all ? .detailOnly : .all
                            }
                        } label: {
                            Image(systemName: "sidebar.left")
                        }
                        .accessibilityLabel("Toggle sidebar")
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button(action: onRefresh) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Refresh library")
                        Button {
                            if isCompactLayout {
                                showCompactQueue = true
                            } else {
                                withAnimation(.easeInOut(duration: 0.24)) {
                                    isQueueVisible.toggle()
                                }
                            }
                        } label: {
                            Image(systemName: "sidebar.right")
                        }
                        .accessibilityLabel(isQueueVisible ? "Show queue" : "Show queue")
                        Button(action: onSettings) {
                            Image(systemName: "slider.horizontal.3")
                        }
                        .accessibilityLabel("Settings")
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(ToyakoDesign.Color.accent)
        .background(ToyakoDesign.Color.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ToyakoNextMiniPlayer(onOpen: onOpenNowPlaying)
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
                .padding(.top, 8)
        }
        .animation(.easeInOut(duration: 0.22), value: isQueueVisible)
        .sheet(isPresented: $showCompactQueue) {
            NavigationStack {
                ToyakoNextQueuePanel()
                    .navigationTitle("Queue")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showCompactQueue = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: searchText) { _, value in
            if !value.isEmpty && selection == .home {
                selection = .tracks
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toyakoCommandNavigate)) { notification in
            guard let destination = notification.object as? String else { return }
            switch destination {
            case "home": selection = .home
            case "tracks": selection = .tracks
            case "albums": selection = .albums
            case "artists": selection = .artists
            case "playlists": selection = .playlists
            default: break
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "waveform")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("TOYAKO")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .tracking(1.5)
                    Text("Music workspace")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 24)

            List(selection: $selection) {
                Section("WORKSPACE") {
                    ForEach([ToyakoNextDestination.home, .tracks, .albums, .artists, .playlists]) { destination in
                        Label(destination.title, systemImage: destination.symbol)
                            .tag(destination)
                    }
                }
                Section("INSIGHTS") {
                    Label(ToyakoNextDestination.statistics.title, systemImage: ToyakoNextDestination.statistics.symbol)
                        .tag(ToyakoNextDestination.statistics)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            VStack(spacing: 8) {
                Button(action: onImport) {
                    Label("Import music", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ToyakoPrimaryButtonStyle())

                HStack {
                    Text("\(library.tracks.count.formatted()) tracks")
                    Spacer()
                    Text(library.statusMessage)
                        .lineLimit(1)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(14)
        }
        .background(ToyakoDesign.Color.surface.opacity(0.55))
    }

    private var mainWorkspace: some View {
        VStack(alignment: .leading, spacing: 0) {
            workspaceHeader
            ScrollView {
                Group {
                    switch activeDestination {
                    case .home:
                        overview
                    case .tracks:
                        TrackGridView(tracks: filteredTracks, library: library)
                    case .albums:
                        AlbumGridView(albums: filteredAlbums, library: library)
                    case .artists:
                        ArtistListView(artists: filteredArtists, library: library)
                    case .playlists:
                        AllPlaylistsGridView(
                            playlists: library.playlists,
                            library: library,
                            onAddSongs: onEditPlaylist,
                            onRename: onRenamePlaylist
                        )
                    case .statistics:
                        statistics
                    }
                }
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var workspaceHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(activeDestination.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .tracking(-0.7)
                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search your music", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 13)
            .frame(maxWidth: 320)
            .frame(height: 42)
            .background(ToyakoDesign.Color.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(ToyakoDesign.Color.divider, lineWidth: 1)
            }
            Button(action: onNewPlaylist) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(ToyakoDesign.Color.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create playlist")
        }
        .padding(.horizontal, 26)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    private var activeDestination: ToyakoNextDestination { selection ?? .home }

    private var headerSubtitle: String {
        switch activeDestination {
        case .home: "\(library.tracks.count.formatted()) tracks in your collection"
        case .tracks: "Your complete local collection"
        case .albums: "\(library.albums.count.formatted()) albums"
        case .artists: "\(library.artists.count.formatted()) artists"
        case .playlists: "\(library.playlists.count.formatted()) playlists"
        case .statistics: "A closer look at your listening"
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 12) {
                NextMetric(value: library.tracks.count, title: "Tracks", symbol: "music.note")
                NextMetric(value: library.albums.count, title: "Albums", symbol: "square.stack")
                NextMetric(value: library.artists.count, title: "Artists", symbol: "person.2")
                NextMetric(value: library.playlists.count, title: "Playlists", symbol: "text.line.first.and.arrowtriangle.forward")
            }

            if !audioManager.recentlyPlayed.isEmpty {
                NextSectionHeader(title: "Recently played", detail: "PICK UP WHERE YOU LEFT OFF")
                VStack(spacing: 2) {
                    ForEach(Array(audioManager.recentlyPlayed.prefix(8).enumerated()), id: \.element.id) { index, track in
                        NextTrackRow(track: track, artworkURL: library.artworkURL(for: track), active: audioManager.currentTrack?.id == track.id) {
                            audioManager.playStandalonePreservingQueue(track)
                        }
                    }
                }
            }

            if !library.albums.isEmpty {
                NextSectionHeader(title: "Your albums", detail: "THE COLLECTION")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 16)], alignment: .leading, spacing: 18) {
                    ForEach(library.albums.prefix(12)) { album in
                        NavigationLink {
                            AlbumDetailView(album: album, library: library)
                                .navigationTitle(album.name)
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                LazyAlbumArtwork(url: album.artworkURL, cornerRadius: 12)
                                    .aspectRatio(1, contentMode: .fit)
                                    .frame(maxWidth: .infinity)
                                Text(album.name)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                                Text(album.artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !library.playlists.isEmpty {
                NextSectionHeader(title: "Playlists", detail: "YOUR MIXES")
                VStack(spacing: 2) {
                    ForEach(library.playlists.prefix(6)) { playlist in
                        Button {
                            selection = .playlists
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "music.note.list")
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .background(ToyakoDesign.Color.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                Text(playlist.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(playlist.trackURLs.count) tracks")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if library.tracks.isEmpty {
                ContentUnavailableView {
                    Label("Your music starts here", systemImage: "music.note")
                } description: {
                    Text("Import local audio files to build your Toyako library.")
                } actions: {
                    Button("Import music", action: onImport)
                        .buttonStyle(ToyakoPrimaryButtonStyle())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 6)
    }

    private var statistics: some View {
        VStack(alignment: .leading, spacing: 18) {
            NextSectionHeader(title: "Library overview", detail: "ON THIS DEVICE")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                NextMetric(value: library.tracks.count, title: "Tracks", symbol: "music.note")
                NextMetric(value: library.albums.count, title: "Albums", symbol: "square.stack")
                NextMetric(value: library.artists.count, title: "Artists", symbol: "person.2")
                NextMetric(value: audioManager.recentlyPlayed.count, title: "Recent tracks", symbol: "clock")
            }
            Text("Listening insights will grow as Toyako records more playback history. Your library and playback data stay on this device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .padding(26)
    }
}

private struct NextSectionHeader: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .tracking(-0.35)
            Spacer()
            Text(detail)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.tertiary)
        }
        .padding(.bottom, 8)
    }
}

private struct NextMetric: View {
    let value: Int
    let title: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value.formatted())
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(ToyakoDesign.Color.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct NextTrackRow: View {
    let track: LocalTrack
    let artworkURL: URL?
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                LazyArtwork(url: artworkURL, size: 46, cornerRadius: 9)
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.subheadline.weight(active ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if active {
                    Image(systemName: "waveform")
                        .foregroundStyle(.secondary)
                        .symbolEffect(.pulse, isActive: true)
                } else {
                    Text(nextTime(track.duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ToyakoNextMiniPlayer: View {
    let onOpen: () -> Void
    @EnvironmentObject private var audioManager: AudioEngineManager
    @EnvironmentObject private var clock: PlaybackClock

    var body: some View {
        HStack(spacing: 12) {
            if let track = audioManager.currentTrack {
                Button(action: onOpen) {
                    HStack(spacing: 11) {
                        LazyArtwork(url: track.url, size: 42, cornerRadius: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(track.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button { audioManager.backward() } label: {
                    Image(systemName: "backward.end.fill")
                }
                .buttonStyle(ToyakoIconButtonStyle(size: 40))

                Button { audioManager.togglePlayPause() } label: {
                    Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(ToyakoIconButtonStyle(size: 44))

                Button { audioManager.forward() } label: {
                    Image(systemName: "forward.end.fill")
                }
                .buttonStyle(ToyakoIconButtonStyle(size: 40))
            } else {
                Image(systemName: "waveform")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Nothing playing")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Choose something from your library")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ToyakoDesign.Color.divider, lineWidth: 1)
        }
        .overlay(alignment: .bottom) {
            GeometryReader { proxy in
                Capsule()
                    .fill(.primary.opacity(0.75))
                    .frame(width: proxy.size.width * max(0, min(1, clock.playbackProgress)), height: 2)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .padding(.horizontal, 14)
        }
        .shadow(color: .black.opacity(0.06), radius: 18, y: 6)
    }
}

private struct ToyakoNextQueuePanel: View {
    @EnvironmentObject private var audioManager: AudioEngineManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Up next")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("\(max(0, audioManager.queue.count - audioManager.queueIndex - 1)) tracks remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Clear queue", role: .destructive) {
                        audioManager.clearQueue()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .frame(width: 34, height: 34)
                        .background(ToyakoDesign.Color.surface, in: Circle())
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 16)

            if let current = audioManager.currentTrack {
                HStack(spacing: 10) {
                    LazyArtwork(url: current.url, size: 38, cornerRadius: 7)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NOW PLAYING")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(.secondary)
                        Text(current.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "waveform")
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(ToyakoDesign.Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }

            ScrollView {
                LazyVStack(spacing: 2) {
                    let start = min(audioManager.queueIndex + 1, audioManager.queue.count)
                    ForEach(Array(audioManager.queue.dropFirst(start).enumerated()), id: \.element.id) { offset, track in
                        Button {
                            audioManager.playQueuedTrack(at: start + offset)
                        } label: {
                            HStack(spacing: 10) {
                                LazyArtwork(url: track.url, size: 38, cornerRadius: 7)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.title)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(track.artist)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                Text(nextTime(track.duration))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 7)
                            .padding(.horizontal, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
            }
            .scrollIndicators(.hidden)

            if audioManager.queue.isEmpty {
                ContentUnavailableView("Queue is empty", systemImage: "text.badge.plus", description: Text("Play an album or track to start a listening session."))
                    .padding(.horizontal, 12)
            }
        }
        .background(ToyakoDesign.Color.canvas)
    }
}

struct ToyakoNextNowPlayingView: View {
    @Binding var isPresented: Bool
    let library: LocalLibrary

    @EnvironmentObject private var audioManager: AudioEngineManager
    @EnvironmentObject private var clock: PlaybackClock
    @State private var sidePanel: PlayerSidePanel = .queue

    private enum PlayerSidePanel: String, CaseIterable {
        case queue = "Queue"
        case lyrics = "Lyrics"
    }

    private var track: LocalTrack? { audioManager.currentTrack }
    private var artworkURL: URL? {
        guard let track else { return nil }
        return library.artworkURL(for: track)
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack {
                        Button {
                            withAnimation(.easeInOut(duration: 0.28)) { isPresented = false }
                        } label: {
                            Label("Back to workspace", systemImage: "chevron.down")
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Text("NOW PLAYING")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            sidePanel = sidePanel == .queue ? .lyrics : .queue
                        } label: {
                            Image(systemName: sidePanel == .queue ? "quote.bubble" : "text.line.first.and.arrowtriangle.forward")
                        }
                        .buttonStyle(ToyakoIconButtonStyle(size: 40))
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 18)

                    Spacer(minLength: 18)

                    if let track {
                        LazyArtwork(url: artworkURL, size: min(geometry.size.height * 0.43, geometry.size.width * 0.43), cornerRadius: 18)
                            .aspectRatio(1, contentMode: .fit)
                            .shadow(color: .black.opacity(0.14), radius: 28, y: 14)
                            .padding(.bottom, 28)

                        VStack(spacing: 6) {
                            Text(track.title)
                                .font(.system(size: 25, weight: .bold, design: .rounded))
                                .tracking(-0.5)
                                .lineLimit(1)
                            Text(track.artist + "  ·  " + track.album)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 24)

                        VStack(spacing: 8) {
                            Slider(value: Binding(
                                get: { clock.playbackProgress },
                                set: { audioManager.seek(to: $0 * max(track.duration, 0)) }
                            ), in: 0...1)
                            HStack {
                                Text(nextTime(clock.currentTime))
                                Spacer()
                                Text("-" + nextTime(max(0, track.duration - clock.currentTime)))
                            }
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 34)
                        .padding(.top, 24)

                        HStack(spacing: 30) {
                            Button { audioManager.backward() } label: {
                                Image(systemName: "backward.end.fill").font(.title2)
                            }
                            Button { audioManager.togglePlayPause() } label: {
                                Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 22, weight: .bold))
                                    .frame(width: 66, height: 66)
                                    .background(.primary, in: Circle())
                                    .foregroundStyle(ToyakoDesign.Color.canvas)
                            }
                            Button { audioManager.forward() } label: {
                                Image(systemName: "forward.end.fill").font(.title2)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 18)
                    } else {
                        ContentUnavailableView("Nothing playing", systemImage: "music.note", description: Text("Choose a track from your library to begin."))
                    }

                    Spacer(minLength: 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ToyakoDesign.Color.canvas)

                Rectangle()
                    .fill(ToyakoDesign.Color.divider)
                    .frame(width: 1)

                VStack(alignment: .leading, spacing: 0) {
                    Picker("Player panel", selection: $sidePanel) {
                        Text("Queue").tag(PlayerSidePanel.queue)
                        Text("Lyrics").tag(PlayerSidePanel.lyrics)
                    }
                    .pickerStyle(.segmented)
                    .padding(18)

                    if sidePanel == .queue {
                        ToyakoNextQueuePanel()
                    } else {
                        lyricsPanel
                    }
                }
                .frame(width: max(300, min(geometry.size.width * 0.34, 440)))
                .background(ToyakoDesign.Color.surface.opacity(0.42))
            }
            .background(ToyakoDesign.Color.canvas)
        }
        .background(ToyakoDesign.Color.canvas)
        .ignoresSafeArea()
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
        .zIndex(100)
    }

    private var activeLyricID: UUID? {
        audioManager.currentLyrics.last(where: { $0.time <= clock.currentTime })?.id
    }

    private var lyricsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Synchronised lyrics")
                .font(.headline)
                .padding(.horizontal, 18)
            if audioManager.currentLyrics.isEmpty {
                ContentUnavailableView("No lyrics found", systemImage: "text.quote", description: Text("Add an LRC or TTML lyrics file beside the audio track."))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(audioManager.currentLyrics) { line in
                                let active = clock.currentTime >= line.time && clock.currentTime < max(line.endTime, line.time + 4)
                                Button {
                                    audioManager.seek(to: line.time)
                                } label: {
                                    Text(line.text)
                                        .font(.system(size: active ? 20 : 16, weight: active ? .semibold : .regular))
                                        .foregroundStyle(active ? .primary : .secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .buttonStyle(.plain)
                                .id(line.id)
                            }
                        }
                        .padding(20)
                    }
                    .onChange(of: activeLyricID) { _, activeID in
                        guard let activeID else { return }
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo(activeID, anchor: .center)
                        }
                    }
                }
            }
        }
        .padding(.top, 8)
    }
}

private func nextTime(_ duration: TimeInterval) -> String {
    let seconds = max(0, Int(duration))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
}
