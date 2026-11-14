import AppKit
import ScreenCaptureKit

final class CaptureEngine {
    static let shared = CaptureEngine()

    private init() {}

    // MARK: - Shareable content

    func loadContent() async throws -> SCShareableContent {
        do {
            return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            if ScreenPermission.isGranted {
                throw GlintError.recordingFailed(error.localizedDescription)
            }
            throw GlintError.noPermission
        }
    }

    func loadWindows(limit: Int = 24) async throws -> [SCWindow] {
        let content = try await loadContent()
        guard let selfBundle = Bundle.main.bundleIdentifier else { return filterWindows(content.windows, limit: limit) }
        let windows = content.windows.filter { window in
            guard window.isOnScreen, window.windowLayer == 0 else { return false }
            guard window.frame.width >= 120, window.frame.height >= 80 else { return false }
            guard let title = window.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            guard let app = window.owningApplication else { return false }
            guard app.bundleIdentifier != selfBundle else { return false }
            guard app.applicationName != "Window Server", app.applicationName != "Dock" else { return false }
            return true
        }
        return Array(windows.prefix(limit))
    }

    private func filterWindows(_ windows: [SCWindow], limit: Int) -> [SCWindow] {
        Array(windows.filter {
            $0.isOnScreen && $0.windowLayer == 0 && $0.frame.width >= 120 && $0.frame.height >= 80
                && !($0.title ?? "").isEmpty
        }.prefix(limit))
    }

    // MARK: - Screenshots

    func captureFullScreen(screen: NSScreen) async throws -> CapturedImage {
        let content = try await loadContent()
        let display = try display(for: screen, in: content)
        let filter = displayFilter(display, content: content)
        let scale = CGFloat(filter.pointPixelScale)

        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(origin: .zero, size: CGSize(width: display.width, height: display.height))
        config.width = max(1, Int(round(CGFloat(display.width) * scale)))
        config.height = max(1, Int(round(CGFloat(display.height) * scale)))
        config.showsCursor = false
        config.scalesToFit = false
        config.captureResolution = .best
        config.ignoreShadowsDisplay = true

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return CapturedImage(cgImage: image, scale: scale, label: screen.glintName)
    }

    func captureArea(screen: NSScreen, localRect: CGRect) async throws -> CapturedImage {
        let content = try await loadContent()
        let display = try display(for: screen, in: content)
        let filter = displayFilter(display, content: content)
        let scale = CGFloat(filter.pointPixelScale)

        let screenBounds = CGRect(origin: .zero, size: screen.frame.size)
        let clipped = localRect.intersection(screenBounds).integral
        guard clipped.width >= 1, clipped.height >= 1 else { throw GlintError.emptyImage }

        // AppKit screen coordinates start at the bottom-left; ScreenCaptureKit's
        // sourceRect is expressed from the display's top-left corner.
        let sourceRect = CGRect(
            x: clipped.minX,
            y: screen.frame.height - clipped.maxY,
            width: clipped.width,
            height: clipped.height
        )

        let config = SCStreamConfiguration()
        config.sourceRect = sourceRect
        config.width = max(1, Int(round(clipped.width * scale)))
        config.height = max(1, Int(round(clipped.height * scale)))
        config.showsCursor = false
        config.scalesToFit = false
        config.captureResolution = .best
        config.ignoreShadowsDisplay = true

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let label = "\(screen.glintName) · \(Int(clipped.width))×\(Int(clipped.height))"
        return CapturedImage(cgImage: image, scale: scale, label: label)
    }

    func captureWindow(_ window: SCWindow) async throws -> CapturedImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = max(1, CGFloat(filter.pointPixelScale))
        let frame = window.frame
        guard frame.width >= 1, frame.height >= 1 else { throw GlintError.emptyImage }

        let config = SCStreamConfiguration()
        config.width = max(2, Int(round(frame.width * scale)))
        config.height = max(2, Int(round(frame.height * scale)))
        config.showsCursor = false
        config.scalesToFit = true
        config.preservesAspectRatio = true
        config.ignoreShadowsSingleWindow = true
        config.ignoreGlobalClipSingleWindow = true
        config.shouldBeOpaque = false
        config.captureResolution = .best

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let appName = window.owningApplication?.applicationName ?? "窗口"
        let title = (window.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let label = title.isEmpty ? appName : "\(appName) — \(title)"
        return CapturedImage(cgImage: image, scale: scale, label: label)
    }

    func windowThumbnail(_ window: SCWindow) async -> NSImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let frame = window.frame
        guard frame.width >= 1, frame.height >= 1 else { return nil }

        let targetWidth: CGFloat = 560
        let targetHeight = min(560, max(120, targetWidth * frame.height / frame.width))
        let config = SCStreamConfiguration()
        config.width = Int(targetWidth)
        config.height = Int(targetHeight)
        config.showsCursor = false
        config.scalesToFit = true
        config.preservesAspectRatio = true
        config.ignoreShadowsSingleWindow = true
        config.ignoreGlobalClipSingleWindow = true
        config.shouldBeOpaque = false
        config.captureResolution = .best

        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        } catch {
            return nil
        }
    }

    // MARK: - Display helpers

    func display(for screen: NSScreen, in content: SCShareableContent) throws -> SCDisplay {
        guard let id = screen.displayID,
              let display = content.displays.first(where: { $0.displayID == id }) else {
            throw GlintError.displayUnavailable
        }
        return display
    }

    func displayFilter(_ display: SCDisplay, content: SCShareableContent) -> SCContentFilter {
        let bundle = Bundle.main.bundleIdentifier
        let selfApps = content.applications.filter { $0.bundleIdentifier == bundle }
        return SCContentFilter(display: display, excludingApplications: selfApps, exceptingWindows: [])
    }
}
