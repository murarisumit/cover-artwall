import Foundation

/// Reads the currently playing track from the Spotify desktop app via
/// Apple Events. Requires the user to grant Automation access to Spotify
/// the first time this runs (macOS prompts for this automatically).
///
/// Spotify publishes an artwork URL, so this source gets artwork loading
/// for free from the `NowPlayingSource` default implementation.
final class SpotifySource: NowPlayingSource {
    let id = "spotify"
    let displayName = "Spotify"

    private let app = InstalledApp(bundleIdentifier: "com.spotify.client")

    private let nowPlaying = AppleScriptRunner("""
    tell application "Spotify"
        if player state is playing then
            set playingTrack to current track
            return artwork url of playingTrack & tab & name of playingTrack & tab & artist of playingTrack & tab & album of playingTrack & tab & duration of playingTrack & tab & player position
        end if
    end tell
    """)

    var isAvailable: Bool { app.isInstalled }
    var isRunning: Bool { app.isRunning }

    func currentTrack() -> TrackInfo? {
        guard isRunning, let fields = nowPlaying.runForFields(expecting: 6) else { return nil }

        guard let artworkURL = URL(string: fields[0]),
              let durationMilliseconds = Double(fields[4]),
              let positionSeconds = Double(fields[5]) else {
            return nil
        }

        return TrackInfo(
            sourceID: id,
            title: fields[1],
            artist: fields[2],
            album: fields[3],
            artwork: .remote(artworkURL),
            position: positionSeconds,
            duration: durationMilliseconds / 1000
        )
    }
}
