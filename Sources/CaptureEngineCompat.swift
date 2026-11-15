#if GLINT_COMPAT
import AppKit
import CoreGraphics

/// macOS 11 compatible capture backend. It deliberately uses the older
/// CGWindowList/CGDisplay APIs so the app does not link ScreenCaptureKit.
final class CaptureEngine {
    static let shared = CaptureEngine()

    private init() {}

    private var ownPID: pid_t { ProcessInfo.processInfo.processIdentifier }

    func loadContent() async throws -> SCShareableContent {
        guard ScreenPermission.isGranted else { throw GlintError.noPermission }

        let displays = NSScreen.screens.compactMap { screen -> SCDisplay? in
            guard let id = screen.displayID else { return nil }
            return SCDisplay(displayID: id, width: Int(screen.frame.width), height: Int(screen.frame.height))
        }

        var windows: [SCWindow] = []
        var apps: [CompatApplication] = []
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        if let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
            for info in raw {
                guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID else { continue }
                let layer = info[kCGWindowLayer as String] as? Int ?? 0
                guard layer == 0 else { continue }
                let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
                guard alpha > 0 else { continue }
                guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                      let frame = CGRect(dictionaryRepresentation: boundsDict) else { continue }
                guard frame.width >= 120, frame.height >= 80 else { continue }
                guard let windowID = info[kCGWindowNumber as String] as? CGWindowID else { continue }
                let ownerName = info[kCGWindowOwnerName as String] as? String ?? "应用"
                guard ownerName != "Window Server", ownerName != "Dock" else { continue }
                let title = (info[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let onScreen = info[kCGWindowIsOnscreen as String] as? Bool ?? true
                let app = CompatApplication(applicationName: ownerName, bundleIdentifier: nil, processID: pid)
                if !apps.contains(where: { $0.processID == pid }) { apps.append(app) }
                windows.append(SCWindow(
                    windowID: windowID,
                    frame: frame,
                    title: title,
                    owningApplication: app,
                    isOnScreen: onScreen,
                    windowLayer: layer
                ))
            }
        }

        windows.sort { lhs, rhs in
            if lhs.frame.width * lhs.frame.height != rhs.frame.width * rhs.frame.height {
                return lhs.frame.width * lhs.frame.height > rhs.frame.width * rhs.frame.height
            }
            return lhs.windowID < rhs.windowID
        }
        return SCShareableContent(displays: displays, windows: windows, applications: apps)
    }

    func loadWindows(limit: Int = 24) async throws -> [SCWindow] {
        let content = try await loadContent()
        return Array(content.windows.prefix(limit))
    }

    func captureFullScreen(screen: NSScreen) async throws -> CapturedImage {
        guard ScreenPermission.isGranted else { throw GlintError.noPermission }
        guard let id = screen.displayID else { throw GlintError.displayUnavailable }
        guard let image = CGDisplayCreateImage(id) ?? screenShot(rect: CGDisplayBounds(id)) else {
            throw GlintError.emptyImage
        }
        let scale = max(1, CGFloat(image.width) / max(1, screen.frame.width))
        return CapturedImage(cgImage: image, scale: scale, label: screen.glintName)
    }

    func captureArea(screen: NSScreen, localRect: CGRect) async throws -> CapturedImage {
        guard ScreenPermission.isGranted else { throw GlintError.noPermission }
        let clipped = localRect.intersection(CGRect(origin: .zero, size: screen.frame.size)).integral
        guard clipped.width >= 1, clipped.height >= 1 else { throw GlintError.emptyImage }
        guard let id = screen.displayID, let full = CGDisplayCreateImage(id) else {
            throw GlintError.emptyImage
        }
        let scale = max(1, CGFloat(full.width) / max(1, screen.frame.width))
        let pixelRect = CGRect(
            x: clipped.minX * scale,
            y: (screen.frame.height - clipped.maxY) * scale,
            width: clipped.width * scale,
            height: clipped.height * scale
        ).integral
        guard let cropped = full.cropping(to: pixelRect) else { throw GlintError.emptyImage }
        let label = "\(screen.glintName) · \(Int(clipped.width))×\(Int(clipped.height))"
        return CapturedImage(cgImage: cropped, scale: scale, label: label)
    }

    func captureWindow(_ window: SCWindow) async throws -> CapturedImage {
        guard ScreenPermission.isGranted else { throw GlintError.noPermission }
        guard let image = windowShot(window.windowID) else { throw GlintError.emptyImage }
        let scale = max(1, CGFloat(image.width) / max(1, window.frame.width))
        let appName = window.owningApplication?.applicationName ?? "窗口"
        let title = (window.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let label = title.isEmpty ? appName : "\(appName) — \(title)"
        return CapturedImage(cgImage: image, scale: scale, label: label)
    }

    func windowThumbnail(_ window: SCWindow) async -> NSImage? {
        guard let image = windowShot(window.windowID) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    func display(for screen: NSScreen, in content: SCShareableContent) throws -> SCDisplay {
        guard let id = screen.displayID,
              let display = content.displays.first(where: { $0.displayID == id }) else {
            throw GlintError.displayUnavailable
        }
        return display
    }

    // MARK: - CG fallbacks

    private func windowShot(_ id: CGWindowID) -> CGImage? {
        CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            id,
            [.bestResolution, .boundsIgnoreFraming]
        )
    }

    private func screenShot(rect: CGRect) -> CGImage? {
        CGWindowListCreateImage(
            rect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .boundsIgnoreFraming]
        )
    }
}
#endif
