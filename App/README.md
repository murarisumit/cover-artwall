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
  App.swift                 - @main SwiftUI App, MenuBarExtra scene
  AppState.swift             - poll loop, ties source -> compositor -> wallpaper
  MenuBarContentView.swift   - the dropdown UI
  LoginItemManager.swift     - SMAppService-based "Launch at Login"
  StringHashing.swift
  Sources/
    NowPlayingSource.swift   - protocol + TrackInfo — implement this for a new source
    SpotifySource.swift      - the only source today
  Wallpaper/
    WallpaperCompositor.swift - renders cover + gradient -> NSImage
    WallpaperSetter.swift     - applies an image to every screen
    SpaceSyncObserver.swift   - re-applies wallpaper when the active Space changes
```

## Adding a new source

Implement `NowPlayingSource` (one `currentTrack() -> TrackInfo?` method) and
add an instance to the `sources` array in `AppState.swift`. Nothing else
needs to change.
