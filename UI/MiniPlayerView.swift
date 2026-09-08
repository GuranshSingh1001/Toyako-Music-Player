import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject var audioManager: AudioEngineManager

    var body: some View {
        HStack(spacing: 12) {
            if let track = audioManager.currentTrack,
               let data = track.artworkData,
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(.white.opacity(0.8))
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(audioManager.currentTrack?.title ?? "Not Playing")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                
                Text(audioManager.currentTrack?.artist ?? "Unknown Artist")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 20) {
                Button {
                    audioManager.togglePlayPause()
                } label: {
                    Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .contentShape(Rectangle())
                }
                
                Button {
                    print("Next track tapped") // यहाँ अपना नेक्स्ट ट्रैक मेथड डालें
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                        .contentShape(Rectangle())
                }
            }
            .foregroundColor(.primary)
            .padding(.trailing, 8)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color.black.opacity(0.001))
    }
}