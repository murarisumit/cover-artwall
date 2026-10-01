# Cover Artwall

A tiny macOS menu bar app that turns the cover art of whatever's currently
playing into your desktop wallpaper: a large, crisp cover centered over a
color gradient pulled from the art itself. It does one job — no music
playback, no library browsing, just wallpaper.

Spotify is the only source today. The app is built around a small
`NowPlayingSource` protocol so more sources (Apple Music, etc.) are a matter
of writing one new file, not restructuring the app — see
[`App/Sources/CoverArtwall/Sources/NowPlayingSource.swift`](App/Sources/CoverArtwall/Sources/NowPlayingSource.swift).

## Install

**Homebrew** (once a tap is published — see [`Casks/cover-artwall.rb`](Casks/cover-artwall.rb)):

```zsh
brew tap murarisumit/tap
brew install --cask cover-artwall
```

**Manual**: download the latest `CoverArtwall.app.zip` from
[Releases](../../releases), unzip, and drag `Cover Artwall.app` into
`/Applications`.

Either way, the app is unsigned (no Apple Developer ID yet), so macOS
Gatekeeper blocks the first launch. Fix it once with either:

- Right-click the app in Finder -> **Open** -> **Open** again in the dialog, or
- `xattr -cr "/Applications/Cover Artwall.app"` in Terminal.

After that it launches normally. The first time it reads Spotify's now
playing track, macOS will also ask for **Automation** permission — allow it
(System Settings -> Privacy & Security -> Automation).

## Migrating from the old CLI script

Earlier versions of this project were a shell script + LaunchAgent. If you
still have that installed, run its `uninstall.sh` before using this app —
otherwise both will fight over the wallpaper.

## What's in this repo

- [`App/`](App/) — the menu bar app (Swift Package, SwiftUI `MenuBarExtra`).
  See [`App/README.md`](App/README.md) to build it yourself.
- [`Casks/cover-artwall.rb`](Casks/cover-artwall.rb) — Homebrew Cask
  template; see the comments in that file for how to actually publish it
  via a tap.
- [`.github/workflows/release.yml`](.github/workflows/release.yml) — builds
  a universal (arm64 + x86_64) `.app`, zips it, and attaches it to a GitHub
  Release whenever a `v*.*.*` tag is pushed.

## License

MIT — see [LICENSE](LICENSE).
