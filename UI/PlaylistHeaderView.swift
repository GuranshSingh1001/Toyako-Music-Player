import SwiftUI

struct PlaylistHeaderView: View {
    let playlist: Playlist
    let tracks: [LocalTrack]
    let onAddSongs: () -> Void

    @EnvironmentObject var audioManager:
        AudioEngineManager

    var body: some View {
        VStack(
            alignment:
                .leading,
            spacing:
                18
        ) {

            HStack(
                alignment:
                    .top,
                spacing:
                    20
            ) {

                PlaylistArtwork(
                    tracks:
                        tracks,
                    playlistName:
                        playlist.name
                )
                .frame(
                    width:
                        145,
                    height:
                        145
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius:
                            14,
                        style:
                            .continuous
                    )
                )
                .shadow(
                    color:
                        .black.opacity(
                            0.25
                        ),
                    radius:
                        12,
                    y:
                        6
                )

                VStack(
                    alignment:
                        .leading,
                    spacing:
                        7
                ) {

                    Text(
                        "PLAYLIST"
                    )
                    .font(
                        .caption.bold()
                    )
                    .foregroundColor(
                        .secondary
                    )

                    Text(
                        playlist.name
                    )
                    .font(
                        .system(
                            size: 26,
                            weight: .bold
                        )
                    )
                    .lineLimit(
                        2
                    )

                    Text(
                        "\(tracks.count) "
                        + (
                            tracks.count == 1
                            ? "Song"
                            : "Songs"
                        )
                        + " • "
                        + totalDurationString
                    )
                    .font(
                        .subheadline
                    )
                    .foregroundColor(
                        .secondary
                    )

                    Spacer(
                        minLength:
                            2
                    )
                }

                Spacer(
                    minLength:
                        0
                )
            }

            HStack(
                spacing:
                    12
            ) {

                Button {
                    guard !tracks.isEmpty
                    else {
                        return
                    }

                    audioManager.startQueue(
                        tracks:
                            tracks,
                        startIndex:
                            0
                    )
                } label: {
                    Label(
                        "Play",
                        systemImage:
                            "play.fill"
                    )
                    .font(
                        .subheadline.bold()
                    )
                }
                .buttonStyle(
                    .borderedProminent
                )

                Button {
                    guard !tracks.isEmpty
                    else {
                        return
                    }

                    if !audioManager.isShuffle {
                        audioManager.toggleShuffle()
                    }

                    let index =
                        Int.random(
                            in:
                                0..<tracks.count
                        )

                    audioManager.startQueue(
                        tracks:
                            tracks,
                        startIndex:
                            index
                    )
                } label: {
                    Label(
                        "Shuffle",
                        systemImage:
                            "shuffle"
                    )
                    .font(
                        .subheadline.bold()
                    )
                }
                .buttonStyle(
                    .bordered
                )

                Button(
                    action:
                        onAddSongs
                ) {
                    Label(
                        "Add Songs",
                        systemImage:
                            "plus"
                    )
                    .font(
                        .subheadline.bold()
                    )
                }
                .buttonStyle(
                    .bordered
                )
            }
        }
        .padding(
            .horizontal,
            20
        )
        .padding(
            .vertical,
            18
        )
    }

    private var totalDurationString:
        String {

        let total =
            tracks.reduce(
                0
            ) {
                $0 + $1.duration
            }

        let seconds =
            max(
                0,
                Int(
                    total
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