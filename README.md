# Toyako

**Toyako is a native, offline-first music player for iPadOS.**

Built with SwiftUI and AVFoundation, Toyako is designed around a simple idea: your local music library should feel like a first-class music app without requiring a streaming service, account, or cloud library.

> Your music. Your device. No internet required.

## Features
- Fully offline music playback
- Local music library stored and managed on-device
- Import music through the iPad Files app
- Album browsing and album detail views
- Artist browsing
- Playlist creation and playlist management
- Queue management
- Mini-player for persistent playback controls
- Full Now Playing screen
- Album artwork and artwork loading
- LRC lyric parsing and lyric display support
- Fine-grained Japanese TTML karaoke lyrics with synchronized romaji
- Configurable lyric size, animation, and karaoke glow
- Romanization toggle for Japanese lyrics
- Recently played history
- Adaptive artwork-driven Now Playing ambience
- Audio quality information for the current track
- Queue drag-and-drop reordering
- Persistent smooth track transition settings
- Background audio playback
- Shuffle and repeat controls
- Playback progress and seeking
- iPad-optimized layouts
- Native SwiftUI interface
- No user account required
- No music streaming service required
- No third-party cloud music library required

## Supported Music

Toyako is intended for music stored locally on the device or imported through the Files app.

Supported audio formats depend on the formats provided by Apple's AVFoundation framework and the capabilities of the current iPadOS version.

### Lyrics

Toyako supports timed **LRC** and **TTML** lyrics. Japanese TTML spans can be rendered as fine-grained karaoke units with synchronized romaji, while Latin words and numbers remain atomic. The active lyric presentation can be customized from Settings.

## Offline by Design

Toyako is designed to keep the core music experience on the device. Playback and local-library functionality do not depend on an internet connection.

Toyako does not require:

- User accounts
- Cloud music storage
- A streaming subscription
- A remote music database
- Third-party analytics
- Online playback services

Your music library and playback remain local to the device.

## Interface

Toyako includes dedicated experiences for:

- **Home** — access your local music library and categories
- **Albums** — browse albums and open album details
- **Artists** — browse music by artist
- **Playlists** — create and manage playlists
- **Queue** — view and manage the current playback queue
- **Mini Player** — control playback without leaving the current screen
- **Now Playing** — artwork, track information, progress, lyrics, and playback controls

The interface is built specifically for iPad and supports portrait and landscape orientations.

## Automatic Artist Artwork

Toyako can optionally download artist artwork from the internet and cache it locally. This feature is **off by default** because artist names are sent to online metadata services when artwork is requested. When enabled, Toyako tries **Deezer**, then **iTunes**, then **Wikidata / Wikimedia Commons** as fallbacks. Artist names are normalized to improve matching, and common multi-artist metadata such as `Aki Toyosaki, Yoko Hikasa, Satomi Sato` is split into individual artist entries.

You can enable or disable automatic downloads in **Settings → Artist Artwork**. The same section includes **Remove All Downloaded Artist Artwork**. Artwork is stored in the app sandbox at `Library/Caches/ArtistArtwork`, so it does not appear in the Files app. iOS treats the Caches directory as app-managed, discardable data rather than user documents.

## Toyako Design System

The UI now uses a shared SwiftUI design system under `UI/DesignSystem/ToyakoDesignSystem.swift`.

The design system centralizes:

- Toyako accent color and semantic surfaces
- Screen spacing, control heights, corner radii, and artwork sizes
- Typography hierarchy for titles, sections, items, metadata, and actions
- Primary, secondary, icon, and small-action button styles
- Shared card/surface and section-header components

Screens should use these shared values and components instead of introducing new ad-hoc visual constants. This keeps Home, Tracks, Albums, Artists, Playlists, Queue, Settings, and shared playback surfaces visually coherent while still allowing immersive Now Playing-specific presentation where appropriate.
