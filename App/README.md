# Cover Artwall (app source)

A Swift Package (no Xcode project needed) building a `MenuBarExtra`-based
macOS app. See the [top-level README](../README.md) for what it does and
how to install a release build.

## Build & run locally

Requires Xcode Command Line Tools (`xcode-select --install`) for `swiftc`/
`swift build`, on macOS 13 (Ventura) or later.

```zsh
./Scripts/build-app.sh
open "dist/Cover Artwall.app"
```

`build-app.sh` compiles a release binary, assembles it into a `.app`
bundle with `Resources/Info.plist`, and ad-hoc code-signs it. Set
`UNIVERSAL=1` to build a universal (arm64 + x86_64) binary — that's what
the release CI workflow does; local dev builds default to just your host
arch, which is faster.

## Layout

```
Sources/CoverArtwall/
  App.swift                  - @main SwiftUI App, MenuBarExtra scene
  AppState.swift             - poll loop, ties source -> compositor -> wallpaper
  MenuBarContentView.swift   - the dropdown UI
  LoginItemManager.swift     - SMAppService-based "Launch at Login"
  StringHashing.swift
  Sources/
    NowPlayingSource.swift   - protocol, TrackInfo, ArtworkReference
    SourceRegistry.swift     - where sources get registered; selection mode
    AppleScriptRunner.swift  - shared Apple Events plumbing
    SpotifySource.swift
    AppleMusicSource.swift
  Wallpaper/
    WallpaperCompositor.swift - renders cover + gradient -> NSImage
    DisplayRegistry.swift     - connected displays; which ones are opted in
    WallpaperSetter.swift     - applies per display, restores the ones opted out
    DesktopSyncObserver.swift - watches Space switches and display changes
```

## Displays

By default the wallpaper goes on every connected display. With more than
one display the menu grows a **Displays** section where any subset can be
picked instead — useful when the second monitor is a TV, or a work screen
that shouldn't advertise what you're listening to.

Three things make that work:

- **Stable identity.** `CGDirectDisplayID` is reassigned every session, so
  a selection is persisted against `CGDisplayCreateUUIDFromDisplayID`,
  which macOS keeps per physical monitor. Unplug a display and plug it
  back in and it keeps its setting.
- **Per-display rendering.** Each targeted display gets a wallpaper in its
  own pixel size and aspect ratio, so a 16:9 monitor next to a 16:10
  laptop doesn't get a cropped copy of the laptop's. Displays of the same
  size share one rendered file.
- **Restore on opt-out.** `WallpaperSetter` records what a display was
  showing the first time it takes it over, and puts it back when the
  display is deselected — turning a display off hands it its old wallpaper
  rather than freezing it on whatever was playing. The record is persisted,
  so it survives a relaunch.

`DesktopSyncObserver` re-renders when displays are attached, detached, or
rearranged.

## Adding a new source

1. Write a class conforming to `NowPlayingSource` in `Sources/`.
2. Add it to `SourceRegistry.makeSources()`.

That's the whole extension point. The poll loop, the menu picker, artwork
loading, and the persisted source selection all pick it up with no further
edits — `AppState` never names a concrete source.

### What the protocol asks for

| Member | Notes |
| --- | --- |
| `id`, `displayName` | `id` is persisted when the user pins the source, so keep it stable. |
| `isAvailable` | Can this source ever work on this Mac? App installed, companion server configured, credentials present... Unavailable sources are hidden from the menu. |
| `isRunning` | Cheap check used to skip sources that aren't going to answer. |
| `currentTrack()` | Returns `TrackInfo?`. Synchronous — it runs on the main actor, so keep it to a fast query. |
| `loadArtwork(for:)` | Optional. The default implementation handles any source whose artwork is a plain URL. |

### Artwork: the part that actually varies

`TrackInfo.artwork` is an `ArtworkReference`, not a URL, because sources
genuinely disagree here:

- `.remote(URL)` — Spotify publishes a CDN URL. Nothing to implement;
  the default `loadArtwork(for:)` fetches it.
- `.embedded(identity:)` — Apple Music will only hand over raw bytes over
  an Apple Event, which is far too expensive to do on every 5-second poll.
  The `identity` is a cheap value that changes exactly when the artwork
  does; the poll loop compares it and calls `loadArtwork(for:)` only on a
  real change, roughly once a song.

A source that has no art for the current track (a podcast, a radio stream)
should throw `NowPlayingSourceError.artworkUnavailable`. That's treated as
"leave the wallpaper alone", not as an error worth showing the user.

### Sources that aren't AppleScript

Nothing in the protocol assumes Apple Events. A source backed by a local
companion HTTP server (the usual approach for YouTube Music) reports
`isAvailable` by probing its config, `isRunning` by whether the port
answers, and returns `.remote(...)` artwork — reusing the default loader.
`AppleScriptRunner` is a convenience for the Apple Events sources, not part
of the contract.
