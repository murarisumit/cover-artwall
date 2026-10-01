import AppKit
import ColorSync

/// One connected display, in the terms the rest of the app cares about:
/// something stable to persist a choice against, a name to show in the
/// menu, and the pixel size a wallpaper for it should be rendered at.
struct DisplayInfo: Identifiable, Hashable {
    /// Stable across reboots, sleep, and unplugging the cable — unlike
    /// `CGDirectDisplayID`, which macOS hands out fresh each session. This
    /// is what gets persisted when someone picks specific displays.
    let id: String
    let name: String
    /// Backing-store pixels, i.e. the wallpaper's natural size for this
    /// display. Two displays of the same size share a rendered image.
    let pixelSize: CGSize
    /// Whether this is the display the menu bar is on.
    let isMain: Bool
}

enum DisplayRegistry {
    /// Displays currently connected, in `NSScreen.screens` order.
    @MainActor
    static func connectedDisplays() -> [DisplayInfo] {
        NSScreen.screens.map { screen in
            DisplayInfo(
                id: stableID(for: screen),
                name: screen.localizedName,
                pixelSize: CGSize(
                    width: screen.frame.width * screen.backingScaleFactor,
                    height: screen.frame.height * screen.backingScaleFactor
                ),
                isMain: screen == NSScreen.main
            )
        }
    }

    /// The display UUID macOS keeps per physical monitor. Falls back to the
    /// session-scoped display number if the UUID can't be resolved — worse
    /// (a selection may not survive a reconnect) but never wrong within a
    /// session, and it still tells two identical monitors apart.
    @MainActor
    static func stableID(for screen: NSScreen) -> String {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let displayID = CGDirectDisplayID(number?.uint32Value ?? 0)

        if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
           let string = CFUUIDCreateString(nil, uuid) as String? {
            return string
        }
        return "display-number-\(displayID)"
    }
}

/// Which displays the wallpaper is applied to.
///
/// `.allDisplays` is the default and follows the Mac as monitors come and
/// go; `.only` pins an explicit set, so a display that's unplugged and
/// plugged back in keeps whatever the user chose for it.
enum DisplaySelection: Hashable {
    case allDisplays
    case only(Set<String>)

    private static let allToken = "*"

    func includes(_ display: DisplayInfo) -> Bool {
        switch self {
        case .allDisplays: return true
        case .only(let ids): return ids.contains(display.id)
        }
    }

    /// Turning one display off while in `.allDisplays` first materializes
    /// the current set, so "all except the TV" is one click rather than a
    /// re-selection of everything else.
    func setting(_ display: DisplayInfo, enabled: Bool, among displays: [DisplayInfo]) -> DisplaySelection {
        var ids: Set<String>
        switch self {
        case .allDisplays: ids = Set(displays.map(\.id))
        case .only(let existing): ids = existing
        }

        if enabled {
            ids.insert(display.id)
        } else {
            ids.remove(display.id)
        }
        return .only(ids)
    }

    var persistedValue: [String] {
        switch self {
        case .allDisplays: return [Self.allToken]
        case .only(let ids): return ids.sorted()
        }
    }

    init(persistedValue: [String]?) {
        switch persistedValue {
        case nil: self = .allDisplays
        case let values? where values == [Self.allToken]: self = .allDisplays
        case let values?: self = .only(Set(values))
        }
    }
}
