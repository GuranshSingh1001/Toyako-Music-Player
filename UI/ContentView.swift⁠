import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var audioManager: AudioEngineManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Track.title) private var tracks: [Track]
    
    @State private var selectedCategory: String? = "Songs"
    @State private var showNowPlaying = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedCategory) {
                Section("Library") {
                    NavigationLink("Songs", value: "Songs")
                    NavigationLink("Albums", value: "Albums")
                    NavigationLink("Artists", value: "Artists")
                }
                Section("Playlists") {
                    NavigationLink("Favorites", value: "Favorites")
                }
            }
            .navigationTitle("Library")
        } detail: {
            ZStack(alignment: .bottom) {
                TrackListView(tracks: tracks)
                
                if audioManager.currentTrack != nil {
                    MiniPlayerView()
                        .onTapGesture { showNowPlaying = true }
                        .padding(.bottom, 8)
                }
            }
        }
        .fullScreenCover(isPresented: $showNowPlaying) {
            NowPlayingView()
        }
        .keyboardShortcut(" ", modifiers: []) // Space to play/pause globally
        .onChange(of: selectedCategory) { _ in
            // Handle category switching
        }
    }
}

struct TrackListView: View {
    @EnvironmentObject var audioManager: AudioEngineManager
    var tracks: [Track]
    
    var body: some View {
        List(tracks) { track in
            HStack {
                VStack(alignment: .leading) {
                    Text(track.title).font(.headline)
                    Text(track.artistName).font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
                Text(formatTime(track.duration)).font(.caption.monospacedDigit())
            }
            .contentShape(Rectangle())
            .onTapGesture { audioManager.play(track: track) }
            .contextMenu {
                Button("Play Next") { /* Queue logic */ }
                Button("Add to Favorites") { track.isFavorite.toggle() }
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let min = Int(time) / 60
        let sec = Int(time) % 60
        return String(format: "%d:%02d", min, sec)
    }
}
