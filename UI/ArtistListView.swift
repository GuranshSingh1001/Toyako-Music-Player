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
        .background(Color(.systemBackground))
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
        .background(Color(.secondarySystemBackground).opacity(0.35))
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
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.16))
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
            .padding(.horizontal, 34)
            .padding(.top, 20)
            .padding(.bottom, 100)
        }
        .scrollIndicators(.hidden)
        .background {
            ZStack {
                Color(.systemBackground)

                if let artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 460)
                        .frame(maxWidth: .infinity, alignment: .top)
                        .blur(radius: 45)
                        .opacity(0.20)
                        .mask {
                            LinearGradient(
                                colors: [.black, .black.opacity(0.55), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                }
            }
            .ignoresSafeArea()
        }
        .task(id: artist.name) {
            let data = await AppleMusicArtistArtworkService.shared.imageData(for: artist.name)
            guard !Task.isCancelled else { return }
            artwork = data.flatMap(UIImage.init(data:))
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom, spacing: 26) {
                ZStack {
                    if let artwork {
                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.secondary.opacity(0.16)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 54))
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(width: 190, height: 190)
                .clipShape(Circle())
                .shadow(radius: 24, y: 12)

                VStack(alignment: .leading, spacing: 12) {
                    Text(artist.name)
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .lineLimit(2)

                    Text(artistMeta)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Button {
                            playArtist()
                        } label: {
                            Label("Play", systemImage: "play.fill")
                                .font(.body.weight(.semibold))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 11)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)

                        Button {
                            shuffleArtist()
                        } label: {
                            Label("Shuffle", systemImage: "shuffle")
                                .font(.body.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)

                        Menu {
                            Button {
                                audioManager.enqueue(artist.tracks)
                            } label: {
                                Label("Add to Queue", systemImage: "text.badge.plus")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(width: 42, height: 42)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                    }
                }
                .padding(.bottom, 4)

                Spacer(minLength: 0)
            }
        }
    }

    private var popularTracks: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Popular Tracks")
                    .font(.title3.weight(.bold))

                Spacer()

                if artist.tracks.count > 6 {
                    Button(showAllTracks ? "Show Less" : "View All") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAllTracks.toggle()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }

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
                                size: 48,
                                cornerRadius: 7
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
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var albumSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Albums")
                    .font(.title3.weight(.bold))

                Spacer()

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
                                    cornerRadius: 12
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
