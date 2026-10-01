import Foundation

/// Which source the app should read from.
enum SourceSelection: Hashable {
    /// Use whichever registered source is actually playing, in
    /// registration order. This is the default and the only mode most
    /// people ever need.
    case automatic
    /// Always read from one specific source, even when another is
    /// playing — for people who keep two players open.
    case pinned(sourceID: String)

    private static let automaticToken = "auto"

    var persistedValue: String {
        switch self {
        case .automatic: return Self.automaticToken
        case .pinned(let sourceID): return sourceID
        }
    }

    init(persistedValue: String?) {
        switch persistedValue {
        case nil, Self.automaticToken: self = .automatic
        case let sourceID?: self = .pinned(sourceID: sourceID)
        }
    }
}

/// The single place a new music app gets wired into the app.
///
/// Write a `NowPlayingSource` conformer, add it to `makeSources()`, and
/// you're done: the poll loop, the menu picker, artwork loading, and the
/// persisted selection all pick it up without another edit.
///
/// Order matters — it's the priority order used by `.automatic`.
enum SourceRegistry {
    @MainActor
    static func makeSources() -> [NowPlayingSource] {
        [
            SpotifySource(),
            AppleMusicSource(),
        ]
    }
}

/// A source as the menu bar UI sees it: just enough to render and select,
/// with none of the machinery.
struct SourceOption: Identifiable, Hashable {
    let id: String
    let displayName: String
}
