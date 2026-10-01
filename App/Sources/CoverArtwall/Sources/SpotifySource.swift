import Foundation

/// Reads the currently playing track from the Spotify desktop app via
/// Apple Events. Requires the user to grant Automation access to Spotify
/// the first time this runs (macOS prompts for this automatically).
///
/// Spotify publishes an artwork URL, so the fetching itself is the default
/// implementation's job — this source only upgrades the URL first (see
/// `loadArtwork`).
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

    /// Spotify's dictionary only ever reports the 640px variant of a cover,
    /// but the compositor draws the art at up to ~1900px on a Retina
    /// display — a 3x upscale that visibly softens it. The same image is
    /// served at 1429px under a different size prefix, so ask for that one.
    ///
    /// The upgraded URL is fetched but never stored on the track: keeping
    /// `artwork` as the URL Spotify actually reported means `artworkKey`
    /// (and so the cache filename) doesn't depend on an undocumented CDN
    /// convention that may change.
    func loadArtwork(for track: TrackInfo) async throws -> Data {
        guard case .remote(let url) = track.artwork else {
            throw NowPlayingSourceError.artworkUnavailable
        }

        if let larger = Self.higherResolutionURL(for: url),
           let data = try? await RemoteArtwork.data(from: larger) {
            return data
        }
        // Prefix scheme didn't match, or that size isn't served for this
        // cover — fall back to what Spotify gave us rather than failing.
        return try await RemoteArtwork.data(from: url)
    }

    /// Cover URLs are `https://i.scdn.co/image/<prefix><id>`, where the
    /// prefix encodes the size. Returns `nil` for any URL that isn't in the
    /// reported-640px shape, so an unexpected one is left alone.
    private static func higherResolutionURL(for url: URL) -> URL? {
        let reportedSizePrefix = "ab67616d0000b273"  // 640x640
        let largerSizePrefix = "ab67616d000082c1"    // 1429x1429

        let absolute = url.absoluteString
        guard absolute.contains(reportedSizePrefix) else { return nil }
        return URL(string: absolute.replacingOccurrences(
            of: reportedSizePrefix,
            with: largerSizePrefix
        ))
    }
}
