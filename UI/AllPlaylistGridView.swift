import SwiftUI

struct AllPlaylistsGridView: View {
    @Namespace private var playlistTransitionNamespace
    @State private var activePlaylistTransitionID: UUID?

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
                    let isActive = activePlaylistTransitionID == playlist.id

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
                        .navigationTitle("")
                        .navigationBarTitleDisplayMode(.inline)
                        .navigationTransition(.zoom(sourceID: playlist.id, in: playlistTransitionNamespace))
                        .onDisappear {
                            activePlaylistTransitionID = nil
                        }
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
                    .opacity(isActive ? 0 : 1)
                    .animation(.easeOut(duration: 0.16), value: isActive)
                    .background {
                        Circle()
                            .fill(.black.opacity(0.001))
                            .frame(width: 1, height: 1)
                            .matchedTransitionSource(id: playlist.id, in: playlistTransitionNamespace)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            activePlaylistTransitionID = playlist.id
                        }
                    )
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
            .scrollDisabled(false)
    }
}

// MARK: - Animated Playlist Artwork

struct PlaylistArtwork: View {
    let tracks: [LocalTrack]
    let playlistName: String
    var playlistID: UUID? = nil


    private var seed: Int {
        stableSeed(for: playlistID ?? UUID())
    }

    private var artworkURLs: [URL] {
        guard !tracks.isEmpty else { return [] }
        var generator = SeededRandom(seed: seed)
        var indices = Array(0..<tracks.count)
        generator.shuffle(&indices)

        return (0..<9).map { index in
            tracks[indices[index % indices.count]].url
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            ZStack {
                if artworkURLs.isEmpty {
                    emptyArtwork
                } else {
                    staticCollage(side: side)
                }

                LinearGradient(
                    colors: [
                        .black.opacity(0.02),
                        .clear,
                        .black.opacity(0.16)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .allowsHitTesting(false)
            }
            .clipped()
            .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private func staticCollage(side: CGFloat) -> some View {
        let cards = collageCards(side: side)

        ZStack {
            ForEach(cards) { card in
                LazyArtwork(
                    url: card.url,
                    size: card.size,
                    cornerRadius: card.size * 0.075
                )
                .overlay {
                    RoundedRectangle(cornerRadius: card.size * 0.075, style: .continuous)
                        .stroke(.white.opacity(0.22), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.28), radius: 6, y: 3)
                .rotationEffect(.degrees(card.rotation))
                .offset(card.position)
                .zIndex(Double(card.index))
            }
        }
        .frame(width: side * 1.12, height: side * 1.12)
        .position(x: side * 0.50, y: side * 0.50)
    }

    private func collageCards(side: CGFloat) -> [CollageCard] {
        var generator = SeededRandom(seed: seed)
        let cardSide = side * 0.255
        let step = side * 0.267
        let totalSpan = cardSide + step * 3
        let origin = -totalSpan * 0.50 + cardSide * 0.50

        var cards: [CollageCard] = []
        cards.reserveCapacity(16)

        for row in 0..<4 {
            for column in 0..<4 {
                let index = row * 4 + column
                let jitterX = CGFloat(generator.nextDouble(in: -0.012...0.012)) * side
                let jitterY = CGFloat(generator.nextDouble(in: -0.012...0.012)) * side
                let rotation = generator.nextDouble(in: -5.0...5.0)

                cards.append(
                    CollageCard(
                        index: index,
                        url: artworkURLs[index % artworkURLs.count],
                        size: cardSide,
                        position: CGSize(
                            width: origin + CGFloat(column) * step + jitterX,
                            height: origin + CGFloat(row) * step + jitterY
                        ),
                        rotation: rotation,
                        drift: .zero
                    )
                )
            }
        }

        return cards
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

private struct CollageCard: Identifiable {
    let index: Int
    let url: URL
    let size: CGFloat
    let position: CGSize
    let rotation: Double
    let drift: CGSize

    var id: Int { index }
}

private struct SeededRandom {
    private var state: UInt64

    init(seed: Int) {
        let unsigned = UInt64(bitPattern: Int64(seed))
        state = unsigned == 0 ? 0x9E3779B97F4A7C15 : unsigned
    }

    mutating func nextUInt() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func nextDouble(in range: ClosedRange<Double>) -> Double {
        let value = Double(nextUInt() % 1_000_000) / 1_000_000.0
        return range.lowerBound + value * (range.upperBound - range.lowerBound)
    }

    mutating func shuffle<T>(_ array: inout [T]) {
        guard array.count > 1 else { return }
        for index in stride(from: array.count - 1, through: 1, by: -1) {
            let target = Int(nextUInt() % UInt64(index + 1))
            array.swapAt(index, target)
        }
    }
}
