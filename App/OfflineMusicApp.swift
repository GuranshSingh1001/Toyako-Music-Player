import SwiftUI
import SwiftData
import AVFoundation

@main
struct OfflineMusicApp: App {
    @StateObject private var audioManager = AudioEngineManager()
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Track.self, Playlist.self, Album.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioManager)
                .environment(\.modelContext, sharedModelContainer.mainContext)
                .onAppear {
                    setupAudioSession()
                }
        }
    }
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
            try session.setActive(true)
        } catch {
            print("Failed to set audio session: \(error)")
        }
    }
}
