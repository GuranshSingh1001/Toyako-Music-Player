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
        let sequenceWidth = CGFloat(count) * (coverSize + coverSpacing)

        return TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let distance = CGFloat(elapsed.truncatingRemainder(
                dividingBy: TimeInterval(max(sequenceWidth / marqueeSpeed, 0.001))
            )) * marqueeSpeed

            HStack(spacing: coverSpacing) {
                coverSequence(size: coverSize)
                coverSequence(size: coverSize)
            }
            .offset(x: -distance)
            .frame(
                width: availableWidth,
                height: coverSize,
                alignment: .leading
            )
            .clipped()
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.045),
                        .init(color: .black, location: 0.955),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
    }

    private func coverSequence(size: CGFloat) -> some View {
        HStack(spacing: coverSpacing) {
            ForEach(Array(tracks.enumerated()), id: \.offset) { _, track in
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
