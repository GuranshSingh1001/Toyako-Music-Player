import SwiftUI

struct AlbumGridView: View {
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
                        AlbumDetailView(album: album, library: library)
                    } label: {
                        AlbumCard(album: album)
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

    @EnvironmentObject var audioManager: AudioEngineManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
            let isPortrait = width < 700 || verticalSizeClass == .regular
            let isWide = width >= 900 && !isPortrait

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if isWide {
                        wideHeader
                    } else {
                        compactHeader(maxWidth: width)
                    }

                    tracksSection
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.bottom, 100)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        }
        .navigationTitle(album.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.84)) {
                artworkVisible = true
            }
        }
    }

    // MARK: Wide iPad / Landscape

    private var wideHeader: some View {
        HStack(alignment: .center, spacing: 46) {
            artwork(size: 350)
                .frame(maxWidth: 390)

            VStack(alignment: .leading, spacing: 14) {
                Text("ALBUM")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)

                Text(album.name)
                    .font(.system(size: 38, weight: .bold))
                    .lineLimit(3)
                    .minimumScaleFactor(0.72)

                Text(album.artist)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)

                Text("\(album.tracks.count) \(album.tracks.count == 1 ? "Song" : "Tracks") • \(formatTotalDuration(totalDuration))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    playButton
                    shuffleButton
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: 520, alignment: .leading)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: 1100)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 42)
        .padding(.vertical, 34)
    }

    // MARK: Portrait / Resized

    private func compactHeader(maxWidth: CGFloat) -> some View {
        let size = min(maxWidth * 0.66, 310)

        return VStack(spacing: 16) {
            artwork(size: size)

            VStack(spacing: 6) {
                Text(album.name)
                    .font(.system(size: maxWidth < 500 ? 26 : 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.72)

                Text(album.artist)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("\(album.tracks.count) \(album.tracks.count == 1 ? "Song" : "Tracks") • \(formatTotalDuration(totalDuration))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 650)

            HStack(spacing: 12) {
                playButton
                shuffleButton
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, min(maxWidth * 0.08, 32))
        .padding(.top, 22)
        .padding(.bottom, 30)
    }

    private func artwork(size: CGFloat) -> some View {
        LazyAlbumArtwork(url: album.artworkURL, cornerRadius: 20)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.26), radius: 26, y: 14)
            .scaleEffect(artworkVisible ? 1 : 0.94)
            .opacity(artworkVisible ? 1 : 0)
            .animation(.spring(response: 0.48, dampingFraction: 0.84), value: artworkVisible)
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

            Text("Tracks")
                .font(.title2.bold())
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 8)

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
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func formatTrackDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
