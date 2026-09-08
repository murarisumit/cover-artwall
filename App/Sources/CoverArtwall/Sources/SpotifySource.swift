import AppKit
import Foundation

/// Reads the currently playing track from the Spotify desktop app via
/// Apple Events. Requires the user to grant Automation access to Spotify
/// the first time this runs (macOS prompts for this automatically).
final class SpotifySource: NowPlayingSource {
    let id = "spotify"
    let displayName = "Spotify"

    private static let script = """
    tell application "Spotify"
        if player state is playing then
            set playingTrack to current track
            return artwork url of playingTrack & tab & name of playingTrack & tab & artist of playingTrack & tab & album of playingTrack & tab & duration of playingTrack & tab & player position
        end if
    end tell
    """

    func currentTrack() -> TrackInfo? {
        guard isSpotifyRunning, let appleScript = NSAppleScript(source: Self.script) else {
            return nil
        }

        var errorInfo: NSDictionary?
        let result = appleScript.executeAndReturnError(&errorInfo)
        if errorInfo != nil {
            // Spotify is running but paused/idle, or the automation prompt
            // hasn't been answered yet — either way, no wallpaper update.
            return nil
        }

        guard let raw = result.stringValue else { return nil }
        let parts = raw.components(separatedBy: "\t")
        guard parts.count == 6,
              let artworkURL = URL(string: parts[0]),
              let durationMilliseconds = Double(parts[4]),
              let positionSeconds = Double(parts[5]) else {
            return nil
        }

        return TrackInfo(
            title: parts[1],
            artist: parts[2],
            album: parts[3],
            artworkURL: artworkURL,
            position: positionSeconds,
            duration: durationMilliseconds / 1000
        )
    }

    private var isSpotifyRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.spotify.client" }
    }
}
