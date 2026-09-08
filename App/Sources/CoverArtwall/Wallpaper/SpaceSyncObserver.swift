import AppKit

/// macOS only paints a desktop's wallpaper on Spaces it has already
/// rendered. Switching to a Space that hasn't been visited since the last
/// `setDesktopImageURL` call can show a stale image until re-applied, so
/// this re-applies the current wallpaper whenever the active Space changes.
final class SpaceSyncObserver {
    private var currentImageURL: URL?

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared
        )
    }

    func update(currentImageURL: URL) {
        self.currentImageURL = currentImageURL
    }

    @objc private func activeSpaceChanged() {
        guard let currentImageURL else { return }
        WallpaperSetter.apply(imageURL: currentImageURL)
    }
}
