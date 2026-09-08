import Foundation

/// A track currently playing in some source app, along with the artwork
/// needed to render a wallpaper for it.
struct TrackInfo: Equatable {
    var title: String
    var artist: String
    var album: String
    var artworkURL: URL
    /// Playback position, in seconds.
    var position: Double
    /// Track duration, in seconds.
    var duration: Double
}

/// A now-playing integration for one music app (Spotify, Apple Music, ...).
///
/// Adding support for a new app means writing one conformer and registering
/// it in `AppState` — nothing else in the app needs to change.
protocol NowPlayingSource: AnyObject {
    /// Stable identifier used when persisting the user's chosen source.
    var id: String { get }
    /// Display name shown in the menu bar UI.
    var displayName: String { get }
    /// The currently playing track, or `nil` if the source app isn't
    /// running or nothing is playing right now.
    func currentTrack() -> TrackInfo?
}
