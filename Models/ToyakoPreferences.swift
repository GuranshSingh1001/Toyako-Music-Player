import SwiftUI

struct ToyakoPreferences {
    static let showRomanizationKey = "Toyako.Lyrics.ShowRomanization"
    static let karaokeGlowKey = "Toyako.Lyrics.KaraokeGlow"
    static let lyricsFontScaleKey = "Toyako.Lyrics.FontScale"
    static let lyricsLineSpacingKey = "Toyako.Lyrics.LineSpacing"
    static let lyricsAnimationStyleKey = "Toyako.Lyrics.AnimationStyle"
    static let showAudioInfoKey = "Toyako.NowPlaying.ShowAudioInfo"
    static let crossfadeKey = "Toyako.Playback.Crossfade"
    static let crossfadeDurationKey = "Toyako.Playback.CrossfadeDuration"
    static let gaplessKey = "Toyako.Playback.Gapless"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showRomanizationKey: true,
            karaokeGlowKey: true,
            lyricsFontScaleKey: 1.0,
            lyricsLineSpacingKey: 30.0,
            lyricsAnimationStyleKey: "dynamic",
            showAudioInfoKey: true,
            crossfadeKey: true,
            crossfadeDurationKey: 0.45,
            gaplessKey: true
        ])
    }
}

enum LyricsAnimationStyle: String, CaseIterable, Identifiable {
    case dynamic
    case smooth
    case classic
    case minimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dynamic: "Dynamic"
        case .smooth: "Smooth"
        case .classic: "Classic"
        case .minimal: "Minimal"
        }
    }
}
