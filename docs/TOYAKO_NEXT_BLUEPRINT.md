# Toyako Next — iPad Workspace Blueprint

## Product direction

Toyako Next is a local-first music workstation designed for iPad. It is not a reskin of Classic. The new experience uses a workspace model: a persistent adaptive navigation sidebar, a focused content area, contextual playback, and a queue that can live beside the workspace on wide displays.

Classic remains available as a separate interface mode and retains its original destination hierarchy.

## Interaction model

- **Adaptive navigation:** `NavigationSplitView` provides a full sidebar on wide iPad layouts and native compact navigation when space is constrained.
- **Workspace destinations:** Overview, Tracks, Albums, Artists, Playlists, and Statistics.
- **Unified search:** searches tracks, albums, and artists and presents grouped results.
- **Dense track browser:** compact rows expose title, artist, album, duration, context actions, and drag-to-queue.
- **Contextual queue:** a persistent right-side queue on wide windows; a summoned sheet in portrait and compact Stage Manager windows. Tracks can be dropped into the queue.
- **Studio Now Playing:** artwork and transport controls share the screen with a switchable Queue / Lyrics panel. Timed lyrics follow playback and can be tapped to seek.
- **Docked mini-player:** playback stays available while browsing.
- **Multiple windows:** the app's `WindowGroup` supports additional workspace windows, opened from the File menu.
- **Keyboard:** the existing app-wide playback and library shortcuts remain active and now route navigation into Toyako Next.

## Visual language

- Apple-platform typography, controls, and materials.
- Neutral surfaces with artwork providing contextual colour.
- Restrained separators, compact metadata, and clear hierarchy.
- Short, cinematic transitions for workspace and player presentation.
- Layouts respond to window width rather than assuming a fixed iPad size.

## Current implementation scope

This first implementation establishes the new workspace shell and its navigation / playback mechanisms. It reuses the existing local library, album and artist detail views, playlist editor, artwork cache, lyric parser, and audio manager so the new interface does not fork core data or playback state.

Included in this phase:
- New iPad-first workspace and adaptive sidebar.
- Overview with recent listening, albums, playlists, and library metrics.
- Unified track / album / artist search.
- Dense track browser with enqueue context actions and drag-to-queue.
- Wide-window queue panel and compact queue sheet.
- Studio Now Playing with scrubbing, transport controls, queue, and timed lyrics.
- Interface selector for Toyako Next / Classic.
- Additional workspace window command.

## Audio and library roadmap

These capabilities were requested as product goals, but are **not represented as completed by this UI foundation**:

1. Verify codec support on the target iPadOS versions. AVFoundation support is format- and container-dependent; DSD, OGG Vorbis, and Opus need a deliberate decoder decision before being advertised.
2. Specify and test true gapless playback and adjustable crossfade. The current AVQueuePlayer-based engine must be evaluated for transition guarantees before adding controls.
3. Design an advanced equaliser against the actual audio rendering pipeline. A real multi-band EQ requires an audio processing graph; it should not be simulated with decorative settings.
4. Expand listening analytics beyond the existing recently-played cache, with local persistence and privacy controls.
5. Build the visual smart-playlist rule editor and metadata correction workflow.
6. Add queue reordering only after queue-index and AVPlayer item scheduling are updated atomically and covered by tests.

## Compatibility and quality bar

- Keep Classic's UI path isolated from Toyako Next.
- Keep the library and audio engine as shared sources of truth.
- Do not add network dependencies to local playback.
- Prefer native SwiftUI layout and animation; avoid animating expensive library-wide view trees.
- Validate on real iPad hardware in portrait, landscape, Split View, and Stage Manager before treating the branch as release-ready.
