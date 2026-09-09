import Foundation

/// Compiles an AppleScript once and runs it on demand, handing back the
/// result as a string or as raw bytes.
///
/// Everything stays on the main thread on purpose: `NSAppleScript` is not
/// thread-safe and Apple Event replies are delivered to the main run loop.
/// The cost of that is real, so sources keep their per-poll script small
/// and only reach for an expensive one (Apple Music's artwork bytes) when
/// the track has actually changed — roughly once a song.
@MainActor
final class AppleScriptRunner {
    private let source: String
    private var compiled: NSAppleScript?

    init(_ source: String) {
        self.source = source
    }

    /// Runs the script. Returns `nil` on any error, which for these
    /// scripts means the same thing as an empty result: the app is idle,
    /// or the user hasn't answered the Automation prompt yet.
    func run() -> NSAppleEventDescriptor? {
        let script: NSAppleScript
        if let compiled {
            script = compiled
        } else {
            guard let fresh = NSAppleScript(source: source) else { return nil }
            compiled = fresh
            script = fresh
        }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        return errorInfo == nil ? result : nil
    }

    /// Runs the script and splits its string result on tabs — the shape
    /// every now-playing script here returns.
    func runForFields(expecting count: Int) -> [String]? {
        guard let raw = run()?.stringValue else { return nil }
        let fields = raw.components(separatedBy: "\t")
        return fields.count == count ? fields : nil
    }

    /// Runs the script and returns its result as raw bytes, for scripts
    /// that hand back image data rather than text.
    func runForData() -> Data? {
        guard let result = run() else { return nil }
        let data = result.data
        return data.isEmpty ? nil : data
    }
}
