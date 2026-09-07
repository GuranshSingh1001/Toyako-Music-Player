import SwiftUI

struct NowPlayingView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var audioManager: AudioEngineManager
    
    // Mock lyrics for demonstration; in production, this binds to LyricSynchronizer
    let lyrics: [LyricLine] = [
        LyricLine(time: 10.0, text: "Welcome to the offline player"),
        LyricLine(time: 14.5, text: "Running entirely on your iPad"),
        LyricLine(time: 18.2, text: "No servers required.")
    ]
    @State private var activeLyricID: UUID?

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            
            ViewThatFits {
                HStack(spacing: 0) {
                    artworkPane
                        .frame(width: geo.size.width * 0.5)
                    lyricsPane
                        .frame(width: geo.size.width * 0.5)
                }
                
                VStack(spacing: 0) {
                    artworkPane
                    lyricsPane
                }
            }
            .background(Color.black.edgesIgnoringSafeArea(.all))
            .overlay(alignment: .topLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.down")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding()
                }
            }
        }
    }
    
    private var artworkPane: some View {
        VStack {
            Spacer()
            // Placeholder for MeshGradient and CIImage color extraction
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.3))
                .aspectRatio(1, contentMode: .fit)
                .padding(40)
                .shadow(color: .white.opacity(0.1), radius: 20)
            
            if let track = audioManager.currentTrack {
                Text(track.title).font(.title.bold()).foregroundColor(.white)
                Text(track.artistName).font(.title3).foregroundColor(.gray)
            }
            
            ProgressView(value: audioManager.playbackProgress)
                .tint(.white)
                .padding(.horizontal, 40)
                .padding(.top, 20)
                
            HStack(spacing: 60) {
                Image(systemName: "backward.fill").font(.title)
                Button(action: { audioManager.togglePlayPause() }) {
                    Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 44))
                }
                Image(systemName: "forward.fill").font(.title)
            }
            .foregroundColor(.white)
            .padding(.top, 20)
            Spacer()
        }
    }
    
    private var lyricsPane: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(lyrics) { line in
                        Text(line.text)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(activeLyricID == line.id ? .white : .white.opacity(0.3))
                            .id(line.id)
                            .onTapGesture {
                                // Seek audioManager to line.time
                                activeLyricID = line.id
                            }
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: activeLyricID)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 200) // Padding to allow scrolling to center
            }
            .onChange(of: activeLyricID) { oldID, newID in
                withAnimation(.spring()) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
    }
}
