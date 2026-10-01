import Foundation

/// Reads the currently playing track from Apple's Music app via Apple
/// Events. Requires Automation access to "Music" the first time it runs.
///
/// Unlike Spotify, Music never exposes an artwork URL — the only way to
/// get cover art is to pull the raw bytes back over an Apple Event. That
/// is expensive enough that it must not happen on every poll, which is
/// exactly what `ArtworkReference.embedded` buys: the poll loop compares
/// a cheap identity and only asks for bytes when the track changes.
final class AppleMusicSource: NowPlayingSource {
    let id = "apple-music"
    let displayName = "Apple Music"

    private let app = InstalledApp(bundleIdentifier: "com.apple.Music")

    private let nowPlaying = AppleScriptRunner("""
    tell application "Music"
        if player state is playing then
            set playingTrack to current track
            return (name of playingTrack) & tab & (artist of playingTrack) & tab & (album of playingTrack) & tab & ((duration of playingTrack) as text) & tab & (player position as text) & tab & ((database ID of playingTrack) as text)
        end if
    end tell
    """)

    var isAvailable: Bool { app.isInstalled }
    var isRunning: Bool { app.isRunning }

    func currentTrack() -> TrackInfo? {
        guard isRunning, let fields = nowPlaying.runForFields(expecting: 6) else { return nil }

        guard let durationSeconds = Double(fields[3]),
              let positionSeconds = Double(fields[4]) else {
            return nil
        }

        let title = fields[0], artist = fields[1], album = fields[2]
        // Library tracks get a stable database ID; some streamed/radio
        // tracks come back as 0, so fall back to the metadata for those.
        let databaseID = Int(fields[5]) ?? 0
        let identity = databaseID != 0
            ? "db:\(databaseID)"
            : "meta:\(title)|\(artist)|\(album)"

        return TrackInfo(
            sourceID: id,
            title: title,
            artist: artist,
            album: album,
            artwork: .embedded(identity: identity),
            position: positionSeconds,
            duration: durationSeconds
        )
    }

    func loadArtwork(for track: TrackInfo) async throws -> Data {
        guard case .embedded(let identity) = track.artwork else {
            throw NowPlayingSourceError.artworkUnavailable
        }

        // Fetching artwork is a second round trip, so the track may have
        // moved on since `currentTrack()`. When we have a database ID,
        // make the script assert it still matches rather than risk
        // pinning the previous song's cover to the desktop.
        let guardClause: String
        if identity.hasPrefix("db:") {
            let databaseID = String(identity.dropFirst("db:".count))
            guardClause = "((database ID of playingTrack) as text) is \"\(databaseID)\" and "
        } else {
            guardClause = ""
        }

        let script = AppleScriptRunner("""
        tell application "Music"
            if player state is playing then
                set playingTrack to current track
                if \(guardClause)(count of artworks of playingTrack) > 0 then
                    return raw data of artwork 1 of playingTrack
                end if
            end if
        end tell
        """)

        guard let data = script.runForData() else {
            throw NowPlayingSourceError.artworkUnavailable
        }
        return data
    }
}
