import SwiftUI

struct PlaylistHeaderView: View {
    let playlist: Playlist
    let tracks: [LocalTrack]
    let library: LocalLibrary
    let onAddSongs: () -> Void

    @EnvironmentObject private var audioManager: AudioEngineManager

    private let coverSpacing: CGFloat = 12
    private let marqueeSpeed: CGFloat = 22 // points per second — independent of track count

    var body: some View {
        GeometryReader { proxy in
            let narrow = proxy.size.width < 820
            let coverSize = narrow
                ? min(112, max(82, (proxy.size.width - 54) / 3.05))
                : 132

            VStack(alignment: .leading, spacing: 0) {
                coverMarquee(
                    availableWidth: proxy.size.width,
                    coverSize: coverSize
                )
                .frame(height: coverSize)
                .padding(.bottom, narrow ? 22 : 26)

                if narrow {
                    // Stage Manager / narrow windows:
                    // keep the complete button labels and put the controls
                    // underneath the playlist information instead of squeezing
                    // them into a narrow horizontal column.
                    VStack(alignment: .leading, spacing: 16) {
                        titleBlock(compact: true)

                        actionBar
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    // Wide windows: title + metadata and the complete action
                    // buttons share one horizontal baseline.
                    HStack(alignment: .center, spacing: 28) {
                        titleBlock(compact: false)
                            .layoutPriority(2)

                        Spacer(minLength: 16)

                        actionBar
                            .layoutPriority(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }

                Spacer(minLength: 12)
            }
            .frame(maxWidth: 1320)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, narrow ? 22 : 34)
            .padding(.top, narrow ? 8 : 16)
        }
        .frame(
            minHeight: 350,
            idealHeight: 385,
            maxHeight: 425
        )
    }

    private func titleBlock(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(playlist.name)
                .font(
                    .system(
                        size: compact ? 36 : 52,
                        weight: .bold
                    )
                )
                .tracking(compact ? -0.6 : -1.2)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: false, vertical: true)

            Text(
                "\(tracks.count) \(tracks.count == 1 ? "Song" : "Tracks") • \(totalDurationString)"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private func coverMarquee(
        availableWidth: CGFloat,
        coverSize: CGFloat
    ) -> some View {
        let count = max(tracks.count, 1)
        let singleSequenceWidth =
            CGFloat(count) * coverSize +
            CGFloat(max(count - 1, 0)) * coverSpacing
        let sequenceWidth = singleSequenceWidth + coverSpacing

        return TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let distance = CGFloat(
                elapsed.truncatingRemainder(
                    dividingBy: TimeInterval(
                        max(sequenceWidth / marqueeSpeed, 0.001)
                    )
                )
            ) * marqueeSpeed

            HStack(spacing: coverSpacing) {
                coverSequence(
                    size: coverSize,
                    availableWidth: availableWidth
                )
                coverSequence(
                    size: coverSize,
                    availableWidth: availableWidth
                )
            }
            .offset(x: -distance)
            .frame(
                width: availableWidth,
                height: coverSize * 1.22,
                alignment: .leading
            )
            .clipped()
            .coordinateSpace(name: "playlistMarquee")
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.055),
                        .init(color: .black, location: 0.945),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .frame(height: coverSize)
        }
    }

    private func coverSequence(
        size: CGFloat,
        availableWidth: CGFloat
    ) -> some View {
        HStack(spacing: coverSpacing) {
            ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                GeometryReader { geo in
                    let frame = geo.frame(in: .named("playlistMarquee"))
                    let centerX = availableWidth / 2
                    let distanceFromCenter = frame.midX - centerX
                    let normalizedDistance = min(
                        abs(distanceFromCenter) / max(centerX, 1),
                        1
                    )

                    // A subtle Cover Flow treatment: the center artwork is
                    // slightly larger/brighter, while the outer covers turn
                    // away and recede. It stays entirely driven by position,
                    // so it remains smooth at the fixed marquee speed.
                    let scale = 1.0 - (normalizedDistance * 0.10)
                    let rotation = Double(
                        max(-1, min(1, distanceFromCenter / max(centerX, 1)))
                    ) * -11
                    let lift = sin(
                        Double(index) * 0.85 +
                        geo.frame(in: .named("playlistMarquee")).midX / 90
                    ) * 1.8

                    LazyArtwork(
                        url: library.artworkURL(for: track),
                        size: size,
                        cornerRadius: min(16, size * 0.12)
                    )
                    .frame(width: size, height: size)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: min(16, size * 0.12),
                            style: .continuous
                        )
                    )
                    .scaleEffect(scale)
                    .rotation3DEffect(
                        .degrees(rotation),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.65
                    )
                    .opacity(0.78 + (1 - normalizedDistance) * 0.22)
                    .offset(y: lift)
                    .shadow(
                        color: .black.opacity(
                            0.10 + (1 - normalizedDistance) * 0.12
                        ),
                        radius: 8,
                        y: 4
                    )
                }
                .frame(width: size, height: size * 1.18)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button(action: playAll) {
                Label("Play", systemImage: "play.fill")
                    .font(.subheadline.bold())
                    .lineLimit(1)
            }
            .buttonStyle(ToyakoPrimaryButtonStyle())

            Button(action: shuffleAll) {
                Label("Shuffle", systemImage: "shuffle")
                    .font(.subheadline.bold())
                    .lineLimit(1)
            }
            .buttonStyle(ToyakoSecondaryButtonStyle())

            Button(action: onAddSongs) {
                Label("Add Songs", systemImage: "plus")
                    .font(.subheadline.bold())
                    .lineLimit(1)
            }
            .buttonStyle(ToyakoSecondaryButtonStyle())
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func playAll() {
        guard !tracks.isEmpty else { return }
        audioManager.startQueue(tracks: tracks, startIndex: 0)
    }

    private func shuffleAll() {
        guard !tracks.isEmpty else { return }

        if !audioManager.isShuffle {
            audioManager.toggleShuffle()
        }

        audioManager.startQueue(
            tracks: tracks,
            startIndex: Int.random(in: 0..<tracks.count)
        )
    }

    private var totalDurationString: String {
        let seconds = max(0, Int(tracks.reduce(0) { $0 + $1.duration }))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        return hours > 0
            ? "\(hours) hr \(minutes) min"
            : "\(minutes) min"
    }
}
