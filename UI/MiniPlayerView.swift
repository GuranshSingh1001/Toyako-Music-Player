import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject var audioManager: AudioEngineManager

    var body: some View {
        HStack(spacing: 12) {
            if let track = audioManager.currentTrack {
                if let data = track.artworkData, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 46, height: 46)
                        .cornerRadius(8)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 46, height: 46)
                        .overlay(Image(systemName: "music.note").foregroundColor(.gray))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(track.artist) — \(track.album)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    audioManager.togglePlayPause()
                } label: {
                    Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                }

                Button {
                    audioManager.forward()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                }
            }
        }
        .padding(10)
        .liquidGlass(cornerRadius: 16, opacity: 0.65)
        .padding(.horizontal, 16)
    }
}
