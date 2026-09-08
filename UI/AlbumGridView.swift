import SwiftUI

struct AlbumGridView: View {
    let albums: [AlbumGroup]
    let library: LocalLibrary

    private let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 20)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: columns,
                spacing: 24
            ) {
                ForEach(albums) { album in
                    NavigationLink {
                        AlbumDetailView(
                            album: album,
                            library: library
                        )
                    } label: {
                        AlbumCard(album: album)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .padding(.bottom, 80)
        }
    }
}

// MARK: - Album Card

private struct AlbumCard: View {
    let album: AlbumGroup

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            AlbumArtwork(
                artworkData:
                    album.artworkData
            )
            .frame(
                maxWidth: .infinity
            )
            .aspectRatio(
                1,
                contentMode: .fit
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
            )

            Text(album.name)
                .font(.headline)
                .foregroundColor(.primary)
                .lineLimit(1)

            Text(album.artist)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Text(
                "\(album.tracks.count) "
                + (
                    album.tracks.count == 1
                    ? "Song"
                    : "Songs"
                )
            )
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }
}

// MARK: - Album Detail

struct AlbumDetailView: View {
    let album: AlbumGroup
    let library: LocalLibrary

    @EnvironmentObject var audioManager:
        AudioEngineManager

    @State private var artworkVisible = false

    private var sortedTracks: [LocalTrack] {
        album.tracks.sorted {
            $0.title.localizedCaseInsensitiveCompare(
                $1.title
            ) == .orderedAscending
        }
    }

    private var totalDuration:
        TimeInterval {
        sortedTracks.reduce(0) {
            $0 + $1.duration
        }
    }

    var body: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: 0
            ) {

                // MARK: Album Header

                VStack(spacing: 20) {
                    AlbumArtwork(
                        artworkData:
                            album.artworkData
                    )
                    .frame(
                        width:
                            min(
                                300,
                                UIScreen.main.bounds.width
                                * 0.62
                            ),
                        height:
                            min(
                                300,
                                UIScreen.main.bounds.width
                                * 0.62
                            )
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 16,
                            style: .continuous
                        )
                    )
                    .shadow(
                        color:
                            .black.opacity(0.25),
                        radius: 25,
                        y: 12
                    )
                    .scaleEffect(
                        artworkVisible
                            ? 1.0
                            : 0.94
                    )
                    .opacity(
                        artworkVisible
                            ? 1.0
                            : 0.0
                    )

                    VStack(
                        spacing: 5
                    ) {
                        Text(album.name)
                            .font(
                                .system(
                                    size: 28,
                                    weight: .bold
                                )
                            )
                            .multilineTextAlignment(
                                .center
                            )

                        Text(album.artist)
                            .font(
                                .system(
                                    size: 18,
                                    weight: .medium
                                )
                            )
                            .foregroundColor(
                                .secondary
                            )

                        Text(
                            "\(album.tracks.count) "
                            + (
                                album.tracks.count == 1
                                ? "Song"
                                : "Songs"
                            )
                            + " • "
                            + formatTotalDuration(
                                totalDuration
                            )
                        )
                        .font(.subheadline)
                        .foregroundColor(
                            .secondary
                        )
                    }
                    .frame(
                        maxWidth: .infinity
                    )

                    HStack(
                        spacing: 12
                    ) {
                        Button {
                            playAlbum()
                        } label: {
                            Label(
                                "Play",
                                systemImage:
                                    "play.fill"
                            )
                            .font(
                                .headline
                            )
                            .frame(
                                minWidth: 110
                            )
                        }
                        .buttonStyle(
                            .borderedProminent
                        )

                        Button {
                            shuffleAlbum()
                        } label: {
                            Label(
                                "Shuffle",
                                systemImage:
                                    "shuffle"
                            )
                            .font(
                                .headline
                            )
                            .frame(
                                minWidth: 110
                            )
                        }
                        .buttonStyle(
                            .bordered
                        )
                    }
                }
                .frame(
                    maxWidth: .infinity
                )
                .padding(
                    .horizontal,
                    20
                )
                .padding(
                    .top,
                    20
                )
                .padding(
                    .bottom,
                    28
                )

                Divider()

                // MARK: Songs

                VStack(
                    alignment: .leading,
                    spacing: 0
                ) {
                    Text("Songs")
                        .font(
                            .title2.bold()
                        )
                        .padding(
                            .horizontal,
                            20
                        )
                        .padding(
                            .top,
                            24
                        )
                        .padding(
                            .bottom,
                            8
                        )

                    ForEach(
                        Array(
                            sortedTracks.enumerated()
                        ),
                        id: \.element.id
                    ) {
                        index,
                        track in

                        AlbumTrackRow(
                            track:
                                track,
                            number:
                                index + 1
                        ) {
                            audioManager.startQueue(
                                tracks:
                                    sortedTracks,
                                startIndex:
                                    index
                            )
                        }

                        if track.id !=
                            sortedTracks.last?.id {
                            Divider()
                                .padding(
                                    .leading,
                                    76
                                )
                        }
                    }
                }
            }
        }
        .navigationTitle(
            album.name
        )
        .navigationBarTitleDisplayMode(
            .inline
        )
        .onAppear {
            withAnimation(
                .spring(
                    response: 0.45,
                    dampingFraction: 0.82
                )
            ) {
                artworkVisible = true
            }
        }
    }

    private func playAlbum() {
        guard !sortedTracks.isEmpty
        else {
            return
        }

        audioManager.startQueue(
            tracks:
                sortedTracks,
            startIndex:
                0
        )
    }

    private func shuffleAlbum() {
        guard !sortedTracks.isEmpty
        else {
            return
        }

        if !audioManager.isShuffle {
            audioManager.toggleShuffle()
        }

        let randomIndex =
            Int.random(
                in:
                    0..<sortedTracks.count
            )

        audioManager.startQueue(
            tracks:
                sortedTracks,
            startIndex:
                randomIndex
        )
    }

    private func formatTotalDuration(
        _ duration:
            TimeInterval
    ) -> String {
        let seconds =
            max(
                0,
                Int(
                    duration.rounded()
                )
            )

        let hours =
            seconds / 3600

        let minutes =
            (seconds % 3600) / 60

        if hours > 0 {
            return
                "\(hours) hr \(minutes) min"
        }

        return
            "\(minutes) min"
    }
}

// MARK: - Album Track Row

private struct AlbumTrackRow: View {
    let track: LocalTrack
    let number: Int
    let action: () -> Void

    var body: some View {
        Button(
            action:
                action
        ) {
            HStack(spacing: 14) {

                Text(
                    "\(number)"
                )
                .font(
                    .system(
                        size: 14,
                        weight: .medium,
                        design: .monospaced
                    )
                )
                .foregroundColor(
                    .secondary
                )
                .frame(
                    width: 24
                )

                if let data =
                    track.artworkData,
                   let image =
                    UIImage(data: data) {

                    Image(
                        uiImage:
                            image
                    )
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: 48,
                        height: 48
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 7,
                            style: .continuous
                        )
                    )
                } else {
                    RoundedRectangle(
                        cornerRadius: 7,
                        style: .continuous
                    )
                    .fill(
                        Color.gray.opacity(
                            0.18
                        )
                    )
                    .frame(
                        width: 48,
                        height: 48
                    )
                    .overlay {
                        Image(
                            systemName:
                                "music.note"
                        )
                        .foregroundColor(
                            .secondary
                        )
                    }
                }

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(
                        track.title
                    )
                    .font(
                        .body.weight(
                            .medium
                        )
                    )
                    .foregroundColor(
                        .primary
                    )
                    .lineLimit(1)

                    Text(
                        track.artist
                    )
                    .font(
                        .caption
                    )
                    .foregroundColor(
                        .secondary
                    )
                    .lineLimit(1)
                }

                Spacer()

                Text(
                    formatTrackDuration(
                        track.duration
                    )
                )
                .font(
                    .caption.monospacedDigit()
                )
                .foregroundColor(
                    .secondary
                )
            }
            .padding(
                .horizontal,
                20
            )
            .padding(
                .vertical,
                9
            )
            .contentShape(
                Rectangle()
            )
        }
        .buttonStyle(
            .plain
        )
    }

    private func formatTrackDuration(
        _ duration:
            TimeInterval
    ) -> String {
        let seconds =
            max(
                0,
                Int(duration)
            )

        return String(
            format:
                "%d:%02d",
            seconds / 60,
            seconds % 60
        )
    }
}

// MARK: - Shared Album Artwork

struct AlbumArtwork: View {
    let artworkData: Data?

    var body: some View {
        Group {
            if let artworkData,
               let image =
                    UIImage(
                        data:
                            artworkData
                    ) {

                Image(
                    uiImage:
                        image
                )
                .resizable()
                .scaledToFill()

            } else {
                RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
                .fill(
                    LinearGradient(
                        colors: [
                            Color.gray.opacity(
                                0.28
                            ),
                            Color.gray.opacity(
                                0.12
                            )
                        ],
                        startPoint:
                            .topLeading,
                        endPoint:
                            .bottomTrailing
                    )
                )
                .overlay {
                    Image(
                        systemName:
                            "square.stack"
                    )
                    .font(
                        .system(
                            size: 42,
                            weight: .medium
                        )
                    )
                    .foregroundColor(
                        .secondary
                    )
                }
            }
        }
    }
}