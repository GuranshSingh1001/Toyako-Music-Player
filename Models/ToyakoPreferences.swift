import SwiftUI

struct ToyakoPreferences {
    static let showRomanizationKey = "Toyako.Lyrics.ShowRomanization"
    static let karaokeGlowKey = "Toyako.Lyrics.KaraokeGlow"
    static let lyricsFontScaleKey = "Toyako.Lyrics.FontScale"
    static let lyricsLineSpacingKey = "Toyako.Lyrics.LineSpacing"
    static let lyricsAnimationStyleKey = "Toyako.Lyrics.AnimationStyle"
    static let showAudioInfoKey = "Toyako.NowPlaying.ShowAudioInfo"
    static let translationKey = "Toyako.Lyrics.Translation"
    static let automaticArtistArtworkKey = "Toyako.ArtistArtwork.AutomaticDownloads"
    static let preventAccidentalAlbumArtistPlaybackKey = "Toyako.Playback.PreventAccidentalAlbumArtistPlayback"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showRomanizationKey: true,
            karaokeGlowKey: true,
            lyricsFontScaleKey: 1.0,
            lyricsLineSpacingKey: 30.0,
            lyricsAnimationStyleKey: "dynamic",
            showAudioInfoKey: true,
            translationKey: false,
            automaticArtistArtworkKey: false,
            preventAccidentalAlbumArtistPlaybackKey: true
        ])

        // Classic was removed because it was visually too close to Smooth.
        if UserDefaults.standard.string(forKey: lyricsAnimationStyleKey) == "classic" {
            UserDefaults.standard.set("smooth", forKey: lyricsAnimationStyleKey)
        }
    }
}

enum LyricsAnimationStyle: String, CaseIterable, Identifiable {
    case dynamic
    case smooth
    case minimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dynamic: "Dynamic"
        case .smooth: "Smooth"
        case .minimal: "Minimal"
        }
    }
}
