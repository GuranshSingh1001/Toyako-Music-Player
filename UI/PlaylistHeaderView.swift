import SwiftUI

struct PlaylistHeaderView: View {
    let playlist: Playlist
    let tracks: [LocalTrack]
    let library: LocalLibrary
    let onAddSongs: () -> Void

    @EnvironmentObject var audioManager: AudioEngineManager
    @State private var marqueeActive = false

    private let coverSize: CGFloat = 132
    private let coverSpacing: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 760

            VStack(alignment: .leading, spacing: 0) {
                // The playlist's artwork rail is intentionally separate from
                // the title area: covers continuously travel right -> left.
                coverMarquee
                    .frame(height: compact ? 112 : 148)
                    .padding(.bottom, compact ? 20 : 26)

                HStack(alignment: .bottom, spacing: 24) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(playlist.name)
                            .font(.system(size: compact ? 38 : 52, weight: .bold))
                            .tracking(-1.2)
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)

                        Text(
                            "\(tracks.count) \(tracks.count == 1 ? "Song" : "Tracks") • \(totalDurationString)"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 16)

                    actionBar
                }
                .frame(maxWidth: .infinity, alignment: .bottom)
                .padding(.horizontal, compact ? 6 : 4)

                Spacer(minLength: 18)
            }
            .frame(maxWidth: 1320)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, compact ? 24 : 34)
            .padding(.top, compact ? 10 : 18)
        }
        .frame(minHeight: 350, idealHeight: 390, maxHeight: 430)
        .onAppear {
            guard tracks.count > 1 else { return }
            marqueeActive = false
            DispatchQueue.main.async {
                marqueeActive = true
            }
        }
    }

    private var coverMarquee: some View {
        GeometryReader { proxy in
            let sequenceWidth = CGFloat(max(tracks.count, 1)) * (coverSize + coverSpacing)

            HStack(spacing: coverSpacing) {
                coverSequence
                coverSequence
            }
            .frame(height: coverSize)
            .offset(
                x: marqueeActive && tracks.count > 1
                    ? -sequenceWidth
                    : 0
            )
            .animation(
                tracks.count > 1
                    ? .linear(duration: max(16, Double(tracks.count) * 2.4))
                        .repeatForever(autoreverses: false)
                    : nil,
                value: marqueeActive
            )
            .frame(
                width: proxy.size.width,
                height: coverSize,
                alignment: .leading
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
        }
    }

    private var coverSequence: some View {
        ForEach(Array(tracks.enumerated()), id: \.offset) { _, track in
            LazyArtwork(
                url: library.artworkURL(for: track),
                size: coverSize,
                cornerRadius: 16
            )
            .frame(width: coverSize, height: coverSize)
            .clipShape(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                guard !tracks.isEmpty else { return }
                audioManager.startQueue(tracks: tracks, startIndex: 0)
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.subheadline.bold())
            }
            .buttonStyle(ToyakoPrimaryButtonStyle())

            Button {
                guard !tracks.isEmpty else { return }
                if !audioManager.isShuffle {
                    audioManager.toggleShuffle()
                }
                audioManager.startQueue(
                    tracks: tracks,
                    startIndex: Int.random(in: 0..<tracks.count)
                )
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

    private var totalDurationString: String {
        let seconds = max(0, Int(tracks.reduce(0) { $0 + $1.duration }))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours) hr \(minutes) min" : "\(minutes) min"
    }
}
