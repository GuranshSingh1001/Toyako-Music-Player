import SwiftUI

struct PlaylistHeaderView: View {
    let playlist: Playlist
    let tracks: [LocalTrack]
    let library: LocalLibrary
    let onAddSongs: () -> Void

    private let coverSpacing: CGFloat = 12
    private let marqueeDuration: TimeInterval = 22

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 760
            let coverSize = compact
                ? min(112, max(82, (proxy.size.width - 54) / 3.05))
                : 132

            VStack(alignment: .leading, spacing: 0) {
                coverMarquee(
                    availableWidth: proxy.size.width,
                    coverSize: coverSize
                )
                .frame(height: coverSize)
                .padding(.bottom, compact ? 22 : 28)

                if compact {
                    VStack(alignment: .leading, spacing: 16) {
                        titleBlock(compact: true)
                        compactActionBar
                    }
                } else {
                    HStack(alignment: .bottom, spacing: 24) {
                        titleBlock(compact: false)

                        Spacer(minLength: 20)

                        actionBar
                    }
                }

                Spacer(minLength: 12)
            }
            .frame(maxWidth: 1320)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, compact ? 22 : 34)
            .padding(.top, compact ? 8 : 16)
        }
        .frame(minHeight: 330, idealHeight: 365, maxHeight: 405)
    }

    private func titleBlock(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(playlist.name)
                .font(
                    .system(
                        size: compact ? 34 : 52,
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

    // A TimelineView drives the marquee from the current time instead of
    // relying on a one-shot SwiftUI state animation. This keeps the covers
    // moving after parent/layout updates and while the window is resized.
    private func coverMarquee(
        availableWidth: CGFloat,
        coverSize: CGFloat
    ) -> some View {
        let count = max(tracks.count, 1)
        let sequenceWidth = CGFloat(count) * (coverSize + coverSpacing)

        return TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let progress = tracks.count > 1
                ? (elapsed.truncatingRemainder(dividingBy: marqueeDuration))
                    / marqueeDuration
                : 0

            HStack(spacing: coverSpacing) {
                coverSequence(size: coverSize)
                coverSequence(size: coverSize)
            }
            .offset(x: -sequenceWidth * progress)
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
            Button {
                playAll()
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.subheadline.bold())
            }
            .buttonStyle(ToyakoPrimaryButtonStyle())

            Button {
                shuffleAll()
            } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .font(.subheadline.bold())
            }
            .buttonStyle(ToyakoSecondaryButtonStyle())

            Button(action: onAddSongs) {
                Label("Add Songs", systemImage: "plus")
                    .font(.subheadline.bold())
            }
            .buttonStyle(ToyakoSecondaryButtonStyle())
        }
    }

    // Narrow windows use icon controls rather than allowing button labels
    // to compress into vertically stacked letters.
    private var compactActionBar: some View {
        HStack(spacing: 10) {
            Button(action: playAll) {
                Image(systemName: "play.fill")
            }
            .accessibilityLabel("Play")
            .buttonStyle(ToyakoPrimaryButtonStyle())
            .frame(width: 58)

            Button(action: shuffleAll) {
                Image(systemName: "shuffle")
            }
            .accessibilityLabel("Shuffle")
            .buttonStyle(ToyakoSecondaryButtonStyle())
            .frame(width: 58)

            Button(action: onAddSongs) {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add Songs")
            .buttonStyle(ToyakoSecondaryButtonStyle())
            .frame(width: 58)

            Spacer(minLength: 0)
        }
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
