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
    @AppStorage(ToyakoPreferences.crossfadeKey) private var crossfadeEnabled = true
    @AppStorage(ToyakoPreferences.crossfadeDurationKey) private var crossfadeDuration = 0.75
    @AppStorage(ToyakoPreferences.gaplessKey) private var gaplessEnabled = true

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

                Section("Playback") {
                    Toggle("Crossfade", isOn: $crossfadeEnabled)
                        .onChange(of: crossfadeEnabled) { _, newValue in
                            if newValue {
                                gaplessEnabled = false
                                audioManager.setGaplessEnabled(false)
                            }
                            audioManager.setCrossfadeEnabled(newValue)
                        }

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Gapless Playback", isOn: $gaplessEnabled)
                            .onChange(of: gaplessEnabled) { _, newValue in
                                if newValue {
                                    crossfadeEnabled = false
                                    audioManager.setCrossfadeEnabled(false)
                                }
                                audioManager.setGaplessEnabled(newValue)
                            }

                        Text("Crossfade and gapless playback are mutually exclusive.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if crossfadeEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Crossfade Length")
                                Spacer()
                                Text(String(format: "%.1f sec", crossfadeDuration))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(value: Binding(
                                get: { crossfadeDuration },
                                set: { newValue in
                                    crossfadeDuration = newValue
                                    audioManager.setCrossfadeDuration(newValue)
                                }
                            ), in: 0.50...3.00, step: 0.05)
                        }
                    }
                }

                Section("About") {
                    LabeledContent("App", value: "Toyako")
                    LabeledContent("Version", value: "1.3")
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
            if gaplessEnabled {
                crossfadeEnabled = false
            }
            audioManager.crossfadeEnabled = crossfadeEnabled
            audioManager.crossfadeDuration = max(0.5, min(3.0, crossfadeDuration))
            audioManager.gaplessEnabled = gaplessEnabled
        }
    }
}
