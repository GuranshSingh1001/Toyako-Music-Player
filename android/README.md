# Toyako Android (initial native port)

This is a separate Android app scaffold; it does not alter the existing SwiftUI/iPad app. It uses Kotlin + Jetpack Compose for UI and AndroidX Media3 for local audio playback and the system media session.

## Build locally

Requirements: JDK 17, Android SDK platform 35, Android build tools 35.0.0, and Gradle 8.11.1.

```bash
gradle assembleDebug
```

The APK is written to `app/build/outputs/apk/debug/app-debug.apk`.

## Build with GitHub Actions

Push the repository to `main`, or open Actions → **Build Toyako Android APK** → **Run workflow**. Download the `Toyako-Android-debug` artifact from the completed workflow run and install the APK on your Android device. Android may ask you to allow installation from the browser/file manager used to open the APK.

## Current scope

The initial preview implements local audio selection, a simple library list, playback controls, and a Media3 session service for background/system media controls. It is a foundation, not a feature-complete port of Toyako. It does not yet port the iOS SwiftUI UI, LRC/TTML lyrics, romaji mapping, playlists persistence, queue reordering, artwork services, remote server, or all format/metadata behavior. Those should be implemented incrementally and tested on a real device.

## Notes

- `minSdk` is 26 (Android 8.0); `targetSdk` is 35.
- The first CI build targets the standard Android debug APK; Play Store signing is not configured.
- Keep the existing iOS workflow (`main.yml`) unchanged.
