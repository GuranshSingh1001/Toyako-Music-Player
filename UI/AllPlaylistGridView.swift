import SwiftUI

struct AllPlaylistsGridView: View {
    @Namespace private var playlistTransitionNamespace

    let playlists: [Playlist]
    let library: LocalLibrary

    var onAddSongs: (Playlist) -> Void
    var onRename: (Playlist) -> Void
    var onDelete: (Playlist) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 170), spacing: 22)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 28) {
                ForEach(playlists) { playlist in
                    let playlistTracks = library.tracks.filter { playlist.trackURLs.contains($0.url) }

                    NavigationLink {
                        SongListView(
                            tracks: playlistTracks,
                            allTracks: playlistTracks,
                            library: library,
                            playlistID: playlist.id,
                            headerView: AnyView(
                                PlaylistHeaderView(
                                    playlist: playlist,
                                    tracks: playlistTracks,
                                    onAddSongs: { onAddSongs(playlist) }
                                )
                            )
                        )
                        .navigationTitle(playlist.name)
                        .navigationBarTitleDisplayMode(.inline)
                        .navigationTransition(.zoom(sourceID: playlist.id, in: playlistTransitionNamespace))
                    } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            PlaylistArtwork(
                                tracks: playlistTracks,
                                playlistName: playlist.name,
                                playlistID: playlist.id
                            )
                            .matchedTransitionSource(id: playlist.id, in: playlistTransitionNamespace)
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: .black.opacity(0.18), radius: 10, y: 6)

                            Text(playlist.name)
                                .font(.headline)
                                .lineLimit(1)

                            Text("\(playlistTracks.count) \(playlistTracks.count == 1 ? "track" : "tracks")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            onAddSongs(playlist)
                        } label: {
                            Label("Add Songs", systemImage: "plus")
                        }

                        Button {
                            onRename(playlist)
                        } label: {
                            Label("Edit Name", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            onDelete(playlist)
                        } label: {
                            Label("Delete Playlist", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 100)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
    }
}

// MARK: - Animated Playlist Artwork

struct PlaylistArtwork: View {
    let tracks: [LocalTrack]
    let playlistName: String
    var playlistID: UUID? = nil

    @State private var revealed = false
    @State private var drifting = false

    private var seed: Int {
        stableSeed(for: playlistID ?? UUID())
    }

    private var style: Int {
        abs(seed) % 8
    }

    private var artworkURLs: [URL] {
        guard !tracks.isEmpty else { return [] }
        // Always build a dense 4x4 field. Reusing artwork is intentional for
        // small playlists so there are no empty holes in the square.
        return (0..<16).map { index in
            tracks[(index * 3 + abs(seed)) % tracks.count].url
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            ZStack {
                if artworkURLs.isEmpty {
                    emptyArtwork
                } else {
                    denseCollage(side: side)
                }

                LinearGradient(
                    colors: [
                        .black.opacity(0.04),
                        .clear,
                        .black.opacity(0.20)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .allowsHitTesting(false)
            }
            .clipped()
            .contentShape(Rectangle())
            .onAppear {
                withAnimation(.spring(response: 0.58, dampingFraction: 0.78)) {
                    revealed = true
                }
                withAnimation(
                    .easeInOut(duration: 8.5 + Double(abs(seed % 5)))
                    .repeatForever(autoreverses: true)
                    .delay(0.45)
                ) {
                    drifting = true
                }
            }
        }
    }

    @ViewBuilder
    private func denseCollage(side: CGFloat) -> some View {
        let cardSide = side * 0.285
        let positions = densePositions(side: side)
        let rotations = rotationPattern

        ZStack {
            ForEach(Array(artworkURLs.enumerated()), id: \.offset) { index, url in
                let position = positions[index]
                let rotation = rotations[index]
                let row = index / 4
                let phase = CGFloat((index * 11 + abs(seed)) % 7) / 7
                let drift = drifting
                    ? -side * (0.018 + phase * 0.026)
                    : 0

                LazyArtwork(
                    url: url,
                    size: cardSide,
                    cornerRadius: cardSide * 0.075
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cardSide * 0.075, style: .continuous)
                        .stroke(.white.opacity(0.28), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.30), radius: 6, y: 3)
                .rotationEffect(.degrees(revealed ? rotation : rotation * 2.2))
                .scaleEffect(revealed ? 1 : 0.76)
                .offset(
                    x: revealed ? position.width + drift * CGFloat(row + 1) : position.width * 1.35,
                    y: revealed ? position.height : position.height * 1.35
                )
                .opacity(revealed ? 1 : 0)
                .animation(
                    .spring(response: 0.58, dampingFraction: 0.80)
                        .delay(Double(index) * 0.028),
                    value: revealed
                )
                .animation(
                    .easeInOut(duration: 8.5 + Double(abs(seed % 5)))
                        .repeatForever(autoreverses: true),
                    value: drifting
                )
                .zIndex(Double(index))
            }
        }
    }

    private func densePositions(side: CGFloat) -> [CGSize] {
        let s = side
        let baseX: [CGFloat] = [-0.375, -0.125, 0.125, 0.375]
        let baseY: [CGFloat] = [-0.375, -0.125, 0.125, 0.375]

        // Build the small pattern table explicitly instead of using a nested
        // map/closure. Swift's type checker can spend an excessive amount of
        // time inferring the nested generic types in the closure above.
        var patterns = Array(repeating: [CGSize](), count: 8)

        for pattern in 0..<8 {
            var result: [CGSize] = []
            result.reserveCapacity(16)

            for row in 0..<4 {
                for col in 0..<4 {
                    var x = baseX[col]
                    var y = baseY[row]

                    switch pattern {
                    case 0:
                        x += row.isMultiple(of: 2) ? -0.012 : 0.012
                    case 1:
                        y += col.isMultiple(of: 2) ? 0.014 : -0.014
                    case 2:
                        x += CGFloat(row - 1) * 0.012
                        y += CGFloat(col - 1) * 0.008
                    case 3:
                        x += CGFloat((col + row) % 3 - 1) * 0.014
                    case 4:
                        y += CGFloat((col * 2 + row) % 3 - 1) * 0.013
                    case 5:
                        x += col == row ? 0.018 : -0.006
                    case 6:
                        x += row == 3 - col ? -0.018 : 0.006
                    default:
                        x += CGFloat((col * 3 + row) % 4) * 0.010 - 0.015
                    }

                    result.append(CGSize(width: x * s, height: y * s))
                }
            }

            patterns[pattern] = result
        }

        return patterns[style]
    }

    private var rotationPattern: [Double] {
        let patterns: [[Double]] = [
            [-4, 2, -3, 5, 3, -5, 2, -2, -3, 4, -1, 3, 5, -2, 3, -4],
            [5, -2, 4, -4, -3, 4, -1, 5, 2, -5, 3, -2, -4, 2, -3, 4],
            [-2, 5, -4, 2, 4, -3, 5, -2, -5, 2, -1, 4, 3, -4, 2, -3],
            [4, -4, 2, -5, -2, 3, -4, 2, 5, -2, 4, -3, -3, 5, -2, 3],
            [-5, 3, -2, 4, 2, -4, 5, -3, -2, 5, -4, 2, 4, -3, 5, -2],
            [3, -5, 4, -2, -4, 2, -5, 3, 2, -3, 5, -4, -2, 4, -3, 5],
            [-3, 4, -5, 2, 5, -2, 3, -4, -5, 3, -2, 4, 2, -4, 5, -3],
            [2, -3, 5, -4, -5, 2, -3, 4, 4, -2, 3, -5, -4, 5, -2, 3]
        ]
        return patterns[style]
    }

    private var emptyArtwork: some View {
        AbstractPlaylistCover(playlistID: playlistID ?? UUID())
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 34, weight: .semibold))
                    Text(playlistName)
                        .font(.headline)
                        .lineLimit(2)
                }
                .foregroundStyle(.white.opacity(0.9))
            }
    }

    private func stableSeed(for id: UUID) -> Int {
        var value = 0
        for byte in id.uuidString.utf8 {
            value = (value &* 31) &+ Int(byte)
        }
        return value == Int.min ? 0 : value
    }
}
