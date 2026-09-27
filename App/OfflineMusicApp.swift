import SwiftUI
import AVFoundation

@main
struct OfflineMusicApp: App {
    @StateObject private var audioManager = AudioEngineManager()
    @StateObject private var remoteServer = RemoteServer()

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
                .environmentObject(remoteServer)
                .onAppear {
                    remoteServer.attach(to: audioManager)
                }
        }
    }
}