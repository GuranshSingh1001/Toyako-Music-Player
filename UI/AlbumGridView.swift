import SwiftUI

struct AlbumGridView: View {
    @Namespace private var albumTransitionNamespace

    let albums: [AlbumGroup]
    let library: LocalLibrary

    private let columns = [
        GridItem(.adaptive(minimum: 170), spacing: 22)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 26) {
                ForEach(albums) { album in
                    NavigationLink {
                        AlbumDetailView(album: album, library: library, transitionNamespace: albumTransitionNamespace)
                    } label: {
                        AlbumCard(album: album)
                            .matchedTransitionSource(id: album.id, in: albumTransitionNamespace)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 100)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
    }
}

private struct AlbumCard: View {
    let album: AlbumGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyAlbumArtwork(url: album.artworkURL)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.16), radius: 8, y: 4)

            Text(album.name)
                .font(.headline)
                .lineLimit(1)

            Text(album.artist)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text("\(album.tracks.count) \(album.tracks.count == 1 ? "Song" : "Tracks")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Album Detail

struct AlbumDetailView: View {
    let album: AlbumGroup
    let library: LocalLibrary
    let transitionNamespace: Namespace.ID

    @EnvironmentObject var audioManager: AudioEngineManager
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var artworkVisible = false

    private var sortedTracks: [LocalTrack] {
        album.tracks.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private var totalDuration: TimeInterval {
        sortedTracks.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let isPortrait = width < 760 || verticalSizeClass == .regular
            let isWide = width >= 900 && !isPortrait

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if isWide {
                        wideHero(width: width)
                    } else {
                        compactHero(width: width)
                    }

                    tracksSection
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.bottom, 110)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationTransition(.zoom(sourceID: album.id, in: transitionNamespace))
        .onAppear {
            withAnimation(.spring(response: 0.52, dampingFraction: 0.84)) {
                artworkVisible = true
            }
        }
    }

    // MARK: iPad / Landscape

    private func wideHero(width: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Match the artist detail experience: the artwork becomes the hero
            // rather than sitting alone in the middle of a large empty page.
            LazyAlbumArtwork(url: album.artworkURL, cornerRadius: 0)
                .frame(maxWidth: .infinity)
                .frame(height: 390)
                .clipped()
                .overlay {
                    LinearGradient(
                        colors: [
                            .black.opacity(0.04),
                            .black.opacity(0.28),
                            .black.opacity(0.90)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            HStack(alignment: .bottom, spacing: 26) {
                LazyAlbumArtwork(url: album.artworkURL, cornerRadius: 18)
                    .frame(width: min(230, width * 0.22), height: min(230, width * 0.22))
                    .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
                    .scaleEffect(artworkVisible ? 1 : 0.94)
                    .opacity(artworkVisible ? 1 : 0)

                VStack(alignment: .leading, spacing: 8) {
                    Text("ALBUM")
                        .font(.caption.weight(.bold))
                        .tracking(1.3)
                        .foregroundStyle(.white.opacity(0.78))

                    Text(album.name)
                        .font(.system(size: min(42, width * 0.043), weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)

                    Text(album.artist)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(2)

                    Text("\(sortedTracks.count) \(sortedTracks.count == 1 ? "Song" : "Tracks") • \(formatTotalDuration(totalDuration))")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.76))

                    HStack(spacing: 12) {
                        playButton
                        shuffleButton
                    }
                    .padding(.top, 5)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: 1120)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.bottom, 28)
        }
        .frame(height: 390)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }

    // MARK: Portrait / Narrow / Resized

    private func compactHero(width: CGFloat) -> some View {
        let artworkSize = min(max(width * 0.48, 180), 250)
        let veryNarrow = width < 520

        return VStack(spacing: 12) {
            LazyAlbumArtwork(url: album.artworkURL, cornerRadius: 20)
                .frame(width: artworkSize, height: artworkSize)
                .shadow(color: .black.opacity(0.28), radius: 22, y: 12)
                .scaleEffect(artworkVisible ? 1 : 0.94)
                .opacity(artworkVisible ? 1 : 0)

            Text("ALBUM")
                .font(.caption.weight(.bold))
                .tracking(1.25)
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            Text(album.name)
                .font(.system(size: veryNarrow ? 28 : 34, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)

            Text(album.artist)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text("\(sortedTracks.count) \(sortedTracks.count == 1 ? "Song" : "Tracks") • \(formatTotalDuration(totalDuration))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                playButton
                shuffleButton
            }
            .padding(.top, 3)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, min(max(width * 0.07, 18), 34))
        .padding(.top, 18)
        .padding(.bottom, 18)
    }

    private var playButton: some View {
        Button(action: playAlbum) {
            Label("Play", systemImage: "play.fill")
                .font(.headline)
                .frame(minWidth: 112)
        }
        .buttonStyle(.borderedProminent)
    }

    private var shuffleButton: some View {
        Button(action: shuffleAlbum) {
            Label("Shuffle", systemImage: "shuffle")
                .font(.headline)
                .frame(minWidth: 112)
        }
        .buttonStyle(.bordered)
    }

    private var tracksSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()

            HStack(alignment: .firstTextBaseline) {
                Text("Tracks")
                    .font(.title2.bold())
                Spacer()
                Text("\(sortedTracks.count)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 6)

            ForEach(Array(sortedTracks.enumerated()), id: \.element.id) { index, track in
                AlbumTrackRow(track: track, number: index + 1) {
                    audioManager.startQueue(
                        tracks: sortedTracks,
                        startIndex: index,
                        shuffle: false
                    )
                }

                if track.id != sortedTracks.last?.id {
                    Divider().padding(.leading, 92)
                }
            }
        }
    }

    private func playAlbum() {
        guard !sortedTracks.isEmpty else { return }
        audioManager.startQueue(tracks: sortedTracks, startIndex: 0, shuffle: false)
    }

    private func shuffleAlbum() {
        guard !sortedTracks.isEmpty else { return }
        audioManager.startQueue(
            tracks: sortedTracks,
            startIndex: Int.random(in: 0..<sortedTracks.count),
            shuffle: true
        )
    }

    private func formatTotalDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours) hr \(minutes) min" : "\(minutes) min"
    }
}

private struct AlbumTrackRow: View {
    let track: LocalTrack
    let number: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text("\(number)")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 26)

                LazyArtwork(url: track.url, size: 52, cornerRadius: 8)

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    Text(track.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Text(formatTrackDuration(track.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func formatTrackDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
