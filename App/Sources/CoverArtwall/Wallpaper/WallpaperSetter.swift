import AppKit

/// Applies rendered wallpapers to the displays that are opted in, and puts
/// back what was there before on the ones that aren't.
///
/// The restore half matters: turning a display off in the menu should hand
/// it back its old wallpaper, not leave it stuck on whatever cover was
/// playing at the time. Originals are recorded the first time a display is
/// taken over and persisted, so a quit-and-relaunch can still undo it.
@MainActor
final class WallpaperSetter {
    /// Recorded for a display we took over but whose previous wallpaper we
    /// couldn't read (or that was already one of ours). Keeps the record
    /// from being re-read on every apply.
    private static let unknownOriginal = ""

    private let cacheDirectory: URL
    private let defaults: UserDefaults
    private var originals: [String: String]

    private enum Keys {
        static let originals = "originalWallpapersByDisplay"
    }

    init(cacheDirectory: URL, defaults: UserDefaults = .standard) {
        self.cacheDirectory = cacheDirectory
        self.defaults = defaults
        originals = defaults.dictionary(forKey: Keys.originals) as? [String: String] ?? [:]
    }

    /// Sets each connected display to its entry in `imageURLsByDisplayID`.
    /// A connected display with no entry is restored to its original
    /// wallpaper — that's how deselecting a display takes effect.
    func apply(_ imageURLsByDisplayID: [String: URL]) {
        let workspace = NSWorkspace.shared

        for screen in NSScreen.screens {
            let displayID = DisplayRegistry.stableID(for: screen)

            if let imageURL = imageURLsByDisplayID[displayID] {
                rememberOriginal(of: screen, displayID: displayID)
                try? workspace.setDesktopImageURL(imageURL, for: screen, options: [:])
            } else if let original = takeOriginal(for: displayID) {
                try? workspace.setDesktopImageURL(original, for: screen, options: [:])
            }
        }
    }

    /// Hands specific displays back their original wallpaper, leaving the
    /// rest alone. `apply` covers the steady state; this is for the one
    /// case it can't — restoring at launch a display that was deselected
    /// while the app wasn't running to notice.
    func restore(displayIDs: Set<String>) {
        for screen in NSScreen.screens {
            let displayID = DisplayRegistry.stableID(for: screen)
            guard displayIDs.contains(displayID), let original = takeOriginal(for: displayID) else { continue }
            try? NSWorkspace.shared.setDesktopImageURL(original, for: screen, options: [:])
        }
    }

    private func rememberOriginal(of screen: NSScreen, displayID: String) {
        guard originals[displayID] == nil else { return }

        let current = NSWorkspace.shared.desktopImageURL(for: screen)
        // A wallpaper we rendered isn't an original worth restoring — most
        // likely we're re-applying after a Space switch or a relaunch.
        let isOurs = current.map { $0.path.hasPrefix(cacheDirectory.path) } ?? true
        originals[displayID] = isOurs ? Self.unknownOriginal : (current?.path ?? Self.unknownOriginal)
        persistOriginals()
    }

    /// The recorded original for a display, forgotten as it's handed back.
    private func takeOriginal(for displayID: String) -> URL? {
        guard let path = originals.removeValue(forKey: displayID) else { return nil }
        persistOriginals()
        guard path != Self.unknownOriginal, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    private func persistOriginals() {
        defaults.set(originals, forKey: Keys.originals)
    }
}
