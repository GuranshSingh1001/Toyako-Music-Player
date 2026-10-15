import SwiftUI
import Foundation

/// Commands exposed through the native iPadOS 26 menu bar.
/// On iPad, the system reveals this menu bar when the user swipes down from
/// the top edge while using Windowed Apps or Stage Manager.
struct ToyakoCommands: Commands {
    @AppStorage(ToyakoPreferences.translationKey) private var showTranslation = false
    @AppStorage(ToyakoPreferences.showRomanizationKey) private var showRomanization = true
    @AppStorage(ToyakoPreferences.karaokeGlowKey) private var karaokeGlow = true
    @AppStorage(ToyakoPreferences.showAudioInfoKey) private var showAudioInfo = true

    var body: some Commands {
        // Remove standard actions that are not useful for a dedicated music player.
        // ToyakoAppDelegate also removes the complete File/Edit/View menus from
        // the main menu builder on platforms that expose UIKit menu customization.
        CommandGroup(replacing: .newItem) { }
        CommandGroup(replacing: .undoRedo) { }
        CommandGroup(replacing: .pasteboard) { }
        CommandGroup(replacing: .textEditing) { }
        CommandGroup(replacing: .textFormatting) { }
        CommandGroup(replacing: .toolbar) { }
        CommandGroup(replacing: .sidebar) { }
        CommandMenu("Playback") {
            Button("Play / Pause", systemImage: "playpause.fill") {
                NotificationCenter.default.post(name: .toyakoCommandTogglePlayback, object: nil)
            }
            .keyboardShortcut(.space, modifiers: [])

            Button("Previous Track", systemImage: "backward.end.fill") {
                NotificationCenter.default.post(name: .toyakoCommandPreviousTrack, object: nil)
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command])

            Button("Next Track", systemImage: "forward.end.fill") {
                NotificationCenter.default.post(name: .toyakoCommandNextTrack, object: nil)
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command])

            Divider()

            Button("Show Now Playing", systemImage: "music.note") {
                NotificationCenter.default.post(name: .toyakoCommandShowNowPlaying, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Show Queue", systemImage: "list.bullet") {
                NotificationCenter.default.post(name: .toyakoCommandShowQueue, object: nil)
            }
            .keyboardShortcut("q", modifiers: [.command, .shift])
        }

        CommandMenu("Library") {
            Button("Home", systemImage: "house") {
                NotificationCenter.default.post(name: .toyakoCommandNavigate, object: "home")
            }.keyboardShortcut("1", modifiers: [.command])
            Button("Tracks", systemImage: "music.note.list") {
                NotificationCenter.default.post(name: .toyakoCommandNavigate, object: "tracks")
            }.keyboardShortcut("2", modifiers: [.command])
            Button("Albums", systemImage: "square.stack") {
                NotificationCenter.default.post(name: .toyakoCommandNavigate, object: "albums")
            }.keyboardShortcut("3", modifiers: [.command])
            Button("Artists", systemImage: "music.mic") {
                NotificationCenter.default.post(name: .toyakoCommandNavigate, object: "artists")
            }.keyboardShortcut("4", modifiers: [.command])
            Button("Playlists", systemImage: "music.note.list") {
                NotificationCenter.default.post(name: .toyakoCommandNavigate, object: "playlists")
            }.keyboardShortcut("5", modifiers: [.command])
        }

        CommandMenu("Settings") {
            Toggle("Translate Japanese Lyrics", isOn: $showTranslation)
            Toggle("Romanization", isOn: $showRomanization)
            Toggle("Karaoke Glow", isOn: $karaokeGlow)
            Toggle("Show Audio Information", isOn: $showAudioInfo)
            Divider()
            Button("Open Settings…", systemImage: "gearshape") {
                NotificationCenter.default.post(name: .toyakoCommandOpenSettings, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let toyakoCommandTogglePlayback = Notification.Name("Toyako.Command.TogglePlayback")
    static let toyakoCommandPreviousTrack = Notification.Name("Toyako.Command.PreviousTrack")
    static let toyakoCommandNextTrack = Notification.Name("Toyako.Command.NextTrack")
    static let toyakoCommandShowNowPlaying = Notification.Name("Toyako.Command.ShowNowPlaying")
    static let toyakoCommandShowQueue = Notification.Name("Toyako.Command.ShowQueue")
    static let toyakoCommandOpenSettings = Notification.Name("Toyako.Command.OpenSettings")
    static let toyakoCommandNavigate = Notification.Name("Toyako.Command.Navigate")
}
