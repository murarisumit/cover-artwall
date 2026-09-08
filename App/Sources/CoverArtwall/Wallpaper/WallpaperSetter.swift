import AppKit

/// Applies a rendered wallpaper image to every connected screen.
enum WallpaperSetter {
    static func apply(imageURL: URL) {
        let workspace = NSWorkspace.shared
        for screen in NSScreen.screens {
            try? workspace.setDesktopImageURL(imageURL, for: screen, options: [:])
        }
    }
}
