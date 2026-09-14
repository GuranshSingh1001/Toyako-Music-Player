# Toyako

**Toyako is a native, offline-first music player for iPadOS.**

Built with SwiftUI and AVFoundation, Toyako is designed around a simple idea: your local music library should feel like a first-class music app without requiring a streaming service, account, or cloud library.

> Your music. Your device. No internet required.

## Stable Release

**Toyako 1.0.0 — First Stable Release**

This release marks the first stable version of Toyako. The core local-library, playback, lyrics, queue, playlist, and iPad interface workflows are ready for regular use.

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

Toyako supports timed **LRC** lyrics through its built-in LRC parser. Lyrics can be associated with locally stored music and displayed from the Now Playing experience.

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
