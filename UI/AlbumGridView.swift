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
            .padding(.horizontal, ToyakoDesign.Metrics.screenHorizontal)
            .padding(.top, ToyakoDesign.Metrics.screenTop)
            .padding(.bottom, ToyakoDesign.Metrics.screenBottom)
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
            LazyAlbumArtwork(
                url: album.artworkURL
            )
            .frame(
                maxWidth: .infinity
            )
            .aspectRatio(
                1,
                contentMode: .fit
            )
            .toyakoArtwork()

            Text(album.name)
                .font(ToyakoDesign.Typography.item)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(album.artist)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(
                "\(album.tracks.count) "
                + (
                    album.tracks.count == 1
                    ? "Song"
                    : "Tracks"
                )
            )
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
            ZStack {
                albumBackground

                ScrollView {
                    VStack(spacing: 0) {
                        AlbumDetailHero(
                            album: album,
                            totalDuration: totalDuration,
                            availableWidth: proxy.size.width,
                            artworkVisible: artworkVisible,
                            playAction: playAlbum,
                            shuffleAction: shuffleAlbum
                        )

                        AlbumTracksSection(
                            tracks: sortedTracks,
                            audioManager: audioManager
                        )
                    }
                    .padding(.bottom, ToyakoDesign.Metrics.screenBottom)
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle(album.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                artworkVisible = true
            }
        }
    }

    private var albumBackground: some View {
        ZStack {
            Color(uiColor: .systemBackground)

            LazyAlbumArtwork(url: album.artworkURL)
                .frame(width: 620, height: 620)
                .scaleEffect(1.25)
                .blur(radius: 70)
                .opacity(0.20)
                .offset(y: -150)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.18),
                    Color(uiColor: .systemBackground).opacity(0.76),
                    Color(uiColor: .systemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private func playAlbum() {
        guard !sortedTracks.isEmpty else { return }
        audioManager.startQueue(tracks: sortedTracks, startIndex: 0)
    }

    private func shuffleAlbum() {
        guard !sortedTracks.isEmpty else { return }

        if !audioManager.isShuffle {
            audioManager.toggleShuffle()
        }

        let randomIndex = Int.random(in: 0..<sortedTracks.count)
        audioManager.startQueue(tracks: sortedTracks, startIndex: randomIndex)
    }
}

// MARK: - Album Detail Hero

private struct AlbumDetailHero: View {
    let album: AlbumGroup
    let totalDuration: TimeInterval
    let availableWidth: CGFloat
    let artworkVisible: Bool
    let playAction: () -> Void
    let shuffleAction: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            wideHero
            compactHero
        }
        .frame(maxWidth: 1100)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, ToyakoDesign.Metrics.screenHorizontal)
        .padding(.top, 22)
        .padding(.bottom, 28)
    }

    private var artwork: some View {
        LazyAlbumArtwork(url: album.artworkURL)
            .aspectRatio(1, contentMode: .fit)
            .toyakoArtwork(cornerRadius: 18)
            .clipped()
            .shadow(color: .black.opacity(0.30), radius: 28, y: 14)
            .scaleEffect(artworkVisible ? 1 : 0.96)
            .opacity(artworkVisible ? 1 : 0)
    }

    private var information: some View {
        VStack(alignment: .center, spacing: 8) {
            Text(album.name)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(3)

            Text(album.artist)
                .font(.system(size: 19, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text("\(album.tracks.count) \(album.tracks.count == 1 ? "Song" : "Tracks")  •  \(formatDuration(totalDuration))")
                .font(ToyakoDesign.Typography.metadata)
                .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button(action: playAction) {
                Label("Play", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ToyakoPrimaryButtonStyle())

            Button(action: shuffleAction) {
                Label("Shuffle", systemImage: "shuffle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ToyakoSecondaryButtonStyle())
        }
        .frame(maxWidth: 430)
    }

    private var wideHero: some View {
        HStack(alignment: .center, spacing: 30) {
            artwork
                .frame(width: 300, height: 300)

            VStack(alignment: .leading, spacing: 20) {
                information
                actions
            }
            .frame(maxWidth: 560, alignment: .leading)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: 980, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private var compactHero: some View {
        let horizontalInset = ToyakoDesign.Metrics.screenHorizontal * 2
        let contentWidth = max(0, availableWidth - horizontalInset)
        let artworkSize = min(320, max(220, contentWidth))
        let textWidth = min(560, contentWidth)
        let actionWidth = min(430, contentWidth)

        return VStack(spacing: 20) {
            artwork
                .frame(width: artworkSize, height: artworkSize)

            information
                .frame(maxWidth: textWidth)

            actions
                .frame(maxWidth: actionWidth)
        }
        .frame(maxWidth: contentWidth)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours) hr \(minutes) min" : "\(minutes) min"
    }
}

// MARK: - Album Tracks

private struct AlbumTracksSection: View {
    let tracks: [LocalTrack]
    let audioManager: AudioEngineManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Tracks")
                    .font(ToyakoDesign.Typography.section)

                Spacer()

                Text("\(tracks.count)")
                    .font(ToyakoDesign.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, ToyakoDesign.Metrics.screenHorizontal)
            .padding(.bottom, 12)

            if tracks.isEmpty {
                Text("No tracks in this album")
                    .font(ToyakoDesign.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, ToyakoDesign.Metrics.screenHorizontal)
                    .padding(.vertical, 24)
            } else {
                ToyakoCard(cornerRadius: ToyakoDesign.Metrics.cardRadius) {
                    VStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            AlbumTrackRow(track: track, number: index + 1) {
                                audioManager.startQueue(tracks: tracks, startIndex: index)
                            }

                            if track.id != tracks.last?.id {
                                Divider()
                                    .padding(.leading, 76)
                            }
                        }
                    }
                }
                .padding(.horizontal, ToyakoDesign.Metrics.screenHorizontal)
            }
        }
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
                .foregroundStyle(.secondary)
                .frame(
                    width: 24
                )

                LazyArtwork(url: track.url, size: ToyakoArtworkSize.compactRow, cornerRadius: ToyakoDesign.Metrics.artworkSmallRadius)

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
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                    Text(
                        track.artist
                    )
                    .font(
                        .caption
                    )
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, ToyakoDesign.Metrics.screenHorizontal)
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
