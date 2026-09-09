import AppKit
import Combine

/// Owns the poll loop: ask the selected source for the current track, and
/// whenever its artwork changes, load it, render a wallpaper, and apply
/// it. Everything runs in one process — no more shelling out to
/// separately-compiled helper binaries.
///
/// This type knows nothing about any specific music app. Sources are
/// registered in `SourceRegistry`; everything here works against the
/// `NowPlayingSource` protocol.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var currentTrack: TrackInfo?
    @Published private(set) var launchAtLoginEnabled: Bool = LoginItemManager.isEnabled
    @Published private(set) var lastError: String?
    /// The exact bytes just handed to `NSWorkspace` — shown as a thumbnail
    /// in the menu so it's obvious what wallpaper is actually applied.
    @Published private(set) var currentWallpaperImage: NSImage?
    /// Sources installed on this Mac, in registration order.
    @Published private(set) var availableSources: [SourceOption] = []
    /// Displays currently connected, refreshed as monitors come and go.
    @Published private(set) var availableDisplays: [DisplayInfo] = []

    @Published var isAutoUpdateEnabled: Bool {
        didSet { UserDefaults.standard.set(isAutoUpdateEnabled, forKey: Keys.autoUpdate) }
    }

    /// Which displays get the wallpaper. Changing it re-renders straight
    /// away (sizes differ per display) and hands any display that just
    /// dropped out back its previous wallpaper.
    @Published var displaySelection: DisplaySelection {
        didSet {
            guard displaySelection != oldValue else { return }
            UserDefaults.standard.set(displaySelection.persistedValue, forKey: Keys.displaySelection)
            reapplyToCurrentDisplays()
        }
    }

    @Published var sourceSelection: SourceSelection {
        didSet {
            guard sourceSelection != oldValue else { return }
            UserDefaults.standard.set(sourceSelection.persistedValue, forKey: Keys.sourceSelection)
            // A different source may be playing something else entirely,
            // so drop the change-detection key and re-render immediately.
            lastArtworkKey = nil
            poll()
        }
    }

    /// The source the current track came from, for the menu's subtitle.
    var currentSourceName: String? {
        guard let sourceID = currentTrack?.sourceID else { return nil }
        return sources.first { $0.id == sourceID }?.displayName
    }

    private let sources: [NowPlayingSource]
    private let cacheDirectory: URL
    private let wallpaperSetter: WallpaperSetter
    private var pollTimer: Timer?
    private var lastArtworkKey: String?
    private var desktopSync: DesktopSyncObserver?
    /// The last cover art we rendered, kept so a display or Space change
    /// can re-render without asking the source for the artwork again.
    private var lastCover: (image: NSImage, artworkKey: String)?
    /// Wallpaper file per display, from the most recent render.
    private var appliedImageURLs: [String: URL] = [:]
    /// How many files one track costs right now — the cache keeps a fixed
    /// number of tracks, not of files.
    private var distinctRenderedSizes = 1

    private enum Keys {
        static let autoUpdate = "isAutoUpdateEnabled"
        static let sourceSelection = "sourceSelection"
        static let displaySelection = "displaySelection"
    }

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = caches.appendingPathComponent("CoverArtwall", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        wallpaperSetter = WallpaperSetter(cacheDirectory: cacheDirectory)
        sources = SourceRegistry.makeSources()
        isAutoUpdateEnabled = UserDefaults.standard.object(forKey: Keys.autoUpdate) as? Bool ?? true
        sourceSelection = SourceSelection(
            persistedValue: UserDefaults.standard.string(forKey: Keys.sourceSelection)
        )
        displaySelection = DisplaySelection(
            persistedValue: UserDefaults.standard.stringArray(forKey: Keys.displaySelection)
        )

        refreshAvailableSources()
        refreshAvailableDisplays()
        // A display deselected in a previous session may still be showing
        // one of our wallpapers if the app was quit before it could be
        // handed back.
        wallpaperSetter.restore(
            displayIDs: Set(availableDisplays.filter { !displaySelection.includes($0) }.map(\.id))
        )

        desktopSync = DesktopSyncObserver(
            onSpaceChange: { [weak self] in self?.reapplyAppliedWallpapers() },
            onDisplayChange: { [weak self] in self?.displayLayoutChanged() }
        )

        startPolling()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        LoginItemManager.setEnabled(enabled)
        launchAtLoginEnabled = LoginItemManager.isEnabled
    }

    /// Recomputed when the menu opens rather than on every poll — apps get
    /// installed rarely, and each check is a LaunchServices lookup.
    func refreshAvailableSources() {
        availableSources = sources
            .filter(\.isAvailable)
            .map { SourceOption(id: $0.id, displayName: $0.displayName) }
    }

    /// Recomputed when the menu opens and whenever the screen layout
    /// changes, so the display list is never stale in the UI.
    func refreshAvailableDisplays() {
        availableDisplays = DisplayRegistry.connectedDisplays()
    }

    /// The connected displays the wallpaper should currently go on.
    var targetedDisplays: [DisplayInfo] {
        availableDisplays.filter { displaySelection.includes($0) }
    }

    private func displayLayoutChanged() {
        refreshAvailableDisplays()
        // A new or resized display needs a wallpaper at its own size, and
        // a disconnected one shouldn't keep a file alive in the cache.
        reapplyToCurrentDisplays()
    }

    /// Re-renders the last cover for whatever displays are targeted now.
    /// With nothing playing yet there's still work to do: the setter hands
    /// back originals to displays that just got deselected.
    private func reapplyToCurrentDisplays() {
        guard let lastCover else {
            appliedImageURLs = [:]
            wallpaperSetter.apply([:])
            return
        }

        do {
            try renderAndApply(cover: lastCover.image, artworkKey: lastCover.artworkKey)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Re-applies the wallpapers already on disk — no re-render, because
    /// nothing about the images changed, only the Space showing them.
    private func reapplyAppliedWallpapers() {
        guard !appliedImageURLs.isEmpty else { return }
        wallpaperSetter.apply(appliedImageURLs)
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

        let track = resolveCurrentTrack()
        currentTrack = track

        guard let track, track.artworkKey != lastArtworkKey else { return }
        lastArtworkKey = track.artworkKey
        Task { await applyWallpaper(for: track) }
    }

    /// Pinned: ask that one source. Automatic: first registered source
    /// that's running and playing wins.
    private func resolveCurrentTrack() -> TrackInfo? {
        switch sourceSelection {
        case .pinned(let sourceID):
            return sources.first { $0.id == sourceID }?.currentTrack()
        case .automatic:
            for source in sources where source.isRunning {
                if let track = source.currentTrack() { return track }
            }
            return nil
        }
    }

    private func applyWallpaper(for track: TrackInfo) async {
        guard let source = sources.first(where: { $0.id == track.sourceID }) else { return }

        do {
            let data = try await source.loadArtwork(for: track)
            guard let cover = NSImage(data: data) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            lastCover = (image: cover, artworkKey: track.artworkKey)
            try renderAndApply(cover: cover, artworkKey: track.artworkKey)
            lastError = nil
        } catch NowPlayingSourceError.artworkUnavailable {
            // A podcast, a radio stream, a local file with no embedded
            // image. Nothing is wrong — keep the wallpaper as it is and
            // don't nag the user about it.
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Renders one wallpaper per distinct display size, applies each to
    /// its displays, and restores every display that isn't targeted.
    private func renderAndApply(cover: NSImage, artworkKey: String) throws {
        var imageURLsByDisplayID: [String: URL] = [:]
        var renderedBySize: [String: URL] = [:]

        for display in targetedDisplays {
            // Identical displays — the common two-of-the-same-monitor
            // desk — render once and share the file.
            let sizeToken = "\(Int(display.pixelSize.width))x\(Int(display.pixelSize.height))"
            if let existing = renderedBySize[sizeToken] {
                imageURLsByDisplayID[display.id] = existing
                continue
            }

            guard let rendered = WallpaperCompositor.render(cover: cover, targetSize: display.pixelSize),
                  let jpeg = WallpaperCompositor.jpegData(for: rendered) else {
                throw CocoaError(.fileWriteUnknown)
            }

            let wallpaperURL = cacheDirectory
                .appendingPathComponent("wallpaper-\(artworkKey.stableFileIdentifier)-\(sizeToken)")
                .appendingPathExtension("jpg")
            try jpeg.write(to: wallpaperURL)

            renderedBySize[sizeToken] = wallpaperURL
            imageURLsByDisplayID[display.id] = wallpaperURL
        }

        appliedImageURLs = imageURLsByDisplayID
        wallpaperSetter.apply(imageURLsByDisplayID)
        distinctRenderedSizes = max(1, renderedBySize.count)
        updatePreview(from: imageURLsByDisplayID)
        pruneOldWallpapers()
    }

    /// The menu thumbnail: the wallpaper actually on the main display when
    /// it's one of ours, otherwise any of the ones we just applied.
    /// Decoded back from the file on disk, so it's provably what
    /// `NSWorkspace` was handed rather than what was drawn.
    private func updatePreview(from imageURLsByDisplayID: [String: URL]) {
        let mainDisplayID = availableDisplays.first(where: \.isMain)?.id
        let previewURL = mainDisplayID.flatMap { imageURLsByDisplayID[$0] }
            ?? imageURLsByDisplayID.values.first
        guard let previewURL, let data = try? Data(contentsOf: previewURL) else {
            currentWallpaperImage = nil
            return
        }
        currentWallpaperImage = NSImage(data: data)
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

        // 25 tracks' worth of history, one file per distinct display size.
        for stale in sorted.dropFirst(25 * distinctRenderedSizes) {
            try? FileManager.default.removeItem(at: stale)
        }
    }
}
