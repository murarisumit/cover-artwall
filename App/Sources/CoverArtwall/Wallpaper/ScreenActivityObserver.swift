import AppKit

/// Reports when the desktop stops and starts being visible, so the poll
/// loop can stand down while nobody can see the wallpaper.
///
/// Polling costs an Apple Event to the music app every few seconds, which
/// keeps that app awake and keeps this one off idle — pointless when the
/// displays are asleep or the screen is locked. Wallpaper that can't be
/// seen doesn't need to be current; it only needs to be right by the time
/// someone looks again, which is what the wake callback is for.
final class ScreenActivityObserver {
    private let onIdle: @MainActor () -> Void
    private let onActive: @MainActor () -> Void

    /// Screen lock isn't published through `NSWorkspace`; it's a system
    /// distributed notification. It's also the one signal here that a
    /// sandboxed build may not receive — if it never arrives the app simply
    /// keeps polling, which is the behaviour it had before.
    private static let screenLocked = Notification.Name("com.apple.screenIsLocked")
    private static let screenUnlocked = Notification.Name("com.apple.screenIsUnlocked")

    init(
        onIdle: @escaping @MainActor () -> Void,
        onActive: @escaping @MainActor () -> Void
    ) {
        self.onIdle = onIdle
        self.onActive = onActive

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            self,
            selector: #selector(becameIdle),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        workspace.addObserver(
            self,
            selector: #selector(becameActive),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(
            self,
            selector: #selector(becameIdle),
            name: Self.screenLocked,
            object: nil
        )
        distributed.addObserver(
            self,
            selector: #selector(becameActive),
            name: Self.screenUnlocked,
            object: nil
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func becameIdle() {
        let handler = onIdle
        Task { @MainActor in handler() }
    }

    @objc private func becameActive() {
        let handler = onActive
        Task { @MainActor in handler() }
    }
}
