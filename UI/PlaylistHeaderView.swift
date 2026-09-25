import SwiftUI

struct PlaylistHeaderView: View {
    let playlist: Playlist
    let tracks: [LocalTrack]
    let library: LocalLibrary
    let onAddSongs: () -> Void

    @EnvironmentObject private var audioManager: AudioEngineManager

    private let coverSpacing: CGFloat = 12
    private let marqueeSpeed: CGFloat = 26

    var body: some View {
        GeometryReader { proxy in
            let narrow = proxy.size.width < 820
            let coverSize = narrow
                ? min(112, max(82, (proxy.size.width - 54) / 3.05))
                : 148

            VStack(alignment: .leading, spacing: 0) {
                coverMarquee(
                    availableWidth: proxy.size.width,
                    coverSize: coverSize
                )
                .frame(height: coverSize * 1.48)
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
            minHeight: 285,
            idealHeight: 310,
            maxHeight: 340
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
        let stride = coverSize + coverSpacing
        let sequenceWidth = max(stride * CGFloat(max(count, 1)), stride)
        let viewportHeight = coverSize * 1.48

        return TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let cycleDuration = max(sequenceWidth / marqueeSpeed, 0.001)
            let phase = CGFloat(
                time.truncatingRemainder(dividingBy: TimeInterval(cycleDuration))
            )

            // Repeat on the exact distance of one artwork sequence. Because the
            // phase and the visual seam share the same period, the loop never
            // jumps when the TimelineView clock wraps around.
            let travel = phase * marqueeSpeed

            ZStack {
                // Soft atmospheric glow behind the center artwork.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                .white.opacity(0.16),
                                .clear
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: coverSize * 1.35
                        )
                    )
                    .frame(
                        width: coverSize * 2.7,
                        height: coverSize * 1.35
                    )
                    .blur(radius: 16)
                    .opacity(count == 0 ? 0 : 1)

                if count > 0 {
                    // Three copies give the ribbon enough runway on both sides
                    // of the viewport. The exact same phase drives every copy,
                    // making the loop visually seamless.
                    ForEach(0..<(count * 3), id: \.self) { itemIndex in
                        let trackIndex = itemIndex % count
                        let copyIndex = itemIndex / count
                        let baseX =
                            CGFloat(trackIndex) * stride +
                            CGFloat(copyIndex - 1) * sequenceWidth

                        let rawX =
                            baseX -
                            travel +
                            availableWidth / 2 -
                            sequenceWidth / 2

                        let x = wrappedCenterX(
                            rawX,
                            sequenceWidth: sequenceWidth,
                            viewportWidth: availableWidth
                        )

                        let normalized =
                            min(
                                abs(x - availableWidth / 2) / max(availableWidth / 2, 1),
                                1
                            )

                        let focus = pow(1 - normalized, 2.2)

                        // Center cover = larger, sharper and slightly lifted.
                        // Edge covers = smaller, tilted and more transparent.
                        let scale = 0.78 + (focus * 0.28)
                        let rotation = (x - availableWidth / 2)
                            / max(availableWidth / 2, 1)
                            * -13
                        let lift = -focus * coverSize * 0.12
                        let opacity = 0.55 + (focus * 0.45)
                        let blur = (1 - focus) * 1.5

                        LazyArtwork(
                            url: library.artworkURL(for: tracks[trackIndex]),
                            size: coverSize,
                            cornerRadius: min(18, coverSize * 0.13)
                        )
                        .frame(width: coverSize, height: coverSize)
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
                            perspective: 0.72
                        )
                        .offset(x: x, y: lift)
                        .opacity(opacity)
                        .blur(radius: blur)
                        .shadow(
                            color: .black.opacity(0.16 + focus * 0.16),
                            radius: 8 + focus * 10,
                            y: 5 + focus * 4
                        )
                        .zIndex(Double(focus))
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
                            .font(.system(size: coverSize * 0.24, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(
                width: availableWidth,
                height: viewportHeight
            )
            .clipped()
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
            .overlay(alignment: .center) {
                // A tiny focus highlight makes the center position feel intentional
                // without adding another moving element.
                RoundedRectangle(
                    cornerRadius: min(20, coverSize * 0.14),
                    style: .continuous
                )
                .stroke(.white.opacity(0.10), lineWidth: 1)
                .frame(
                    width: coverSize * 1.06,
                    height: coverSize * 1.06
                )
                .allowsHitTesting(false)
            }
        }
    }

    private func wrappedCenterX(
        _ x: CGFloat,
        sequenceWidth: CGFloat,
        viewportWidth: CGFloat
    ) -> CGFloat {
        let halfViewport = viewportWidth / 2
        let minX = -halfViewport - sequenceWidth
        let maxX = halfViewport + sequenceWidth

        if x < minX {
            return x + sequenceWidth
        }

        if x > maxX {
            return x - sequenceWidth
        }

        return x
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
