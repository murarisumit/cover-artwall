import AppKit
import Combine

/// Owns the poll loop: ask the active source for the current track, and
/// whenever its artwork changes, download it, render a wallpaper, and
/// apply it. Everything runs in one process — no more shelling out to
/// separately-compiled helper binaries.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var currentTrack: TrackInfo?
    @Published private(set) var launchAtLoginEnabled: Bool = LoginItemManager.isEnabled
    @Published private(set) var lastError: String?
    /// The exact bytes just handed to `NSWorkspace` — shown as a thumbnail
    /// in the menu so it's obvious what wallpaper is actually applied.
    @Published private(set) var currentWallpaperImage: NSImage?

    @Published var isAutoUpdateEnabled: Bool {
        didSet { UserDefaults.standard.set(isAutoUpdateEnabled, forKey: Keys.autoUpdate) }
    }

    /// Only Spotify today; future sources (Apple Music, ...) register here
    /// and the rest of the app doesn't need to change.
    private let sources: [NowPlayingSource] = [SpotifySource()]
    private var activeSource: NowPlayingSource { sources[0] }

    private let cacheDirectory: URL
    private var pollTimer: Timer?
    private var lastArtworkURL: URL?
    private let spaceSync = SpaceSyncObserver()
    private let urlSession = URLSession(configuration: .ephemeral)

    private enum Keys {
        static let autoUpdate = "isAutoUpdateEnabled"
    }

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = caches.appendingPathComponent("CoverArtwall", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        isAutoUpdateEnabled = UserDefaults.standard.object(forKey: Keys.autoUpdate) as? Bool ?? true

        startPolling()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        LoginItemManager.setEnabled(enabled)
        launchAtLoginEnabled = LoginItemManager.isEnabled
    }

    private func startPolling() {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        poll()
    }

    private func poll() {
        guard isAutoUpdateEnabled else { return }

        let track = activeSource.currentTrack()
        currentTrack = track

        guard let track, track.artworkURL != lastArtworkURL else { return }
        lastArtworkURL = track.artworkURL
        Task { await applyWallpaper(for: track) }
    }

    private func applyWallpaper(for track: TrackInfo) async {
        do {
            let (data, response) = try await urlSession.data(from: track.artworkURL)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            guard let cover = NSImage(data: data) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            guard let rendered = WallpaperCompositor.render(cover: cover) else {
                throw CocoaError(.fileWriteUnknown)
            }
            guard let jpeg = WallpaperCompositor.jpegData(for: rendered) else {
                throw CocoaError(.fileWriteUnknown)
            }

            let wallpaperURL = cacheDirectory
                .appendingPathComponent("wallpaper-\(track.artworkURL.absoluteString.stableFileIdentifier)")
                .appendingPathExtension("jpg")
            try jpeg.write(to: wallpaperURL)

            WallpaperSetter.apply(imageURL: wallpaperURL)
            spaceSync.update(currentImageURL: wallpaperURL)
            // Decode back from the written bytes (not the pre-encode
            // `rendered` image) so the thumbnail is provably what's on
            // disk and was handed to NSWorkspace, not just what was drawn.
            currentWallpaperImage = NSImage(data: jpeg)
            lastError = nil

            pruneOldWallpapers()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Keeps the cache from growing without bound across a long-running session.
    private func pruneOldWallpapers() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return
        }

        let wallpapers = files.filter { $0.lastPathComponent.hasPrefix("wallpaper-") }
        let sorted = wallpapers.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return lhsDate > rhsDate
        }

        for stale in sorted.dropFirst(25) {
            try? FileManager.default.removeItem(at: stale)
        }
    }
}
