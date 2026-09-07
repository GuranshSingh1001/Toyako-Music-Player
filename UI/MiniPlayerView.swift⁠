import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject var audioManager: AudioEngineManager
    
    var body: some View {
        HStack {
            if let track = audioManager.currentTrack {
                // Placeholder artwork
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 48, height: 48)
                
                VStack(alignment: .leading) {
                    Text(track.title).font(.headline).lineLimit(1)
                    Text(track.artistName).font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                }
                
                Spacer()
                
                Button(action: { audioManager.togglePlayPause() }) {
                    Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                }
                
                Button(action: { /* Next track logic */ }) {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        .padding(.horizontal)
    }
}
