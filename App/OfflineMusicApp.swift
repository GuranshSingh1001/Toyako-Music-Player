import SwiftUI
import AVFoundation
import UIKit

@main
struct OfflineMusicApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var audioManager = AudioEngineManager()
    @StateObject private var remoteServer = RemoteServer()
    @State private var systemVolume: Float = AVAudioSession.sharedInstance().outputVolume

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
                .background(
                    AppSystemVolumeBridge(value: $systemVolume)
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                )
                .environmentObject(audioManager)
                .environmentObject(audioManager.clock)
                .environmentObject(remoteServer)
                .onAppear {
                    remoteServer.attach(to: audioManager)
                    remoteServer.autoStartIfEnabled()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background && audioManager.isPlaying {
                        // The .playback audio session keeps the app eligible to
                        // continue running while music is playing in the background.
                        let session = AVAudioSession.sharedInstance()
                        try? session.setCategory(.playback, mode: .default, options: [])
                        try? session.setActive(true)
                    }
                }
        }
    }
}