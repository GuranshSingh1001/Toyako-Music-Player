import SwiftUI
import UIKit

struct MiniPlayerView: View {
    @EnvironmentObject var audioManager: AudioEngineManager
    let transitionNamespace: Namespace.ID
    let isNowPlayingPresented: Bool
    let onOpenNowPlaying: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpenNowPlaying) {
                HStack(spacing: 12) {
                    artwork

                    VStack(alignment: .leading, spacing: 4) {
                        Text(audioManager.currentTrack?.title ?? "Not Playing")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)

                        Text(audioManager.currentTrack?.artist ?? "Unknown Artist")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        GeometryReader { proxy in
                            Capsule()
                                .fill(.primary.opacity(0.11))
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(.primary.opacity(0.52))
                                        .frame(
                                            width: proxy.size.width * min(
                                                max(audioManager.playbackProgress, 0),
                                                1
                                            )
                                        )
                                }
                        }
                        .frame(height: 3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 0) {
                Button {
                    audioManager.backward()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 32, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    audioManager.togglePlayPause()
                } label: {
                    Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 38, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    audioManager.forward()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 32, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.primary)
            .disabled(audioManager.currentTrack == nil)
            .opacity(audioManager.currentTrack == nil ? 0.45 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .animation(.smooth(duration: 0.22), value: audioManager.currentTrack?.id)
        .animation(.smooth(duration: 0.16), value: audioManager.isPlaying)
        .opacity(isNowPlayingPresented ? 0.001 : 1)
        .allowsHitTesting(!isNowPlayingPresented)
    }

    @ViewBuilder
    private var artwork: some View {
        if let track = audioManager.currentTrack,
           let data = track.artworkData,
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .matchedGeometryEffect(
                    id: "nowPlayingArtwork",
                    in: transitionNamespace,
                    properties: .frame,
                    anchor: .center,
                    isSource: !isNowPlayingPresented
                )
                .id(track.id)
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
        } else {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.secondary.opacity(0.16))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                }
        }
    }
}
