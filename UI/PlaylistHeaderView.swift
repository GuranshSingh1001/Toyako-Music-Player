import SwiftUI

struct PlaylistHeaderView: View {
    let playlist: Playlist
    let tracks: [LocalTrack]
    let library: LocalLibrary
    let onAddSongs: () -> Void

    @EnvironmentObject private var audioManager: AudioEngineManager

    private let coverSpacing: CGFloat = 12
    private let marqueeSpeed: CGFloat = 18

    var body: some View {
        let coverSize = ToyakoArtworkSize.libraryArtwork

        VStack(alignment: .leading, spacing: 0) {
            // Keep the marquee in its own measured region. The old outer
            // GeometryReader had a fixed 265...320pt height while its content
            // could become taller during Stage Manager/window resizing. That
            // allowed the action bar and the first song row to overlap.
            GeometryReader { proxy in
                coverMarquee(
                    availableWidth: proxy.size.width,
                    coverSize: coverSize
                )
            }
            .frame(height: coverSize * 1.22)
            .padding(.bottom, 18)

            // ViewThatFits changes between the wide two-column header and the
            // stacked header using the actual available width. No hard width
            // breakpoint is needed, so resizing does not leave controls
            // partially outside the playlist surface.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 24) {
                    titleBlock(compact: false)
                        .frame(width: 430, alignment: .leading)
                        .layoutPriority(1)

                    actionBar
                        .fixedSize(horizontal: true, vertical: false)
                }

                VStack(alignment: .leading, spacing: 16) {
                    titleBlock(compact: true)
                    actionBar
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
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

    // MARK: - Kinetic cover marquee

    private func coverMarquee(
        availableWidth: CGFloat,
        coverSize: CGFloat
    ) -> some View {
        let count = tracks.count
        let spacing = max(18, coverSize * 0.16)
        let stride = coverSize + spacing
        let visibleRadius = 5

        return TimelineView(.animation) { context in
            AnyView(
                marqueeTimelineContent(
                    context: context,
                    count: count,
                    availableWidth: availableWidth,
                    coverSize: coverSize,
                    stride: stride,
                    visibleRadius: visibleRadius
                )
            )
        }
    }

    @ViewBuilder
    private func marqueeTimelineContent(
        context: TimelineViewDefaultContext,
        count: Int,
        availableWidth: CGFloat,
        coverSize: CGFloat,
        stride: CGFloat,
        visibleRadius: Int
    ) -> some View {
            let time = context.date.timeIntervalSinceReferenceDate

            // The phase is measured in artwork widths, so one complete cycle
            // is exactly one playlist length. The item that is at phase N is
            // always centered; there is no independent "focus frame" that can
            // drift away from the artwork.
            let phase = count > 0
                ? (time * marqueeSpeed / stride)
                    .truncatingRemainder(dividingBy: Double(count))
                : 0

            let centerIndex = Int(floor(phase))
            let localPhase = phase - Double(centerIndex)

            ZStack {
                if count > 0 {
                    ForEach(
                        (centerIndex - visibleRadius)...(centerIndex + visibleRadius),
                        id: \.self
                    ) { sequenceIndex in
                        let distance = CGFloat(sequenceIndex - centerIndex) - CGFloat(localPhase)
                        let x = distance * stride
                        let normalizedDistance = min(
                            abs(distance) / (CGFloat(visibleRadius) + 0.25),
                            1
                        )

                        // Smooth "cover-flow" focus curve.
                        let focus = pow(1 - normalizedDistance, 2.0)
                        let scale = 0.78 + focus * 0.25
                        let opacity = 0.48 + focus * 0.52
                        let blur = (1 - focus) * 1.1
                        let rotation = max(
                            -14,
                            min(
                                14,
                                -distance * 7.5
                            )
                        )
                        let y = -focus * coverSize * 0.08

                        // A tiny damped "tick" happens once as each new cover
                        // reaches the center. It gives the marquee a tactile
                        // feeling without making the artwork visibly wobble
                        // during the entire movement.
                        let tickEnvelope = exp(-localPhase * 42.0)
                        let tickWave = sin(localPhase * .pi * 14.0) * tickEnvelope
                        let tickStrength = min(1, max(0, focus))
                        let microShakeX = tickWave * 2.2 * tickStrength
                        let microShakeRotation = tickWave * 0.65 * tickStrength

                        let trackIndex = positiveModulo(
                            sequenceIndex,
                            count
                        )

                        LazyArtwork(
                            url: library.artworkURL(for: tracks[trackIndex]),
                            size: coverSize,
                            cornerRadius: min(18, coverSize * 0.13)
                        )
                        .frame(
                            width: coverSize,
                            height: coverSize
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: min(18, coverSize * 0.13),
                                style: .continuous
                            )
                        )
                        .scaleEffect(scale)
                        .rotation3DEffect(
                            .degrees(rotation),
                            axis: (x: 0, y: 1, z: 0),
                            perspective: 0.55
                        )
                        .rotationEffect(.degrees(microShakeRotation))
                        .offset(x: x + microShakeX, y: y)
                        .opacity(opacity)
                        .blur(radius: blur)
                        .shadow(
                            color: .black.opacity(0.18 + focus * 0.12),
                            radius: 7 + focus * 8,
                            y: 4 + focus * 4
                        )
                        .zIndex(Double(100 - abs(distance)))
                        .accessibilityHidden(true)
                    }
                } else {
                    RoundedRectangle(
                        cornerRadius: min(18, coverSize * 0.13),
                        style: .continuous
                    )
                    .fill(.quaternary)
                    .frame(width: coverSize, height: coverSize)
                    .overlay {
                        Image(systemName: "music.note.list")
                            .font(
                                .system(
                                    size: coverSize * 0.24,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(
                width: availableWidth,
                height: coverSize * 1.22
            )
            .clipped()
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.07),
                        .init(color: .black, location: 0.93),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
    }

    private func positiveModulo(
        _ value: Int,
        _ modulus: Int
    ) -> Int {
        let remainder = value % modulus
        return remainder >= 0 ? remainder : remainder + modulus
    }

    private var actionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                playButton.frame(minWidth: 96, maxWidth: 110)
                shuffleButton.frame(minWidth: 112, maxWidth: 126)
                addSongsButton.frame(minWidth: 122, maxWidth: 138)
            }

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    playButton
                    shuffleButton
                }
                addSongsButton
            }
        }
    }

    private var playButton: some View {
        Button(action: playAll) {
            Label("Play", systemImage: "play.fill")
                .font(.subheadline.bold())
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ToyakoPrimaryButtonStyle())
    }

    private var shuffleButton: some View {
        Button(action: shuffleAll) {
            Label("Shuffle", systemImage: "shuffle")
                .font(.subheadline.bold())
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ToyakoSecondaryButtonStyle())
    }

    private var addSongsButton: some View {
        Button(action: onAddSongs) {
            Label("Add Songs", systemImage: "plus")
                .font(.subheadline.bold())
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ToyakoSecondaryButtonStyle())
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
