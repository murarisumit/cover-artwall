import AppKit
import Foundation

/// Where a track's cover art comes from.
///
/// Sources differ here more than anywhere else: Spotify hands out a CDN
/// URL, Apple Music will only give up raw bytes over Apple Events, and a
/// future browser-backed source might do either. So the poll loop never
/// touches artwork directly — it compares this value to spot a change and
/// asks the source to produce the bytes when one happens.
enum ArtworkReference: Equatable {
    /// Artwork lives at a URL anyone can fetch.
    case remote(URL)
    /// Only the source can produce the bytes. `identity` must change
    /// exactly when the artwork does, so the poll loop can tell tracks
    /// apart without paying for the image on every tick.
    case embedded(identity: String)
}

/// A track currently playing in some source app, along with everything
/// needed to render a wallpaper for it.
struct TrackInfo: Equatable {
    /// `id` of the `NowPlayingSource` that produced this track.
    var sourceID: String
    var title: String
    var artist: String
    var album: String
    var artwork: ArtworkReference
    /// Playback position, in seconds.
    var position: Double
    /// Track duration, in seconds.
    var duration: Double

    /// Changes exactly when the wallpaper needs to change. Scoped by
    /// source so switching apps mid-song still re-renders.
    var artworkKey: String {
        switch artwork {
        case .remote(let url): return "\(sourceID)|\(url.absoluteString)"
        case .embedded(let identity): return "\(sourceID)|\(identity)"
        }
    }
}

enum NowPlayingSourceError: LocalizedError {
    /// The track is playing but has no usable cover art — a podcast, a
    /// radio stream, a local file with no embedded image. Not an error the
    /// user needs to see; the app just leaves the wallpaper alone.
    case artworkUnavailable

    var errorDescription: String? {
        switch self {
        case .artworkUnavailable: return "This track has no cover art."
        }
    }
}

/// A now-playing integration for one music app (Spotify, Apple Music, ...).
///
/// Adding support for a new app means writing one conformer and adding it
/// to `SourceRegistry.makeSources()` — nothing else in the app changes.
@MainActor
protocol NowPlayingSource: AnyObject {
    /// Stable identifier, persisted when the user pins a source.
    var id: String { get }
    /// Display name shown in the menu bar UI.
    var displayName: String { get }
    /// Whether this source is usable on this Mac at all — the app is
    /// installed, the companion server is configured, and so on.
    /// Unavailable sources are hidden from the menu and skipped when the
    /// app is picking a source automatically.
    var isAvailable: Bool { get }
    /// Whether the source is running *right now*. Automatic selection
    /// polls only running sources, so a quit app costs nothing.
    var isRunning: Bool { get }
    /// The currently playing track, or `nil` if this source isn't playing
    /// anything.
    func currentTrack() -> TrackInfo?
    /// Produce the cover art bytes for a track this source returned.
    /// Sources using `.remote` artwork get this for free.
    func loadArtwork(for track: TrackInfo) async throws -> Data
}

extension NowPlayingSource {
    /// Default artwork loading: works for any source whose artwork is a
    /// plain URL. Sources with `.embedded` artwork must override.
    func loadArtwork(for track: TrackInfo) async throws -> Data {
        guard case .remote(let url) = track.artwork else {
            throw NowPlayingSourceError.artworkUnavailable
        }
        return try await RemoteArtwork.data(from: url)
    }
}

enum RemoteArtwork {
    private static let session = URLSession(configuration: .ephemeral)

    static func data(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

/// Availability/running checks for sources backed by a locally installed
/// app. Kept separate from the protocol so a source that isn't an app —
/// a browser extension bridge, a local HTTP companion — doesn't have to
/// pretend it has a bundle identifier.
struct InstalledApp {
    let bundleIdentifier: String

    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleIdentifier }
    }
}
