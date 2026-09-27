import SwiftUI
import AVFoundation

@main
struct OfflineMusicApp: App {
    @StateObject private var audioManager = AudioEngineManager()

    init() {
        ToyakoPreferences.registerDefaults()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioManager)
                .environmentObject(audioManager.clock)
        }
    }
}