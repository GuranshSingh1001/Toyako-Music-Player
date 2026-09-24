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
                            .navigationTransition(.zoom(sourceID: album.id, in: albumTransitionNamespace))
                    } label: {
                        AlbumCard(album: album, transitionNamespace: albumTransitionNamespace)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 100)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .scrollDisabled(false)
    }
}

private struct AlbumCard: View {
    let album: AlbumGroup
    let transitionNamespace: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyAlbumArtwork(url: album.artworkURL)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .matchedTransitionSource(id: album.id, in: transitionNamespace)
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
    @State private var artworkVisible = true
    @AppStorage(ToyakoPreferences.playTracksByTappingKey) private var playTracksByTapping = false

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
            let isWide = width >= 560 && verticalSizeClass != .regular

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
            .scrollDisabled(false)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // The navigation zoom provides the page entrance animation. Avoid a
        // second hero animation here so scrolling is immediately responsive
        // after returning from the detail page.
    }

    // MARK: Album Hero — same visual language as the iPad Artist page

    private func wideHero(width: CGFloat) -> some View {
        let horizontalPadding = min(max(width * 0.04, 24), 56)
        let available = max(320, width - horizontalPadding * 2)
        let spacing = min(max(available * 0.045, 24), 52)
        let artworkSize = min(max(available * 0.36, 220), 430)
        let textWidth = max(240, available - artworkSize - spacing)

        return HStack(alignment: .center, spacing: spacing) {
            LazyAlbumArtwork(url: album.artworkURL, cornerRadius: 24)
                .frame(width: artworkSize, height: artworkSize)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.28), radius: 28, y: 14)
                .scaleEffect(artworkVisible ? 1 : 0.92)
                .opacity(artworkVisible ? 1 : 0)
                .layoutPriority(1)

            VStack(alignment: .leading, spacing: 10) {
                Text("ALBUM")
                    .font(.caption.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)

                Text(album.name)
                    .font(.system(size: min(max(textWidth * 0.12, 34), 58), weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.68)

                Text(album.artist)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text("\(sortedTracks.count) \(sortedTracks.count == 1 ? "Song" : "Tracks") • \(formatTotalDuration(totalDuration))")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    playButton
                    shuffleButton
                }
                .frame(maxWidth: min(textWidth, 430), alignment: .leading)
                .padding(.top, 6)
            }
            .frame(width: textWidth, alignment: .leading)
        }
        .padding(.horizontal, horizontalPadding)
        .frame(maxWidth: 1280)
        .frame(maxWidth: .infinity)
        .frame(height: min(max(artworkSize + 36, 340), 500))
        .padding(.top, 8)
    }

    private func compactHero(width: CGFloat) -> some View {
        if width >= 420 {
            let padding: CGFloat = 20
            let available = max(280, width - padding * 2)
            let spacing: CGFloat = 18
            let artworkSize = min(max(available * 0.36, 150), 220)
            let textWidth = max(150, available - artworkSize - spacing)

            return AnyView(
                HStack(alignment: .center, spacing: spacing) {
                    LazyAlbumArtwork(url: album.artworkURL, cornerRadius: 20)
                        .frame(width: artworkSize, height: artworkSize)
                        .shadow(color: .black.opacity(0.25), radius: 22, y: 12)
                        .scaleEffect(artworkVisible ? 1 : 0.92)
                        .opacity(artworkVisible ? 1 : 0)

                    VStack(alignment: .leading, spacing: 7) {
                        Text("ALBUM")
                            .font(.caption.weight(.bold))
                            .tracking(1.3)
                            .foregroundStyle(.secondary)

                        Text(album.name)
                            .font(.system(size: min(max(textWidth * 0.16, 27), 40), weight: .bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)

                        Text(album.artist)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        Text("\(sortedTracks.count) \(sortedTracks.count == 1 ? "Song" : "Tracks") • \(formatTotalDuration(totalDuration))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            playButton
                            shuffleButton
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
                LazyAlbumArtwork(url: album.artworkURL, cornerRadius: 20)
                    .frame(width: min(max(width * 0.62, 170), 230), height: min(max(width * 0.62, 170), 230))
                    .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
                    .scaleEffect(artworkVisible ? 1 : 0.92)
                    .opacity(artworkVisible ? 1 : 0)

                Text("ALBUM")
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)

                Text(album.name)
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(album.artist)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("\(sortedTracks.count) \(sortedTracks.count == 1 ? "Song" : "Tracks") • \(formatTotalDuration(totalDuration))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    playButton
                    shuffleButton
                }
                .frame(maxWidth: 360)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        )
    }

    private var playButton: some View {
        Button(action: playAlbum) {
            Label("Play", systemImage: "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(HeroPrimaryButtonStyle())
    }

    private var shuffleButton: some View {
        Button(action: shuffleAlbum) {
            Label("Shuffle", systemImage: "shuffle")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(HeroSecondaryButtonStyle())
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
                    guard playTracksByTapping else { return }
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
