import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var audioManager: AudioEngineManager

    @AppStorage(ToyakoPreferences.showRomanizationKey) private var showRomanization = true
    @AppStorage(ToyakoPreferences.karaokeGlowKey) private var karaokeGlow = true
    @AppStorage(ToyakoPreferences.translationKey) private var showTranslation = false
    @AppStorage(ToyakoPreferences.lyricsFontScaleKey) private var lyricsFontScale = 1.0
    @AppStorage(ToyakoPreferences.lyricsLineSpacingKey) private var lyricsLineSpacing = 30.0
    @AppStorage(ToyakoPreferences.lyricsAnimationStyleKey) private var lyricsAnimationStyle = LyricsAnimationStyle.dynamic.rawValue
    @AppStorage(ToyakoPreferences.showAudioInfoKey) private var showAudioInfo = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Lyrics") {
                    Toggle("Show Romanization", isOn: $showRomanization)
                    Toggle("Karaoke Glow", isOn: $karaokeGlow)
                    Toggle("Translate Japanese Lyrics", isOn: $showTranslation)

                    Picker("Animation", selection: $lyricsAnimationStyle) {
                        ForEach(LyricsAnimationStyle.allCases) { style in
                            Text(style.title).tag(style.rawValue)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Text Size")
                            Spacer()
                            Text("\(Int(lyricsFontScale * 100))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        Slider(value: $lyricsFontScale, in: 0.82...1.18, step: 0.01)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Line Spacing")
                            Spacer()
                            Text("\(Int(lyricsLineSpacing)) pt")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $lyricsLineSpacing, in: 8...60, step: 1)
                    }
                }

                Section("Now Playing") {
                    Toggle("Show Audio Quality", isOn: $showAudioInfo)
                }

                Section("Artist Artwork") {
                    NavigationLink("Artist Artwork Debug") {
                        ArtistArtworkDebugView()
                    }
                }

                Section("About") {
                    LabeledContent("App", value: "Toyako")
                    LabeledContent("Version", value: "1.3.3")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            ToyakoPreferences.registerDefaults()
        }
    }
}
