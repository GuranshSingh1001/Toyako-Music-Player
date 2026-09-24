import SwiftUI

struct AllPlaylistsGridView: View {
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
                    } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            PlaylistArtwork(
                                tracks: playlistTracks,
                                playlistName: playlist.name,
                                playlistID: playlist.id
                            )
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
        abs(seed) % 6
    }

    private var artworkURLs: [URL] {
        guard !tracks.isEmpty else { return [] }
        // Repeat the playlist artwork so the cover can fill the entire square.
        // This deliberately does not stop at four images.
        return (0..<max(9, min(12, tracks.count * 2))).map { index in
            tracks[index % tracks.count].url
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.black.opacity(0.94))

                if artworkURLs.isEmpty {
                    emptyArtwork
                } else {
                    collage(side: side)
                }

                LinearGradient(
                    colors: [
                        .white.opacity(0.12),
                        .clear,
                        .black.opacity(0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onAppear {
                withAnimation(.spring(response: 0.58, dampingFraction: 0.78)) {
                    revealed = true
                }
                // The artwork keeps a subtle, slow horizontal drift after the
                // entrance animation instead of becoming a static collage.
                withAnimation(
                    .easeInOut(duration: 9.0 + Double(abs(seed % 5)))
                    .repeatForever(autoreverses: true)
                    .delay(0.8)
                ) {
                    drifting = true
                }
            }
        }
    }

    @ViewBuilder
    private func collage(side: CGFloat) -> some View {
        let cardSide = side * 0.43
        let positions = layoutPositions(side: side)
        let rotations = layoutRotations

        ZStack {
            // Two overlapping passes make the cover feel continuously filled,
            // even when a playlist contains only one or two songs.
            ForEach(Array(artworkURLs.enumerated()), id: \.offset) { index, url in
                let position = positions[index % positions.count]
                let rotation = rotations[index % rotations.count]
                let phase = Double((index * 13 + abs(seed)) % 9) / 9.0
                let drift = drifting ? -(side * (0.035 + CGFloat(phase) * 0.035)) : 0

                LazyArtwork(
                    url: url,
                    size: cardSide,
                    cornerRadius: cardSide * 0.10
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cardSide * 0.10, style: .continuous)
                        .stroke(.white.opacity(0.24), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.34), radius: 7, y: 4)
                .scaleEffect(revealed ? 1 : 0.72)
                .rotationEffect(.degrees(revealed ? rotation : rotation * 2.5))
                .offset(
                    x: revealed ? position.width + drift : position.width * 1.8,
                    y: revealed ? position.height : position.height * 1.8
                )
                .opacity(revealed ? 1 : 0)
                .animation(
                    .spring(response: 0.58, dampingFraction: 0.78)
                        .delay(Double(index) * 0.045),
                    value: revealed
                )
                .animation(
                    .easeInOut(duration: 9.0 + Double(abs(seed % 5)))
                        .repeatForever(autoreverses: true),
                    value: drifting
                )
                .zIndex(Double(index))
            }
        }
    }

    private func layoutPositions(side: CGFloat) -> [CGSize] {
        let s = side
        let patterns: [[CGSize]] = [
            [
                .init(width: -0.23*s, height: -0.22*s), .init(width: 0, height: -0.24*s), .init(width: 0.23*s, height: -0.20*s),
                .init(width: -0.24*s, height: 0.01*s), .init(width: 0.01*s, height: 0.01*s), .init(width: 0.25*s, height: 0.02*s),
                .init(width: -0.22*s, height: 0.23*s), .init(width: 0.02*s, height: 0.22*s), .init(width: 0.24*s, height: 0.24*s)
            ],
            [
                .init(width: -0.25*s, height: -0.12*s), .init(width: -0.02*s, height: -0.25*s), .init(width: 0.24*s, height: -0.10*s),
                .init(width: -0.22*s, height: 0.13*s), .init(width: 0.02*s, height: 0.02*s), .init(width: 0.25*s, height: 0.15*s),
                .init(width: -0.12*s, height: 0.26*s), .init(width: 0.13*s, height: 0.25*s), .init(width: 0.01*s, height: -0.05*s)
            ],
            [
                .init(width: -0.25*s, height: -0.22*s), .init(width: 0.01*s, height: -0.23*s), .init(width: 0.25*s, height: -0.20*s),
                .init(width: -0.18*s, height: 0), .init(width: 0.08*s, height: -0.02*s), .init(width: 0.26*s, height: 0.04*s),
                .init(width: -0.25*s, height: 0.23*s), .init(width: 0, height: 0.25*s), .init(width: 0.23*s, height: 0.23*s)
            ],
            [
                .init(width: -0.18*s, height: -0.24*s), .init(width: 0.10*s, height: -0.25*s), .init(width: 0.26*s, height: -0.03*s),
                .init(width: -0.26*s, height: -0.02*s), .init(width: 0, height: 0), .init(width: 0.17*s, height: 0.18*s),
                .init(width: -0.22*s, height: 0.23*s), .init(width: 0.02*s, height: 0.25*s), .init(width: 0.25*s, height: 0.20*s)
            ],
            [
                .init(width: -0.24*s, height: -0.18*s), .init(width: 0.02*s, height: -0.26*s), .init(width: 0.25*s, height: -0.17*s),
                .init(width: -0.26*s, height: 0.08*s), .init(width: 0.01*s, height: -0.01*s), .init(width: 0.24*s, height: 0.08*s),
                .init(width: -0.18*s, height: 0.25*s), .init(width: 0.08*s, height: 0.22*s), .init(width: 0.27*s, height: 0.24*s)
            ],
            [
                .init(width: -0.25*s, height: -0.25*s), .init(width: 0.0*s, height: -0.16*s), .init(width: 0.25*s, height: -0.25*s),
                .init(width: -0.17*s, height: 0.04*s), .init(width: 0.11*s, height: 0.03*s), .init(width: 0.27*s, height: 0.02*s),
                .init(width: -0.24*s, height: 0.25*s), .init(width: 0.02*s, height: 0.20*s), .init(width: 0.24*s, height: 0.25*s)
            ]
        ]

        return patterns[style]
    }

    private var layoutRotations: [Double] {
        let base = [
            [-5, 2, 7, 3, -4, 5, -7, 3, -2],
            [7, -4, 3, -6, 2, 8, -3, 5, -7],
            [-3, 6, -5, 5, -2, 4, -7, 3, 6],
            [6, -7, 4, -3, 5, -5, 2, 7, -4],
            [-7, 3, 6, -5, 2, -4, 7, -3, 5],
            [4, -6, 2, 7, -4, 5, -7, 3, -2]
        ]
        return base[style].map(Double.init)
    }

    private var emptyArtwork: some View {
        AbstractPlaylistCover(playlistID: playlistID ?? UUID())
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 34, weight: .semibold))
                    Text(playlistName)
                        .font(.caption.weight(.bold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .foregroundStyle(.white)
                .padding(12)
                .background(.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(12)
            }
    }

    private func stableSeed(for id: UUID) -> Int {
        id.uuidString.utf8.reduce(5381) { (($0 << 5) &- $0) &+ Int($1) }
    }
}
