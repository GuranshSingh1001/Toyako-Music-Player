import SwiftUI
import AVFoundation

@main
struct OfflineMusicApp: App {
    @StateObject private var audioManager = AudioEngineManager()

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioManager)
                .environmentObject(audioManager.clock)
        }
    }
}