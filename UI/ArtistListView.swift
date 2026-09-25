import SwiftUI
import UIKit

struct ArtistListView: View {
    let artists: [ArtistGroup]
    let library: LocalLibrary
    @EnvironmentObject var audioManager: AudioEngineManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedArtistID: String?
    @State private var artistSearch = ""

    private var isRegular: Bool {
        horizontalSizeClass == .regular
    }

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
        Group {
            if isRegular {
                iPadArtistLayout
            } else {
                compactArtistLayout
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

    private var iPadArtistLayout: some View {
        HStack(spacing: 0) {
            artistSidebar
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 380)

            Divider()

            if let artist = selectedArtist {
                ArtistDetailView(
                    artist: artist,
                    library: library
                )
                .id(artist.id)
                .transition(.opacity)
            } else {
                ContentUnavailableView(
                    "No Artists",
                    systemImage: "music.mic",
                    description: Text("Import music to start building your artist library.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(ToyakoDesign.Color.canvas)
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                hero
                popularTracks
                albumSection
            }
            .toyakoScreenPadding()
        }
        .scrollIndicators(.hidden)
        .tint(ToyakoDesign.Color.accent)
        .background {
            ZStack {
                ToyakoDesign.Color.canvas

                // The hero background is derived from the real artist photo:
                // enlarged, heavily blurred, darkened and faded into the page.
                // It gives the detail page atmosphere without competing with
                // the content or looking like a separate full-screen poster.
                if let artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 500)
                        .frame(maxWidth: .infinity, alignment: .top)
                        .blur(radius: 55)
                        .scaleEffect(1.08)
                        .opacity(0.26)
                        .overlay {
                            LinearGradient(
                                colors: [
                                    ToyakoDesign.Color.canvas.opacity(0.05),
                                    ToyakoDesign.Color.canvas.opacity(0.52),
                                    ToyakoDesign.Color.canvas
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                        .mask {
                            LinearGradient(
                                colors: [.black, .black.opacity(0.8), .black.opacity(0.25), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                }

                LinearGradient(
                    colors: [ToyakoDesign.Color.accent.opacity(0.08), .clear, ToyakoDesign.Color.canvas],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .ignoresSafeArea()
        }
        .task(id: "\(artist.name)|\(automaticArtistArtwork)") {
            // Reuse Toyako's existing artwork provider instead of the MusicKit
            // provider. This is the same source used by the artist list, so
            // the detail page and sidebar stay consistent.
            let data = await ArtistArtworkService.shared.imageData(
                for: artist.name,
                allowNetwork: true
            )
            guard !Task.isCancelled else { return }
            artwork = data.flatMap(UIImage.init(data:))
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 28) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.07))

                    if let artwork {
                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 56, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 210, height: 210)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(ToyakoDesign.Color.accent.opacity(0.75), lineWidth: 3)
                }
                .shadow(color: ToyakoDesign.Color.accent.opacity(0.25), radius: 28, y: 12)

                VStack(alignment: .leading, spacing: 14) {
                    Text(artist.name)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .lineLimit(2)

                    Text(artistMeta)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button(action: playArtist) {
                            Label("Play", systemImage: "play.fill")
                                .frame(minWidth: 142)
                        }
                        .buttonStyle(ToyakoPrimaryButtonStyle())

                        Button(action: shuffleArtist) {
                            Label("Shuffle", systemImage: "shuffle")
                                .frame(minWidth: 142)
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
                    }
                }

                Spacer(minLength: 0)
            }
        }
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
