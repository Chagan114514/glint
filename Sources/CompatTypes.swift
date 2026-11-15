#if GLINT_COMPAT
import AppKit

/// Minimal stand-ins for the ScreenCaptureKit value types used by the
/// compatibility build. The UI only needs metadata, never SCStream.
struct CompatApplication {
    let applicationName: String
    let bundleIdentifier: String?
    let processID: pid_t
}

struct SCWindow {
    let windowID: CGWindowID
    let frame: CGRect
    let title: String?
    let owningApplication: CompatApplication?
    let isOnScreen: Bool
    let windowLayer: Int
}

struct SCDisplay {
    let displayID: CGDirectDisplayID
    let width: Int
    let height: Int

    var pointSize: CGSize {
        CGSize(width: width, height: height)
    }
}

struct SCShareableContent {
    let displays: [SCDisplay]
    let windows: [SCWindow]
    let applications: [CompatApplication]
}
#endif
