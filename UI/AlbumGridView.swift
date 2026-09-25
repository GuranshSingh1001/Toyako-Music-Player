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

                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        AlbumDetailHero(
                            album: album,
                            totalDuration: totalDuration,
                            isCompact: proxy.size.width < 700,
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
                    // Never impose a fixed content width on a NavigationStack
                    // destination. On narrow iPad/Stage Manager widths SwiftUI can
                    // give the scroll view a different proposed width than its outer
                    // GeometryReader. A fixed frame then shifts the whole hero to the
                    // right and clips the title/actions. Let the scroll view's viewport
                    // determine the content width instead.
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, ToyakoDesign.Metrics.screenBottom)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        GeometryReader { proxy in
            ZStack {
                Color(uiColor: .systemBackground)

                // Keep the artwork bleed attached to the actual destination
                // viewport. This avoids the artwork/background becoming an
                // independently-sized layer when the window is resized.
                LazyAlbumArtwork(url: album.artworkURL)
                    .frame(
                        width: max(proxy.size.width * 1.45, 560),
                        height: max(proxy.size.height * 0.72, 560)
                    )
                    .scaleEffect(1.18)
                    .blur(radius: 72)
                    .saturation(1.05)
                    .brightness(-0.18)
                    .opacity(0.18)
                    .position(
                        x: proxy.size.width * 0.5,
                        y: min(proxy.size.height * 0.32, 360)
                    )

                // A single uniform veil. Do not use a vertical gradient here:
                // that was the source of the visible top/bottom dual-tone.
                Color.black.opacity(0.24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
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
    let isCompact: Bool
    let availableWidth: CGFloat
    let artworkVisible: Bool
    let playAction: () -> Void
    let shuffleAction: () -> Void

    var body: some View {
        Group {
            if isCompact {
                compactHero
            } else {
                wideHero
            }
        }
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
        VStack(alignment: isCompact ? .center : .leading, spacing: 8) {
            Text(album.name)
                .font(.system(size: isCompact ? 30 : 34, weight: .bold, design: .rounded))
                .multilineTextAlignment(isCompact ? .center : .leading)
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
        let contentWidth = max(0, availableWidth - (ToyakoDesign.Metrics.screenHorizontal * 2))
        let artworkSize = min(320, contentWidth)

        let heroWidth = min(520, contentWidth)
        let buttonWidth = min(430, contentWidth)

        return VStack(spacing: 20) {
            artwork
                .frame(width: artworkSize, height: artworkSize)

            // Use a real width constraint rather than only maxWidth. Text otherwise
            // keeps its intrinsic one-line width and gets clipped on narrow windows.
            information
                .frame(width: heroWidth)

            actions
                .frame(width: buttonWidth)
        }
        .frame(width: contentWidth, alignment: .center)
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
