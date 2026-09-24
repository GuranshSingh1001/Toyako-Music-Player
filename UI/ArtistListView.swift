import SwiftUI

struct ArtistListView: View {
    @Namespace private var artistTransitionNamespace

    let artists: [ArtistGroup]
    let library: LocalLibrary
    @EnvironmentObject var audioManager: AudioEngineManager

    var body: some View {
        GeometryReader { proxy in
            let horizontalPadding: CGFloat = proxy.size.width < 600 ? 16 : 24

            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 155, maximum: 220), spacing: 20)
                    ],
                    spacing: 26
                ) {
                    ForEach(artists) { artist in
                        NavigationLink {
                            ArtistDetailView(artist: artist, library: library, transitionNamespace: artistTransitionNamespace)
                        } label: {
                            artistGridCard(artist)
                                .matchedTransitionSource(id: artist.id, in: artistTransitionNamespace)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 18)
                .padding(.bottom, audioManager.currentTrack != nil ? 100 : 30)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        }
        .overlay(alignment: .topLeading) {
            Text("\(artists.count) Artists")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 24)
                .padding(.top, 8)
        }
    }

    private func artistGridCard(_ artist: ArtistGroup) -> some View {
        VStack(spacing: 10) {
            ArtistArtworkView(artistName: artist.name, size: 150)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)

            Text(artist.name)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            Text(artist.tracks.count == 1 ? "1 Track" : "\(artist.tracks.count) Tracks")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

// MARK: - Artist Detail

struct ArtistDetailView: View {
    let artist: ArtistGroup
    let library: LocalLibrary
    let transitionNamespace: Namespace.ID

    @EnvironmentObject var audioManager: AudioEngineManager
    @State private var heroVisible = false

    private var albums: [AlbumGroup] {
        Dictionary(grouping: artist.tracks) { track in
            "\(track.album)\u{001F}\(track.artist)"
        }
        .values
        .compactMap { tracks in
            guard let first = tracks.first else { return nil }
            return AlbumGroup(
                name: first.album,
                artist: first.artist,
                artworkURL: library.artworkURL(for: first),
                tracks: tracks
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var sortedTracks: [LocalTrack] {
        artist.tracks.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private var totalDuration: TimeInterval {
        artist.tracks.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            // Use the same hero treatment at every window size. The compact
            // layout is only a spatial adaptation, not the old detail-page UI.
            let wide = width >= 700

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if wide {
                        wideHero
                    } else {
                        compactHero(maxWidth: width)
                    }

                    if !albums.isEmpty {
                        albumsSection(wide: wide)
                    }

                    tracksSection
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.bottom, 100)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationTransition(.zoom(sourceID: artist.id, in: transitionNamespace))
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.84)) {
                heroVisible = true
            }
        }
    }

    private var wideHero: some View {
        ZStack(alignment: .bottomLeading) {
            ArtistArtworkView(artistName: artist.name, size: 420)
                .frame(maxWidth: .infinity, maxHeight: 420, alignment: .center)
                .blur(radius: 0.2)
                .overlay {
                    LinearGradient(
                        colors: [.black.opacity(0.05), .black.opacity(0.72)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            VStack(alignment: .leading, spacing: 8) {
                Text("ARTIST")
                    .font(.caption.weight(.bold))
                    .tracking(1.3)
                    .foregroundStyle(.white.opacity(0.78))

                Text(artist.name)
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text("\(albums.count) \(albums.count == 1 ? "Album" : "Albums") • \(artist.tracks.count) \(artist.tracks.count == 1 ? "Song" : "Tracks") • \(formatDuration(totalDuration))")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.78))

                Button {
                    guard !sortedTracks.isEmpty else { return }
                    audioManager.startQueue(tracks: sortedTracks, startIndex: 0, shuffle: false)
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.headline)
                        .padding(.horizontal, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .padding(.top, 6)
            }
            .padding(.horizontal, 42)
            .padding(.bottom, 30)
        }
        .frame(height: 420)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .scaleEffect(heroVisible ? 1 : 0.985)
        .opacity(heroVisible ? 1 : 0)
    }

    private func compactHero(maxWidth: CGFloat) -> some View {
        let isVeryNarrow = maxWidth < 520
        let artworkSize = isVeryNarrow
            ? min(maxWidth * 0.62, 250)
            : min(maxWidth * 0.38, 300)

        return Group {
            if isVeryNarrow {
                // Phone / very narrow window: retain the visual hierarchy of
                // the large hero while keeping the content compact.
                VStack(spacing: 14) {
                    ArtistArtworkView(artistName: artist.name, size: artworkSize)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
                        .scaleEffect(heroVisible ? 1 : 0.94)
                        .opacity(heroVisible ? 1 : 0)

                    heroMetadata(centered: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 26)
            } else {
                // Resized iPad / narrow desktop window: use the same horizontal
                // composition as the landscape hero, scaled to the available width.
                HStack(spacing: 26) {
                    ArtistArtworkView(artistName: artist.name, size: artworkSize)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.25), radius: 22, y: 12)
                        .scaleEffect(heroVisible ? 1 : 0.94)
                        .opacity(heroVisible ? 1 : 0)

                    heroMetadata(centered: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background {
            LinearGradient(
                colors: [.black.opacity(0.03), .black.opacity(0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, isVeryNarrow ? 14 : 20)
        .padding(.top, 14)
    }

    private func heroMetadata(centered: Bool) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: 8) {
            Text("ARTIST")
                .font(.caption.weight(.bold))
                .tracking(1.3)
                .foregroundStyle(.secondary)

            Text(artist.name)
                .font(.system(size: 34, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(centered ? .center : .leading)

            Text("\(albums.count) \(albums.count == 1 ? "Album" : "Albums") • \(artist.tracks.count) \(artist.tracks.count == 1 ? "Song" : "Tracks") • \(formatDuration(totalDuration))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(centered ? .center : .leading)

            HStack(spacing: 10) {
                Button {
                    guard !sortedTracks.isEmpty else { return }
                    audioManager.startQueue(tracks: sortedTracks, startIndex: 0, shuffle: false)
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.headline)
                        .frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    guard !sortedTracks.isEmpty else { return }
                    audioManager.startQueue(
                        tracks: sortedTracks,
                        startIndex: Int.random(in: 0..<sortedTracks.count),
                        shuffle: true
                    )
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .font(.headline)
                        .frame(minWidth: 100)
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 5)
        }
    }

    private func albumsSection(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Albums")
                .font(.title2.bold())
                .padding(.horizontal, 24)

            if wide {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 20)], spacing: 24) {
                    ForEach(albums) { album in
                        albumCard(album)
                    }
                }
                .padding(.horizontal, 24)
            } else {
                let columns = max(1, Int((UIScreen.main.bounds.width - 72) / 170))
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: min(columns, 2)),
                    spacing: 20
                ) {
                    ForEach(albums) { album in
                        albumCard(album)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .padding(.vertical, 22)
        .background(.thinMaterial.opacity(0.45))
    }

    private func albumCard(_ album: AlbumGroup) -> some View {
        NavigationLink {
            AlbumDetailView(album: album, library: library, transitionNamespace: transitionNamespace)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                LazyAlbumArtwork(url: album.artworkURL)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.16), radius: 8, y: 4)

                Text(album.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text("\(album.tracks.count) \(album.tracks.count == 1 ? "Song" : "Tracks")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .matchedTransitionSource(id: album.id, in: transitionNamespace)
        }
        .buttonStyle(.plain)
    }

    private var tracksSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Songs")
                .font(.title2.bold())
                .padding(.horizontal, 24)
                .padding(.top, 26)
                .padding(.bottom, 8)

            ForEach(sortedTracks) { track in
                Button {
                    audioManager.play(track: track)
                } label: {
                    HStack(spacing: 12) {
                        LazyArtwork(url: library.artworkURL(for: track), size: 50, cornerRadius: 8)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.title)
                                .font(.body.weight(.medium))
                                .lineLimit(1)
                            Text(track.album)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 12)
                        Text(formatTrackDuration(track.duration))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 9)
                }
                .buttonStyle(.plain)

                if track.id != sortedTracks.last?.id {
                    Divider().padding(.leading, 86)
                }
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours) hr \(minutes) min" : "\(minutes) min"
    }

    private func formatTrackDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
