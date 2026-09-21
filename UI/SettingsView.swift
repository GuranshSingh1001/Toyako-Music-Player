import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var audioManager: AudioEngineManager

    @AppStorage(ToyakoPreferences.showRomanizationKey) private var showRomanization = true
    @AppStorage(ToyakoPreferences.karaokeGlowKey) private var karaokeGlow = true
    @AppStorage(ToyakoPreferences.lyricsFontScaleKey) private var lyricsFontScale = 1.0
    @AppStorage(ToyakoPreferences.lyricsAnimationStyleKey) private var lyricsAnimationStyle = LyricsAnimationStyle.dynamic.rawValue
    @AppStorage(ToyakoPreferences.showAudioInfoKey) private var showAudioInfo = true
    @AppStorage(ToyakoPreferences.crossfadeKey) private var crossfadeEnabled = true
    @AppStorage(ToyakoPreferences.crossfadeDurationKey) private var crossfadeDuration = 0.45

    var body: some View {
        NavigationStack {
            Form {
                Section("Lyrics") {
                    Toggle("Show Romanization", isOn: $showRomanization)
                    Toggle("Karaoke Glow", isOn: $karaokeGlow)

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
                }

                Section("Now Playing") {
                    Toggle("Show Audio Quality", isOn: $showAudioInfo)
                }

                Section("Playback") {
                    Toggle("Smooth Track Transitions", isOn: $crossfadeEnabled)
                        .onChange(of: crossfadeEnabled) { _, newValue in
                            audioManager.setCrossfadeEnabled(newValue)
                        }

                    if crossfadeEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Transition Length")
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
                            ), in: 0.20...1.50, step: 0.05)
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
            audioManager.crossfadeEnabled = crossfadeEnabled
            audioManager.crossfadeDuration = crossfadeDuration
        }
    }
}
