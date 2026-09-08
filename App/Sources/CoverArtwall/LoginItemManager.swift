import Foundation
import ServiceManagement

/// Registers this app itself as a login item — no separate helper target
/// or LaunchAgent plist needed on macOS 13+.
enum LoginItemManager {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("SpotifyArtWallpaper: failed to update login item: \(error.localizedDescription)")
        }
    }
}
