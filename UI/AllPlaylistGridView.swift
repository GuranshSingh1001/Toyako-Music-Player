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
                    // Long press is intentionally the only playlist action affordance.
                    // This replaces the old visible three-dot button.
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

    private var urls: [URL] {
        Array(tracks.prefix(4)).map(\.url)
    }

    private var seed: Int {
        stableSeed(for: playlistID ?? UUID())
    }

    private var style: Int {
        Int(UInt(bitPattern: seed) % 5)
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.thinMaterial)

                if urls.isEmpty {
                    emptyArtwork
                } else {
                    ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                        animatedCard(
                            url: url,
                            index: index,
                            count: urls.count,
                            side: side
                        )
                    }
                }

                // A single glass layer makes the different layouts feel like
                // one designed cover instead of a collection of thumbnails.
                LinearGradient(
                    colors: [
                        .white.opacity(0.16),
                        .clear,
                        .black.opacity(0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onAppear {
                withAnimation(.spring(response: 0.58, dampingFraction: 0.76).delay(Double(seed % 7) * 0.018)) {
                    revealed = true
                }
            }
        }
    }

    @ViewBuilder
    private func animatedCard(
        url: URL,
        index: Int,
        count: Int,
        side: CGFloat
    ) -> some View {
        let target = cardLayout(index: index, count: count, side: side)
        let startOffset = CGSize(
            width: target.offset.width * 1.8,
            height: target.offset.height * 1.8
        )

        LazyArtwork(
            url: url,
            size: target.size,
            cornerRadius: min(16, target.size * 0.08)
        )
        .overlay {
            RoundedRectangle(cornerRadius: min(16, target.size * 0.08), style: .continuous)
                .stroke(.white.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.30), radius: 8, y: 5)
        .scaleEffect(revealed ? 1 : 0.72)
        .rotationEffect(.degrees(revealed ? target.rotation : target.rotation * 2.8))
        .offset(revealed ? target.offset : startOffset)
        .opacity(revealed ? 1 : 0)
        .animation(
            .spring(response: 0.58, dampingFraction: 0.76)
                .delay(Double(index) * 0.055 + Double(seed % 5) * 0.012),
            value: revealed
        )
        .zIndex(Double(index))
    }

    private struct CardLayout {
        let size: CGFloat
        let offset: CGSize
        let rotation: Double
    }

    private func cardLayout(index: Int, count: Int, side: CGFloat) -> CardLayout {
        let variant = style

        switch variant {
        case 0:
            // Fan / scattered stack
            let size = count == 1 ? side * 0.80 : side * 0.64
            let positions: [CGSize] = [
                CGSize(width: -side * 0.16, height: side * 0.06),
                CGSize(width: side * 0.16, height: -side * 0.05),
                CGSize(width: -side * 0.06, height: -side * 0.19),
                CGSize(width: side * 0.08, height: side * 0.19)
            ]
            let rotations: [Double] = [-7, 6, -3, 8]
            return CardLayout(size: size, offset: positions[index % positions.count], rotation: rotations[index % rotations.count])

        case 1:
            // Diagonal cascade
            let size = count == 1 ? side * 0.82 : side * 0.67
            let amount = side * 0.18
            return CardLayout(
                size: size,
                offset: CGSize(width: -amount + CGFloat(index) * amount * 0.68, height: amount - CGFloat(index) * amount * 0.62),
                rotation: -8 + Double(index) * 5
            )

        case 2:
            // Offset tiles
            let size = count == 1 ? side * 0.80 : side * 0.61
            let positions: [CGSize] = [
                CGSize(width: -side * 0.18, height: -side * 0.15),
                CGSize(width: side * 0.18, height: -side * 0.08),
                CGSize(width: -side * 0.10, height: side * 0.17),
                CGSize(width: side * 0.15, height: side * 0.15)
            ]
            let rotations: [Double] = [-3, 5, 4, -6]
            return CardLayout(size: size, offset: positions[index % positions.count], rotation: rotations[index % rotations.count])

        case 3:
            // Vertical film-strip style
            let size = count == 1 ? side * 0.80 : side * 0.60
            let x = side * 0.20 * CGFloat(index - max(0, count - 1) / 2)
            let y = side * 0.11 * CGFloat(index % 2 == 0 ? -1 : 1)
            return CardLayout(size: size, offset: CGSize(width: x, height: y), rotation: Double(index - 1) * 5)

        default:
            // Tight pile with one dominant front card.
            let size = count == 1 ? side * 0.82 : side * 0.66
            let positions: [CGSize] = [
                CGSize(width: -side * 0.13, height: side * 0.08),
                CGSize(width: side * 0.15, height: side * 0.03),
                CGSize(width: -side * 0.03, height: -side * 0.16),
                CGSize(width: side * 0.04, height: side * 0.17)
            ]
            let rotations: [Double] = [6, -5, -8, 4]
            return CardLayout(size: size, offset: positions[index % positions.count], rotation: rotations[index % rotations.count])
        }
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
        // Do not use UUID.hashValue: Swift's hash seeding can change between
        // launches. UUID bytes give each playlist a stable visual identity.
        id.uuidString.utf8.reduce(5381) { (($0 << 5) &- $0) &+ Int($1) }
    }
}
