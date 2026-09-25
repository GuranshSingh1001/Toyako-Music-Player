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
    @AppStorage(ToyakoPreferences.automaticArtistArtworkKey) private var automaticArtistArtwork = false
    @AppStorage(ToyakoPreferences.bleedingEffectKey) private var bleedingEffect = true
    @State private var showClearArtistArtworkConfirmation = false
    @State private var artistArtworkStatus: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Toggle("Artwork Bleeding Effect", isOn: $bleedingEffect)

                    Text("Uses album artwork to create a soft blurred background on Home, Tracks, Albums, Playlists, and other artwork-driven screens.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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
                    Toggle("Automatically Download Artist Artwork", isOn: $automaticArtistArtwork)

                    Text("When enabled, Toyako uses internet metadata services to find artist artwork and caches the images on your device. It is off by default.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Remove All Downloaded Artist Artwork", role: .destructive) {
                        showClearArtistArtworkConfirmation = true
                    }

                    Text("Artwork is stored in Toyako's app sandbox under Library/Caches/ArtistArtwork. It does not appear in the Files app because it is app cache data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let artistArtworkStatus {
                        Text(artistArtworkStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("About") {
                    LabeledContent("App", value: "Toyako")
                    LabeledContent("Version", value: "1.4")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toggleStyle(ToyakoToggleStyle())
            .confirmationDialog("Remove all downloaded artist artwork?", isPresented: $showClearArtistArtworkConfirmation, titleVisibility: .visible) {
                Button("Remove Artwork", role: .destructive) {
                    Task {
                        let count = await ArtistArtworkService.shared.clearCache()
                        artistArtworkStatus = count == 0 ? "No cached artist artwork was found." : "Removed \(count) cached artist artwork files."
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(ToyakoDesign.Color.accent)
        .onAppear {
            ToyakoPreferences.registerDefaults()
        }
    }
}
