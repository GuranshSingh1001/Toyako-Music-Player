# Toyako

**Toyako** is a fully offline music player for iPad, built with SwiftUI and AVFoundation.

It is designed to provide a clean, native iPadOS music experience while keeping your music and playback entirely on-device.

## Features

- Fully offline music playback
- Local music library
- Album browsing
- Artist browsing
- Playlist support
- Mini-player
- Now Playing screen
- Album artwork
- Lyrics support
- Background audio playback
- Music import through the Files app
- iPad-optimized interface
- Native SwiftUI interface
- No third-party cloud services required

## Project Structure

```text
Toyako-Music-Player/
│
├── project.yml
├── README.md
│
├── App/
│   ├── OfflineMusicApp.swift
│   └── Assets.xcassets/
│       └── AppIcon.appiconset/
│           ├── AppIcon-20.png
│           ├── AppIcon-40.png
│           ├── AppIcon-29.png
│           ├── AppIcon-58.png
│           ├── AppIcon-40-1x.png
│           ├── AppIcon-80.png
│           ├── AppIcon-76.png
│           ├── AppIcon-152.png
│           ├── AppIcon-167.png
│           ├── AppIcon-1024.png
│           └── Contents.json
│      
│
├── Audio/
│   ├── AudioEngineManager.swift
│   └── LRCParser.swift
│
├── Models/
│   ├── DataModels.swift
│   └── LocalLibrary.swift
│
├── UI/
│   ├── AbstractPlaylistCover.swift
│   ├── AlbumGridView.swift
│   ├── AllPlaylistGridView.swift
│   ├── ArtistListView.swift
│   ├── ContentView.swift
│   ├── DocumentPicker.swift
│   ├── FolderBrowserView.swift
│   ├── MiniPlayerView.swift
│   ├── NowPlayingView.swift
│   ├── PlaylistAddSongsSheet.swift
│   ├── PlaylistHeaderView.swift
│   ├── QueueView.swift
│   └── SongListView.swift
│
└── .github/
    └── workflows/
        └── main.yml

```
## Requirements


- iPad
- iPadOS 26\.0 or later
- SwiftUI
- AVFoundation

The project is configured specifically for iPad:

```yaml
TARGETED_DEVICE_FAMILY: "2"
```

## App Information

### App Name

```text
Toyako
```

### Bundle Identifier

```text
com.local.Toyako
```

These values are configured in `project.yml`\.

## Building

Toyako uses **XcodeGen** to generate the Xcode project from `project.yml`\.

Generate the Xcode project with:

```bash
xcodegen generate
```

Then build the generated project using Xcode\.

### GitHub Actions

The repository also contains GitHub Actions workflows for building the application on a macOS runner\.

The workflow:

1. Checks out the repository\.
2. Selects Xcode\.
3. Installs XcodeGen\.
4. Generates `Toyako.xcodeproj`\.
5. Builds the application\.
6. Creates an unsigned archive\.
7. Packages the application as an IPA\.
8. Uploads the IPA as a GitHub Actions artifact\.

The generated `.xcodeproj` does not need to be committed to the repository\.

## App Icon

The app icon is stored in:

```text
App/Assets.xcassets/AppIcon.appiconset/
```

The asset catalog contains the required iPad app\-icon sizes\.

The primary app icon is configured through:

```yaml
ASSETCATALOG_COMPILER_APPICON_NAME: "AppIcon"
```

The main 1024 × 1024 icon is:

```text
AppIcon-1024.png
```

## Supported Music

Toyako is intended for locally stored music files\.

Supported formats depend on the audio formats supported by Apple’s AVFoundation framework\.

Music can be imported through the iPad Files app\.

## Offline Design

Toyako is designed to work without an internet connection\.

The application does not require:

- User accounts
- Cloud music storage
- Music streaming services
- Remote databases
- Third\-party analytics
- Online playback services

Your local music library and playback remain on the device\.

## Architecture

Toyako is built using Apple’s native frameworks:

- **SwiftUI** — User interface
- **AVFoundation** — Audio playback
- **AVAudioSession** — Background audio
- **XcodeGen** — Project generation

No external Swift packages are required\.

## Development

The main application entry point is:

```text
App/OfflineMusicApp.swift
```

Audio playback is handled by:

```text
Audio/AudioEngineManager.swift
```

Lyrics parsing is handled by:

```text
Audio/LRCParser.swift
```

The user interface is located in:

```text
UI/
```

Data models and local library management are located in:

```text
Models/
```

## License

This project is currently intended for personal use and development\.

The **Toyako** name and application artwork are part of the project and should not be redistributed as a separate commercial product without permission\.

---

## Toyako

> Your music. Your device. No internet required.

## This is Made Using AI
