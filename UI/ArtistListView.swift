import SwiftUI
import UIKit

struct ArtistListView: View {
    let artists: [ArtistGroup]
    let library: LocalLibrary

    @EnvironmentObject private var audioManager: AudioEngineManager
    @State private var artistBeingEdited: ArtistGroup?
    @State private var artworkRefreshID = 0
    @AppStorage(ToyakoPreferences.libraryArtworkSizeKey) private var libraryArtworkSize = 180.0

    var body: some View {
        ZStack {
            ArtworkBleedPageBackground(
                artworkURL: audioManager.currentTrack.flatMap { library.artworkURL(for: $0) }
                    ?? artists.first?.tracks.first.map { library.artworkURL(for: $0) }
            )

            GeometryReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        if artists.isEmpty {
                            ContentUnavailableView(
                                "No Artists",
                                systemImage: "music.mic",
                                description: Text("Import music to start building your artist library.")
                            )
                            .frame(maxWidth: .infinity, minHeight: 220)
                        } else {
                            CenteredLibraryGrid(
                                items: artists,
                                availableWidth: proxy.size.width - (ToyakoDesign.Metrics.screenHorizontal * 2),
                                minimumItemWidth: CGFloat(libraryArtworkSize) + 24,
                                rowSpacing: 24,
                                columnSpacing: 18
                            ) { artist in
                                NavigationLink {
                                    ArtistDetailView(artist: artist, library: library)
                                        .navigationTitle(artist.name)
                                        .navigationBarTitleDisplayMode(.inline)
                                } label: {
                                    ArtistGridCard(
                                        artist: artist,
                                        artworkSize: CGFloat(libraryArtworkSize),
                                        refreshID: artworkRefreshID
                                    )
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        playArtist(artist)
                                    } label: {
                                        Label("Play", systemImage: "play.fill")
                                    }

                                    Button {
                                        shuffleArtist(artist)
                                    } label: {
                                        Label("Shuffle", systemImage: "shuffle")
                                    }

                                    Button {
                                        artistBeingEdited = artist
                                    } label: {
                                        Label("Edit Artwork", systemImage: "pencil")
                                    }
                                }
                                .menuOrder(.fixed)
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
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: audioManager.currentTrack != nil ? 82 : 0)
        }
        .sheet(item: $artistBeingEdited) { artist in
            ArtistArtworkPickerSheet(artistName: artist.name) {
                artworkRefreshID += 1
            }
        }
    }

    private func playArtist(_ artist: ArtistGroup) {
        guard !artist.tracks.isEmpty else { return }
        audioManager.startQueue(tracks: artist.tracks, startIndex: 0)
    }

    private func shuffleArtist(_ artist: ArtistGroup) {
        guard !artist.tracks.isEmpty else { return }
        if !audioManager.isShuffle { audioManager.toggleShuffle() }
        audioManager.startQueue(
            tracks: artist.tracks,
            startIndex: Int.random(in: artist.tracks.indices)
        )
    }
}

// MARK: - Artist Grid Card

private struct ArtistGridCard: View {
    let artist: ArtistGroup
    let artworkSize: CGFloat
    let refreshID: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ArtistSquareArtworkView(artistName: artist.name, size: artworkSize)
                .id("\(artist.name)|\(refreshID)")
                .frame(width: artworkSize, height: artworkSize)
                .toyakoArtwork(cornerRadius: ToyakoDesign.Metrics.artworkSmallRadius)

            Text(artist.name)
                .font(.headline)
                .lineLimit(1)

            Text(artist.tracks.count == 1 ? "1 Track" : "\(artist.tracks.count) Tracks")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 6) {
                Text(artist.tracks.count == 1 ? "1 Song" : "\(artist.tracks.count) Songs")
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(formatArtistDuration(artist.tracks))
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
}

private struct ArtistSquareArtworkView: View {
    let artistName: String
    let size: CGFloat
    @AppStorage(ToyakoPreferences.automaticArtistArtworkKey) private var automaticDownloads = false
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.gray.opacity(0.18))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.30))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .task(id: "\(artistName)|\(automaticDownloads)") {
            let data = await ArtistArtworkService.shared.imageData(
                for: artistName,
                allowNetwork: automaticDownloads
            )
            guard !Task.isCancelled else { return }
            image = data.flatMap(UIImage.init(data:))
        }
    }
}

private func formatArtistDuration(_ tracks: [LocalTrack]) -> String {
    let seconds = max(0, Int(tracks.reduce(0) { $0 + $1.duration }.rounded()))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
}

// MARK: - Artist Detail

// MARK: - Shared Artist Reflection Background

private struct ArtistReflectionBackground: View {
    let artwork: UIImage?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: proxy.size.width * 1.28,
                            height: proxy.size.height * 1.28
                        )
                        .position(
                            x: proxy.size.width * 0.50,
                            y: proxy.size.height * 0.50
                        )
                        .blur(radius: 68)
                        .saturation(1.15)
                        .brightness(-0.20)
                        .opacity(0.34)

                    // Wider, lower-frequency colour bleed keeps the artist list and
                    // the detail pane on the same reflected artwork field.
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: proxy.size.width * 1.65,
                            height: proxy.size.height * 1.05
                        )
                        .position(
                            x: proxy.size.width * 0.48,
                            y: proxy.size.height * 0.54
                        )
                        .blur(radius: 112)
                        .saturation(1.10)
                        .brightness(-0.30)
                        .opacity(0.18)
                }

                // One uniform translucent dark veil. No top/bottom gradient and no
                // opaque panel, so the reflected artwork continues through the page.
                (colorScheme == .dark ? Color.black : Color.white).opacity(colorScheme == .dark ? 0.43 : 0.12)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct ArtistDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    let artist: ArtistGroup
    let library: LocalLibrary
    let usesSharedBackground: Bool

    @EnvironmentObject private var audioManager: AudioEngineManager
    @State private var artwork: UIImage?
    @State private var showAllTracks = false
    @AppStorage(ToyakoPreferences.automaticArtistArtworkKey) private var automaticArtistArtwork = false
    @AppStorage(ToyakoPreferences.libraryArtworkSizeKey) private var libraryArtworkSize = 180.0

    init(
        artist: ArtistGroup,
        library: LocalLibrary,
        usesSharedBackground: Bool = false
    ) {
        self.artist = artist
        self.library = library
        self.usesSharedBackground = usesSharedBackground
    }

    private var albums: [ArtistAlbum] {
        var grouped: [String: [LocalTrack]] = [:]
        var order: [String] = []

        for track in artist.tracks {
            let name = track.album.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = name.isEmpty ? "Unknown Album" : name
            if grouped[key] == nil {
                order.append(key)
                grouped[key] = []
            }
            grouped[key]?.append(track)
        }

        return order.map { name in
            ArtistAlbum(
                name: name,
                tracks: grouped[name] ?? [],
                artworkURL: grouped[name].flatMap { $0.first }.map { library.artworkURL(for: $0) }
            )
        }
    }

    private var visibleTracks: [LocalTrack] {
        showAllTracks ? artist.tracks : Array(artist.tracks.prefix(6))
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                hero(availableWidth: proxy.size.width)
                    .padding(.horizontal, heroHorizontalPadding(for: proxy.size.width))
                    .padding(.top, 10)
                    .padding(.bottom, 18)

                Divider()
                    .opacity(0.45)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: ToyakoDesign.Metrics.sectionSpacing) {
                        popularTracks
                        albumSection(availableWidth: max(0, proxy.size.width - (heroHorizontalPadding(for: proxy.size.width) * 2)))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, heroHorizontalPadding(for: proxy.size.width))
                    .padding(.top, 20)
                    .padding(.bottom, ToyakoDesign.Metrics.screenBottom)
                }
                .scrollIndicators(.hidden)
            }
            .tint(ToyakoDesign.Color.accent)
            .background {
                if usesSharedBackground {
                    Color.clear
                } else {
                    ArtistReflectionBackground(artwork: artwork)
                }
            }
        }
        .task(id: "\(artist.name)|\(automaticArtistArtwork)") {
            let data = await ArtistArtworkService.shared.imageData(
                for: artist.name,
                allowNetwork: automaticArtistArtwork
            )
            guard !Task.isCancelled else { return }
            artwork = data.flatMap(UIImage.init(data:))
        }
    }

    @ViewBuilder
    private func hero(availableWidth: CGFloat) -> some View {
        let wideHero = availableWidth >= 700
        let artworkSize = CGFloat(libraryArtworkSize)

        if wideHero {
            HStack(alignment: .center, spacing: 36) {
                artistArtwork(size: artworkSize)

                VStack(alignment: .leading, spacing: 12) {
                    artistTitleBlock
                    heroActions(compact: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 18) {
                    artistArtwork(size: artworkSize)
                    artistTitleBlock
                }

                heroActions(compact: true)
            }
            .padding(.vertical, 4)
        }
    }

    private var artistTitleBlock: some View {
        Text(artist.name)
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .lineLimit(2)
            .minimumScaleFactor(0.72)
    }

    private func heroActions(compact: Bool) -> some View {
        HStack(spacing: 10) {
            Button(action: playArtist) {
                Label("Play", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ToyakoPrimaryButtonStyle())

            Button(action: shuffleArtist) {
                Label("Shuffle", systemImage: "shuffle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ToyakoSecondaryButtonStyle())


        }
        .frame(maxWidth: 430)
    }

    private func artistArtwork(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill((colorScheme == .dark ? Color.white : Color.black).opacity(0.06))

            if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.27, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(ToyakoDesign.Color.accent.opacity(0.78), lineWidth: 3)
        }
        .shadow(color: ToyakoDesign.Color.accent.opacity(0.22), radius: 22, y: 8)
    }

    private func heroHorizontalPadding(for width: CGFloat) -> CGFloat {
        width >= 1100 ? 32 : (width >= 900 ? 26 : 18)
    }

    private func artistSidebarWidth(for width: CGFloat) -> CGFloat {
        // Keep the sidebar fluid while preserving enough room for the detail view.
        let proportional = width * 0.28
        return min(max(proportional, 260), 460)
    }

    private var popularTracks: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToyakoSectionHeader(
                "Popular Tracks",
                trailingTitle: artist.tracks.count > 6 ? (showAllTracks ? "Show Less" : "View All") : nil,
                trailingAction: artist.tracks.count > 6 ? {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAllTracks.toggle()
                    }
                } : nil
            )

            VStack(spacing: 0) {
                ForEach(Array(visibleTracks.enumerated()), id: \.element.id) { index, track in
                    Button {
                        audioManager.startQueue(tracks: artist.tracks, startIndex: artist.tracks.firstIndex(of: track) ?? index)
                    } label: {
                        HStack(spacing: 14) {
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .frame(width: 22)

                            LazyArtwork(
                                url: library.artworkURL(for: track),
                                size: ToyakoArtworkSize.compactRow,
                                cornerRadius: ToyakoDesign.Metrics.artworkSmallRadius
                            )

                            VStack(alignment: .leading, spacing: 3) {
                                Text(track.title)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Text(track.album)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 8)

                            Text(formatTime(track.duration))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)

                            Image(systemName: "ellipsis")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 28)
                        }
                        .padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            audioManager.playNext(track)
                        } label: {
                            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                        }

                        Button {
                            audioManager.enqueue([track])
                        } label: {
                            Label("Add to Queue", systemImage: "text.badge.plus")
                        }
                    }

                    if index < visibleTracks.count - 1 {
                        Divider().padding(.leading, 84)
                    }
                }
            }
            .padding(.horizontal, 14)
            .toyakoCard()
        }
    }

    private func albumSection(availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Albums")
                    .font(ToyakoDesign.Typography.section)
                Spacer(minLength: 0)
                Text("\(albums.count)")
                    .font(ToyakoDesign.Typography.metadata)
                    .foregroundStyle(.secondary)
            }

            CenteredLibraryGrid(
                items: albums,
                availableWidth: availableWidth,
                minimumItemWidth: CGFloat(libraryArtworkSize) + 24,
                rowSpacing: 24,
                columnSpacing: 18,
                rowAlignment: .leading
            ) { album in
                Button {
                    guard !album.tracks.isEmpty else { return }
                    audioManager.startQueue(tracks: album.tracks, startIndex: 0)
                } label: {
                    ArtistAlbumCard(album: album, artworkSize: CGFloat(libraryArtworkSize))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        guard !album.tracks.isEmpty else { return }
                        audioManager.startQueue(tracks: album.tracks, startIndex: 0)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }

                    Button {
                        guard !album.tracks.isEmpty else { return }
                        if !audioManager.isShuffle {
                            audioManager.toggleShuffle()
                        }
                        audioManager.startQueue(
                            tracks: album.tracks,
                            startIndex: Int.random(in: album.tracks.indices)
                        )
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                }
            }
        }
    }

    private func playArtist() {
        guard !artist.tracks.isEmpty else { return }
        audioManager.startQueue(tracks: artist.tracks, startIndex: 0)
    }

    private func shuffleArtist() {
        guard !artist.tracks.isEmpty else { return }
        let index = Int.random(in: artist.tracks.indices)
        if !audioManager.isShuffle {
            audioManager.toggleShuffle()
        }
        audioManager.startQueue(tracks: artist.tracks, startIndex: index)
    }

    private func formatTime(_ duration: TimeInterval) -> String {
        guard duration.isFinite, duration >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)
    }
}

private struct ArtistAlbum: Identifiable {
    let id: String
    let name: String
    let tracks: [LocalTrack]
    let artworkURL: URL?

    init(name: String, tracks: [LocalTrack], artworkURL: URL?) {
        self.id = name
        self.name = name
        self.tracks = tracks
        self.artworkURL = artworkURL
    }
}


// MARK: - Manual Artist Artwork Picker

private struct ArtistArtworkPickerSheet: View {
    let artistName: String
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String
    @State private var results: [ArtistArtworkSearchResult] = []
    @State private var isSearching = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(artistName: String, onSaved: @escaping () -> Void) {
        self.artistName = artistName
        self.onSaved = onSaved
        _searchText = State(initialValue: artistName)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search Deezer artists", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                }
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .padding(.horizontal)

                if isSearching {
                    ProgressView("Searching Deezer…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Couldn't load artists",
                        systemImage: "wifi.exclamationmark",
                        description: Text(errorMessage)
                    )
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List(results) { result in
                        Button {
                            save(result)
                        } label: {
                            HStack(spacing: 12) {
                                AsyncImage(url: URL(string: result.imageURL)) { phase in
                                    if let image = phase.image {
                                        image.resizable().scaledToFill()
                                    } else {
                                        Circle().fill(.quaternary)
                                            .overlay { Image(systemName: "person.fill").foregroundStyle(.secondary) }
                                    }
                                }
                                .frame(width: 54, height: 54)
                                .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(result.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("Deezer artist")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if isSaving {
                                    ProgressView()
                                } else {
                                    Image(systemName: "arrow.down.circle")
                                        .foregroundStyle(ToyakoDesign.Color.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving)
                    }
                    .listStyle(.plain)
                }
            }
            .padding(.top, 12)
            .navigationTitle("Edit Artist Artwork")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task(id: searchText) {
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else {
                    results = []
                    return
                }

                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                isSearching = true
                errorMessage = nil
                let matches = await ArtistArtworkService.shared.searchDeezerArtists(query: query)
                guard !Task.isCancelled else { return }
                results = matches
                isSearching = false
                if matches.isEmpty {
                    errorMessage = "No Deezer artists matched “\(query)”. Try another spelling."
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save(_ result: ArtistArtworkSearchResult) {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil

        Task {
            let success = await ArtistArtworkService.shared.setManualArtistArtwork(
                localArtistName: artistName,
                selection: result
            )
            isSaving = false
            if success {
                onSaved()
                dismiss()
            } else {
                errorMessage = "The selected artist photo couldn't be downloaded. Please try another result."
            }
        }
    }
}


// MARK: - Artist Album Card

private struct ArtistAlbumCard: View {
    let album: ArtistAlbum
    let artworkSize: CGFloat

    private var totalDuration: String {
        let seconds = max(0, Int(album.tracks.reduce(0) { $0 + $1.duration }.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            LazyArtwork(
                url: album.artworkURL,
                size: artworkSize,
                cornerRadius: ToyakoDesign.Metrics.artworkSmallRadius
            )
            .frame(width: artworkSize, height: artworkSize)
            .toyakoArtwork(cornerRadius: ToyakoDesign.Metrics.artworkSmallRadius)

            Text(album.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(album.tracks.first?.artist ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 6) {
                Text(album.tracks.count == 1 ? "1 Track" : "\(album.tracks.count) Tracks")
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(totalDuration)
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .frame(width: artworkSize + 24, alignment: .leading)
        .toyakoCard(cornerRadius: ToyakoDesign.Metrics.cardRadius)
        .contentShape(RoundedRectangle(cornerRadius: ToyakoDesign.Metrics.cardRadius, style: .continuous))
    }
}

