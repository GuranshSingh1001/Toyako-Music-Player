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

    // MARK: Album Hero — same visual language as the iPad Artist page

    private func wideHero(width: CGFloat) -> some View {
        let artworkSize = min(max(width * 0.38, 280), 520)

        return HStack(alignment: .center, spacing: min(max(width * 0.06, 32), 88)) {
            VStack(alignment: .leading, spacing: 10) {
                Text("ALBUM")
                    .font(.caption.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)

                Text(album.name)
                    .font(.system(size: min(max(width * 0.055, 38), 58), weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                Text(album.artist)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text("\(sortedTracks.count) \(sortedTracks.count == 1 ? "Song" : "Tracks") • \(formatTotalDuration(totalDuration))")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    playButton
                    shuffleButton
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            LazyAlbumArtwork(url: album.artworkURL, cornerRadius: 24)
                .frame(width: artworkSize, height: artworkSize)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.28), radius: 28, y: 14)
                .scaleEffect(artworkVisible ? 1 : 0.92)
                .opacity(artworkVisible ? 1 : 0)
        }
        .padding(.horizontal, min(max(width * 0.055, 32), 88))
        .frame(maxWidth: 1280)
        .frame(maxWidth: .infinity)
        .frame(height: min(max(artworkSize + 30, 360), 500))
        .padding(.top, 8)
    }

    private func compactHero(width: CGFloat) -> some View {
        if width >= 420 {
            return AnyView(
                HStack(spacing: 24) {
                    LazyAlbumArtwork(url: album.artworkURL, cornerRadius: 20)
                        .frame(width: min(max(width * 0.40, 180), 250), height: min(max(width * 0.40, 180), 250))
                        .shadow(color: .black.opacity(0.25), radius: 22, y: 12)
                        .scaleEffect(artworkVisible ? 1 : 0.92)
                        .opacity(artworkVisible ? 1 : 0)

                    VStack(alignment: .leading, spacing: 7) {
                        Text("ALBUM")
                            .font(.caption.weight(.bold))
                            .tracking(1.3)
                            .foregroundStyle(.secondary)

                        Text(album.name)
                            .font(.system(size: min(max(width * 0.075, 30), 40), weight: .bold))
                            .lineLimit(2)

                        Text(album.artist)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        Text("\(sortedTracks.count) \(sortedTracks.count == 1 ? "Song" : "Tracks") • \(formatTotalDuration(totalDuration))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            playButton
                            shuffleButton
                        }
                        .padding(.top, 3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
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

                HStack(spacing: 10) {
                    playButton
                    shuffleButton
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        )
    }

    private var playButton: some View {
        Button(action: playAlbum) {
            Label("Play", systemImage: "play.fill")
                .font(.headline)
                .frame(minWidth: 112)
        }
        .buttonStyle(HeroPrimaryButtonStyle())
    }

    private var shuffleButton: some View {
        Button(action: shuffleAlbum) {
            Label("Shuffle", systemImage: "shuffle")
                .font(.headline)
                .frame(minWidth: 112)
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
