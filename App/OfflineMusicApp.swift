import SwiftUI
import AVFoundation

@main
struct OfflineMusicApp: App {
    @StateObject private var audioManager = AudioEngineManager()
    @StateObject private var remoteServer = RemoteServer()

    init() {
        ToyakoPreferences.registerDefaults()
        Self.createUserMusicFolder()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
    }

    private static func createUserMusicFolder() {
        let fileManager = FileManager.default
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

        let musicFolder = documents.appendingPathComponent("Music", isDirectory: true)
        try? fileManager.createDirectory(at: musicFolder, withIntermediateDirectories: true)

        // Keep a real user-visible file in the folder so Files has something to
        // display immediately after the app is launched. It is harmless and can
        // be deleted by the user.
        let readme = musicFolder.appendingPathComponent("Drop Music Here.txt")
        if !fileManager.fileExists(atPath: readme.path) {
            let contents = "Put your MP3, M4A, FLAC, WAV or other music files in this folder.\n"
            try? contents.write(to: readme, atomically: true, encoding: .utf8)
        }
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