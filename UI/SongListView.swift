import SwiftUI

struct SongListView: View {
    let tracks: [LocalTrack]
    let allTracks: [LocalTrack]
    let library: LocalLibrary
    var playlistID: UUID? = nil
    var headerView: AnyView? = nil
    @EnvironmentObject var audioManager: AudioEngineManager

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let header = headerView {
                    header.padding(.bottom, 16)
                }

                if !tracks.isEmpty {
                    HStack {
                        Text("SONGS")
                            .font(.caption.weight(.bold))
                            .tracking(1.1)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(tracks.count)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, ToyakoDesign.Metrics.screenHorizontal)
                    .padding(.bottom, 8)
                }

                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    HStack(spacing: 14) {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: 24, alignment: .trailing)

                        LazyArtwork(
                            url: library.artworkURL(for: track),
                            size: ToyakoArtworkSize.row,
                            cornerRadius: ToyakoDesign.Metrics.artworkSmallRadius
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.title)
                                .font(.headline)
                                .lineLimit(1)

                            Text("\(track.artist) — \(track.album)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        Text(formatTime(track.duration))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, ToyakoDesign.Metrics.screenHorizontal)
                    .padding(.vertical, 11)
                    .contentShape(
                        RoundedRectangle(
                            cornerRadius: ToyakoDesign.Metrics.controlRadius,
                            style: .continuous
                        )
                    )
                    .onTapGesture {
                        audioManager.play(track: track)
                    }
                    .contextMenu {
                        if let pID = playlistID {
                            Button(role: .destructive) {
                                library.removeTrackFromPlaylist(playlistID: pID, trackURL: track.url)
                            } label: { Label("Remove from Playlist", systemImage: "trash") }
                        }
                        Button {
                            audioManager.playNext(track)
                        } label: {
                            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                        }

                        Button {
                            audioManager.enqueue([track])
                        } label: {
                            Label("Add to Queue", systemImage: "text.badge.plus")
                        }

                        Menu("Add to Playlist") {
                            ForEach(library.playlists) { pl in
                                Button(pl.name) { library.addTracksToPlaylist(playlistID: pl.id, trackURLs: [track.url]) }
                            }
                        }
                    }
                    
                    Divider().padding(.leading, 72)
                }
            }
            .padding(.vertical)
        }
    }

    private func formatTime(_ duration: TimeInterval) -> String {
        return String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)
    }
}
import SwiftUI

struct TrackGridView: View {
    let tracks: [LocalTrack]
    let library: LocalLibrary

    @EnvironmentObject private var audioManager: AudioEngineManager

    private let columns = [
        GridItem(.adaptive(minimum: 180), spacing: 18)
    ]

    private var bleedArtworkURL: URL? {
        audioManager.currentTrack.flatMap { library.artworkURL(for: $0) }
            ?? tracks.first.flatMap { library.artworkURL(for: $0) }
    }

    var body: some View {
        ZStack {
            ArtworkBleedPageBackground(artworkURL: bleedArtworkURL)

            GeometryReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    CenteredLibraryGrid(
                    items: tracks,
                    availableWidth: proxy.size.width - (ToyakoDesign.Metrics.screenHorizontal * 2),
                    minimumItemWidth: 180,
                    rowSpacing: 24,
                    columnSpacing: 18
                ) { track in
                    TrackGridCard(track: track, library: library) {
                        audioManager.play(track: track)
                    }
                }
                .padding(.horizontal, ToyakoDesign.Metrics.screenHorizontal)
                .padding(.top, ToyakoDesign.Metrics.screenTop)
                .padding(.bottom, ToyakoDesign.Metrics.screenBottom + 24)
            }
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            }
        }
    }
}

private struct TrackGridCard: View {
    let track: LocalTrack
    let library: LocalLibrary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                LazyArtwork(
                    url: library.artworkURL(for: track),
                    size: 180,
                    cornerRadius: ToyakoDesign.Metrics.artworkSmallRadius
                )
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .toyakoArtwork(cornerRadius: ToyakoDesign.Metrics.artworkSmallRadius)

                Text(track.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(track.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(track.album)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(formatDuration(track.duration))
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .toyakoCard(cornerRadius: ToyakoDesign.Metrics.cardRadius)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                action()
            } label: {
                Label("Play", systemImage: "play.fill")
            }

        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

