import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var audioManager: AudioEngineManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Track.title) private var tracks: [Track]
    
    @State private var selectedCategory: String? = "Songs"
    @State private var showNowPlaying = false
    @State private var showFilePicker = false

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
                if tracks.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 64))
                            .foregroundColor(.gray)
                        Text("No Music Found")
                            .font(.title2.bold())
                        Text("Import audio files from your iPad or iCloud Drive to begin.")
                            .foregroundColor(.secondary)
                        Button("Import Files") {
                            showFilePicker = true
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TrackListView(tracks: tracks)
                }
                
                if audioManager.currentTrack != nil {
                    MiniPlayerView()
                        .onTapGesture { showNowPlaying = true }
                        .padding(.bottom, 8)
                }
            }
            .navigationTitle("Songs")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showFilePicker = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showNowPlaying) {
            NowPlayingView()
        }
        .sheet(isPresented: $showFilePicker) {
            DocumentPicker { urls in
                MusicImporter.importAudioFiles(from: urls, into: modelContext)
            }
        }
        .keyboardShortcut(" ", modifiers: [])
        .onAppear {
        MusicImporter.scanDocumentsDirectory(into: modelContext, existingTracks: tracks)
    }
        .onChange(of: selectedCategory) { oldValue, newValue in
            // Handle category switching logic here
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
