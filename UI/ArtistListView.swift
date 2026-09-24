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
                                .navigationTransition(.zoom(sourceID: artist.id, in: artistTransitionNamespace))
                        } label: {
                            artistGridCard(artist, transitionNamespace: artistTransitionNamespace)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 18)
                .padding(.bottom, audioManager.currentTrack != nil ? 100 : 30)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .scrollDisabled(false)
        }
        .overlay(alignment: .topLeading) {
            Text("\(artists.count) Artists")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 24)
                .padding(.top, 8)
        }
    }

    private func artistGridCard(_ artist: ArtistGroup, transitionNamespace: Namespace.ID) -> some View {
        VStack(spacing: 10) {
            ArtistArtworkView(artistName: artist.name, size: 150)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(Circle())
                .matchedTransitionSource(id: artist.id, in: transitionNamespace) { source in
                    source
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
                }

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
    @State private var heroVisible = true

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
            let wide = width >= 560

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
            .scrollDisabled(false)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // The navigation zoom supplies the opening/closing transition.
        // Do not run a second hero animation here: it can temporarily compete
        // with the navigation transition and make the ScrollView feel locked
        // immediately after returning to the page.
    }

    private var wideHero: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let horizontalPadding = min(max(width * 0.04, 24), 56)
            let available = max(320, width - horizontalPadding * 2)
            let spacing = min(max(available * 0.045, 24), 52)
            let artworkSize = min(max(available * 0.36, 220), 430)
            let textWidth = max(240, available - artworkSize - spacing)

            HStack(alignment: .center, spacing: spacing) {
                // Keep the iPad artist layout consistent with the album page:
                // artwork first, metadata/actions second.
                ArtistArtworkView(artistName: artist.name, size: artworkSize)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.28), radius: 28, y: 14)
                    .scaleEffect(heroVisible ? 1 : 0.92)
                    .opacity(heroVisible ? 1 : 0)
                    .layoutPriority(1)

                VStack(alignment: .leading, spacing: 10) {
                    Text("ARTIST")
                        .font(.caption.weight(.bold))
                        .tracking(1.5)
                        .foregroundStyle(.secondary)

                    Text(artist.name)
                        .font(.system(size: min(max(textWidth * 0.12, 34), 58), weight: .bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.68)

                    Text("\(albums.count) \(albums.count == 1 ? "Album" : "Albums") • \(artist.tracks.count) \(artist.tracks.count == 1 ? "Song" : "Tracks") • \(formatDuration(totalDuration))")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    HStack(spacing: 10) {
                        artistPlayButton
                        artistShuffleButton
                    }
                    .frame(maxWidth: min(textWidth, 430), alignment: .leading)
                    .padding(.top, 6)
                }
                .frame(width: textWidth, alignment: .leading)
            }
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: 1280)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: min(max(artworkHeroHeight, 340), 500))
        .padding(.top, 8)
    }

    private var artistPlayButton: some View {
        Button {
            guard !sortedTracks.isEmpty else { return }
            audioManager.startQueue(tracks: sortedTracks, startIndex: 0, shuffle: false)
        } label: {
            Label("Play", systemImage: "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(HeroPrimaryButtonStyle())
    }

    private var artistShuffleButton: some View {
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
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(HeroSecondaryButtonStyle())
    }

    private var artworkHeroHeight: CGFloat {
        470
    }

    private func compactHero(maxWidth: CGFloat) -> some View {
        if maxWidth >= 420 {
            let padding: CGFloat = 20
            let available = max(280, maxWidth - padding * 2)
            let spacing: CGFloat = 18
            let artworkSize = min(max(available * 0.36, 150), 220)
            let textWidth = max(150, available - artworkSize - spacing)

            return AnyView(
                HStack(alignment: .center, spacing: spacing) {
                    ArtistArtworkView(artistName: artist.name, size: artworkSize)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.25), radius: 22, y: 12)
                        .scaleEffect(heroVisible ? 1 : 0.92)
                        .opacity(heroVisible ? 1 : 0)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("ARTIST")
                            .font(.caption.weight(.bold))
                            .tracking(1.3)
                            .foregroundStyle(.secondary)

                        Text(artist.name)
                            .font(.system(size: min(max(textWidth * 0.16, 27), 40), weight: .bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)

                        Text("\(albums.count) \(albums.count == 1 ? "Album" : "Albums") • \(artist.tracks.count) \(artist.tracks.count == 1 ? "Song" : "Tracks") • \(formatDuration(totalDuration))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            artistPlayButton
                            artistShuffleButton
                        }
                        .frame(maxWidth: textWidth)
                        .padding(.top, 2)
                    }
                    .frame(width: textWidth, alignment: .leading)
                }
                .padding(.horizontal, padding)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
            )
        }

        return AnyView(
            VStack(spacing: 10) {
                ArtistArtworkView(artistName: artist.name, size: min(maxWidth * 0.62, 230))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
                    .scaleEffect(heroVisible ? 1 : 0.92)
                    .opacity(heroVisible ? 1 : 0)

                Text("ARTIST")
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)

                Text(artist.name)
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text("\(albums.count) \(albums.count == 1 ? "Album" : "Albums") • \(artist.tracks.count) \(artist.tracks.count == 1 ? "Song" : "Tracks") • \(formatDuration(totalDuration))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    artistPlayButton
                    artistShuffleButton
                }
                .frame(maxWidth: 360)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        )
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(albums) { album in
                            albumCard(album)
                                .frame(width: min(190, UIScreen.main.bounds.width * 0.42))
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
        .padding(.vertical, 22)
        .background(.thinMaterial.opacity(0.45))
    }

    private func albumCard(_ album: AlbumGroup) -> some View {
        NavigationLink {
            AlbumDetailView(album: album, library: library, transitionNamespace: transitionNamespace)
                .navigationTransition(.zoom(sourceID: album.id, in: transitionNamespace))
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                LazyAlbumArtwork(url: album.artworkURL)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .matchedTransitionSource(id: album.id, in: transitionNamespace) { source in
                        source
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
                    }

                Text(album.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text("\(album.tracks.count) \(album.tracks.count == 1 ? "Song" : "Tracks")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
