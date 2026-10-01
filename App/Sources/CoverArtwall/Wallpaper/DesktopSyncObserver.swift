import AppKit

/// Watches the two things that can invalidate an applied wallpaper
/// without the music changing.
///
/// - macOS only paints a desktop's wallpaper on Spaces it has already
///   rendered, so switching to a Space that hasn't been visited since the
///   last `setDesktopImageURL` can show a stale image until re-applied.
/// - Plugging in, unplugging, or rearranging a display changes which
///   displays exist and what size their wallpapers should be.
final class DesktopSyncObserver {
    private let onSpaceChange: @MainActor () -> Void
    private let onDisplayChange: @MainActor () -> Void

    init(
        onSpaceChange: @escaping @MainActor () -> Void,
        onDisplayChange: @escaping @MainActor () -> Void
    ) {
        self.onSpaceChange = onSpaceChange
        self.onDisplayChange = onDisplayChange

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func activeSpaceChanged() {
        let handler = onSpaceChange
        Task { @MainActor in handler() }
    }

    @objc private func screenParametersChanged() {
        let handler = onDisplayChange
        Task { @MainActor in handler() }
    }
}
