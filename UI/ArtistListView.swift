import SwiftUI
import UIKit

struct ArtistListView: View {
    let artists: [ArtistGroup]
    let library: LocalLibrary
    @EnvironmentObject var audioManager: AudioEngineManager

    @State private var selectedArtistID: String?
    @State private var artistSearch = ""


    private var visibleArtists: [ArtistGroup] {
        guard !artistSearch.isEmpty else { return artists }
        return artists.filter {
            $0.name.localizedCaseInsensitiveContains(artistSearch)
        }
    }

    private var selectedArtist: ArtistGroup? {
        if let selectedArtistID,
           let artist = artists.first(where: { $0.id == selectedArtistID }) {
            return artist
        }
        return visibleArtists.first
    }

    var body: some View {
        GeometryReader { proxy in
            Group {
                if proxy.size.width >= 700 {
                    iPadArtistLayout(availableWidth: proxy.size.width)
                } else {
                    compactArtistLayout
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: audioManager.currentTrack != nil ? 82 : 0)
        }
        .onAppear {
            selectFirstArtistIfNeeded()
        }
        .onChange(of: artists) { _, _ in
            selectFirstArtistIfNeeded()
        }
        .onChange(of: artistSearch) { _, _ in
            if let selectedArtistID,
               visibleArtists.contains(where: { $0.id == selectedArtistID }) {
                return
            }
            self.selectedArtistID = visibleArtists.first?.id
        }
    }

    // MARK: - iPad

    private func iPadArtistLayout(availableWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            artistSidebar
                .frame(width: artistSidebarWidth(for: availableWidth))
                .zIndex(2)

            Divider()
                .zIndex(3)

            if let artist = selectedArtist {
                ArtistDetailView(
                    artist: artist,
                    library: library
                )
                .id(artist.id)
                .transition(.opacity)
                .zIndex(1)
            } else {
                ContentUnavailableView(
                    "No Artists",
                    systemImage: "music.mic",
                    description: Text("Import music to start building your artist library.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(1)
            }
        }
        .background(ToyakoDesign.Color.canvas)
    }

    private func artistSidebarWidth(for totalWidth: CGFloat) -> CGFloat {
        // Keep the sidebar responsive while preserving enough room for the detail pane.
        // The width scales with the available window instead of becoming fixed at a
        // single value, which keeps Stage Manager and split-view resizing smooth.
        let minimum: CGFloat = 240
        let preferred = totalWidth * 0.28
        let maximum = max(minimum, totalWidth - 420)
        return min(max(preferred, minimum), maximum)
    }

    private var artistSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(artists.count) Artists")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)

            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search artists…", text: $artistSearch)
                    .textFieldStyle(.plain)
                    .submitLabel(.search)

                if !artistSearch.isEmpty {
                    Button {
                        artistSearch = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(visibleArtists) { artist in
                        artistRow(artist)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
        }
        .background(ToyakoDesign.Color.surface.opacity(0.42))
    }

    private func artistRow(_ artist: ArtistGroup) -> some View {
        let isSelected = selectedArtist?.id == artist.id

        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                selectedArtistID = artist.id
            }
        } label: {
            HStack(spacing: 12) {
                ArtistArtworkView(
                    artistName: artist.name,
                    size: 48
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(artist.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(trackCountText(for: artist))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(RoundedRectangle(cornerRadius: ToyakoDesign.Metrics.controlRadius, style: .continuous))
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: ToyakoDesign.Metrics.controlRadius, style: .continuous)
                        .fill(ToyakoDesign.Color.selectedFill)
                }
            }
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
        }
    }

    // MARK: - Compact / iPhone

    private var compactArtistLayout: some View {
        List {
            Section {
                ForEach(artists) { artist in
                    NavigationLink {
                        ArtistDetailView(
                            artist: artist,
                            library: library
                        )
                        .navigationTitle(artist.name)
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        HStack(spacing: 14) {
                            ArtistArtworkView(artistName: artist.name, size: 54)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(artist.name)
                                    .font(.headline)
                                    .lineLimit(1)

                                Text(trackCountText(for: artist))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 8)
                        }
                        .padding(.vertical, 4)
                    }
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
                    }
                }
            } header: {
                Text("\(artists.count) Artists")
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Playback

    private func playArtist(_ artist: ArtistGroup) {
        guard !artist.tracks.isEmpty else { return }
        audioManager.startQueue(tracks: artist.tracks, startIndex: 0)
    }

    private func shuffleArtist(_ artist: ArtistGroup) {
        guard !artist.tracks.isEmpty else { return }

        let index = Int.random(in: artist.tracks.indices)
        if !audioManager.isShuffle {
            audioManager.toggleShuffle()
        }
        audioManager.startQueue(tracks: artist.tracks, startIndex: index)
    }

    private func selectFirstArtistIfNeeded() {
        guard selectedArtistID == nil || !artists.contains(where: { $0.id == selectedArtistID }) else {
            return
        }
        selectedArtistID = artists.first?.id
    }

    private func trackCountText(for artist: ArtistGroup) -> String {
        artist.tracks.count == 1 ? "1 Track" : "\(artist.tracks.count) Tracks"
    }
}

// MARK: - Artist Detail

private struct ArtistDetailView: View {
    let artist: ArtistGroup
    let library: LocalLibrary

    @EnvironmentObject private var audioManager: AudioEngineManager
    @State private var artwork: UIImage?
    @State private var showAllTracks = false
    @AppStorage(ToyakoPreferences.automaticArtistArtworkKey) private var automaticArtistArtwork = false


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
                        albumSection
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
                ZStack {
                    // One continuous canvas: the artwork is allowed to flow behind the
                    // complete detail page instead of stopping at a hard horizontal band.
                    ToyakoDesign.Color.canvas

                    if let artwork {
                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                            .blur(radius: 56)
                            .scaleEffect(1.10)
                            .opacity(0.24)
                    }

                    // A single continuous tonal treatment keeps the artwork atmospheric
                    // without introducing a second solid-colored panel behind the hero.
                    LinearGradient(
                        stops: [
                            .init(color: ToyakoDesign.Color.canvas.opacity(0.18), location: 0),
                            .init(color: ToyakoDesign.Color.canvas.opacity(0.38), location: 0.30),
                            .init(color: ToyakoDesign.Color.canvas.opacity(0.82), location: 0.62),
                            .init(color: ToyakoDesign.Color.canvas, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    // Subtle edge darkening for legibility, not a separate panel.
                    LinearGradient(
                        colors: [.black.opacity(0.08), .clear, .black.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
        }
        .task(id: "\(artist.name)|\(automaticArtistArtwork)") {
            let data = await ArtistArtworkService.shared.imageData(
                for: artist.name,
                allowNetwork: true
            )
            guard !Task.isCancelled else { return }
            artwork = data.flatMap(UIImage.init(data:))
        }
    }

    @ViewBuilder
    private func hero(availableWidth: CGFloat) -> some View {
        let wideHero = availableWidth >= 900
        let artworkSize = wideHero ? min(210.0, max(180.0, availableWidth * 0.20)) : min(180.0, max(150.0, availableWidth * 0.30))

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
        VStack(alignment: .leading, spacing: 8) {
            Text(artist.name)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.72)

            Text(artistMeta)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
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

            Menu {
                Button {
                    audioManager.enqueue(artist.tracks)
                } label: {
                    Label("Add to Queue", systemImage: "text.badge.plus")
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .buttonStyle(ToyakoIconButtonStyle(size: ToyakoDesign.Metrics.largeControlHeight))
            .accessibilityLabel("More artist actions")
        }
        .frame(maxWidth: compact ? .infinity : 600)
    }

    private func artistArtwork(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.06))

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

    private var albumSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Albums")
                    .font(ToyakoDesign.Typography.section)
                Spacer(minLength: 0)
                Text("\(albums.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 18) {
                    ForEach(albums) { album in
                        Button {
                            guard !album.tracks.isEmpty else { return }
                            audioManager.startQueue(tracks: album.tracks, startIndex: 0)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                LazyArtwork(
                                    url: album.artworkURL,
                                    size: 150,
                                    cornerRadius: ToyakoDesign.Metrics.artworkRadius
                                )

                                Text(album.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .frame(width: 150, alignment: .leading)

                                Text(album.tracks.count == 1 ? "1 Track" : "\(album.tracks.count) Tracks")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var artistMeta: String {
        let trackCount = artist.tracks.count
        let albumCount = albums.count
        let tracks = trackCount == 1 ? "1 Track" : "\(trackCount) Tracks"
        let albumText = albumCount == 1 ? "1 Album" : "\(albumCount) Albums"
        return "\(tracks)  •  \(albumText)"
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
