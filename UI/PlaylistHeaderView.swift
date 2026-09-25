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
        GeometryReader { proxy in
            let narrow = proxy.size.width < 820
            let coverSize = narrow
                ? min(112, max(82, (proxy.size.width - 54) / 3.05))
                : 156

            VStack(alignment: .leading, spacing: 0) {
                coverMarquee(
                    availableWidth: proxy.size.width,
                    coverSize: coverSize
                )
                .frame(height: coverSize * 1.22)
                .padding(.bottom, narrow ? 16 : 18)

                if narrow {
                    VStack(alignment: .leading, spacing: 16) {
                        titleBlock(compact: true)

                        actionBar
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    HStack(alignment: .center, spacing: 24) {
                        titleBlock(compact: false)
                            .frame(maxWidth: 480, alignment: .leading)
                            .layoutPriority(1)

                        actionBar
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }

                Spacer(minLength: 2)
            }
            .frame(maxWidth: 1320)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, narrow ? 22 : 34)
            .padding(.top, narrow ? 6 : 8)
        }
        .frame(
            minHeight: 265,
            idealHeight: 292,
            maxHeight: 320
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
                // A restrained glow makes the center artwork feel like the
                // "hero" without washing the other covers out.
                if count > 0 {
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [
                                    .white.opacity(0.11),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 8,
                                endRadius: coverSize * 1.65
                            )
                        )
                        .frame(
                            width: coverSize * 3.0,
                            height: coverSize * 1.2
                        )
                        .blur(radius: 18)
                        .allowsHitTesting(false)

                    ForEach(
                        (centerIndex - visibleRadius)...(centerIndex + visibleRadius),
                        id: \.self
                    ) { sequenceIndex in
                        let distance = CGFloat(sequenceIndex - centerIndex) - CGFloat(localPhase)
                        let x = distance * stride
                        let normalizedDistance = min(
                            abs(distance) / CGFloat(visibleRadius + 0.25),
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
                        .offset(x: x, y: y)
                        .opacity(opacity)
                        .blur(radius: blur)
                        .shadow(
                            color: .black.opacity(0.18 + focus * 0.12),
                            radius: 7 + focus * 8,
                            y: 4 + focus * 4
                        )
                        .overlay {
                            if abs(distance) < 0.5 {
                                RoundedRectangle(
                                    cornerRadius: min(18, coverSize * 0.13),
                                    style: .continuous
                                )
                                .stroke(
                                    .white.opacity(0.18 + focus * 0.12),
                                    lineWidth: 1
                                )
                            }
                        }
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
        HStack(spacing: 10) {
            Button(action: playAll) {
                Label("Play", systemImage: "play.fill")
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .frame(width: 100)
            }
            .buttonStyle(ToyakoPrimaryButtonStyle())

            Button(action: shuffleAll) {
                Label("Shuffle", systemImage: "shuffle")
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .frame(width: 120)
            }
            .buttonStyle(ToyakoSecondaryButtonStyle())

            Button(action: onAddSongs) {
                Label("Add Songs", systemImage: "plus")
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .frame(width: 130)
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
