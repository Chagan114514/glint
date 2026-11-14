import AppKit
import AVFoundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

// MARK: - Capture models

enum CaptureKind: String, Codable {
    case image
    case video
}

struct CaptureItem: Identifiable, Equatable {
    let url: URL
    let kind: CaptureKind
    let createdAt: Date

    var id: URL { url }

    var displayName: String {
        url.deletingPathExtension().lastPathComponent
    }

    var subtitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: createdAt)
    }
}

struct CapturedImage {
    let cgImage: CGImage
    let scale: CGFloat
    let label: String

    var pixelSize: CGSize {
        CGSize(width: cgImage.width, height: cgImage.height)
    }
}

// MARK: - Errors

enum GlintError: LocalizedError {
    case noPermission
    case displayUnavailable
    case noWindows
    case emptyImage
    case recordingFailed(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .noPermission:
            return "还没有获得「屏幕与系统音频录制」权限。请在系统设置中允许 Glint 访问屏幕后重试。"
        case .displayUnavailable:
            return "找不到要捕获的显示器，请重新打开 Glint 再试。"
        case .noWindows:
            return "当前没有可截取的窗口。请先打开一个应用窗口。"
        case .emptyImage:
            return "画面捕获失败，没有得到有效的图像。"
        case .recordingFailed(let reason):
            return "录制失败：\(reason)"
        case .saveFailed(let reason):
            return "保存失败：\(reason)"
        }
    }
}

// MARK: - Permission

enum ScreenPermission {
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenRecording",
        ]
        for raw in urls {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}

// MARK: - Preferences

enum Prefs {
    private static let audioKey = "GlintRecordSystemAudio"

    static var includeSystemAudio: Bool {
        get {
            if UserDefaults.standard.object(forKey: audioKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: audioKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: audioKey)
        }
    }

    static var hasLaunchedBefore: Bool {
        get { UserDefaults.standard.bool(forKey: "GlintHasLaunched") }
        set { UserDefaults.standard.set(newValue, forKey: "GlintHasLaunched") }
    }
}

// MARK: - Library

final class CaptureLibrary {
    static let shared = CaptureLibrary()
    static let libraryChanged = Notification.Name("GlintLibraryChanged")

    let imageDirectory: URL
    let videoDirectory: URL

    private let fileManager = FileManager.default
    private let fileNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()

    private init() {
        let pictures = fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Pictures", isDirectory: true)
        let movies = fileManager.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Movies", isDirectory: true)
        imageDirectory = pictures.appendingPathComponent("Glint", isDirectory: true)
        videoDirectory = movies.appendingPathComponent("Glint", isDirectory: true)
        try? fileManager.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: videoDirectory, withIntermediateDirectories: true)
    }

    func imageURL() -> URL {
        uniqueURL(in: imageDirectory, prefix: "Glint", ext: "png")
    }

    func videoURL() -> URL {
        uniqueURL(in: videoDirectory, prefix: "Glint_Record", ext: "mp4")
    }

    private func uniqueURL(in directory: URL, prefix: String, ext: String) -> URL {
        let stamp = fileNameFormatter.string(from: Date())
        var candidate = directory.appendingPathComponent("\(prefix)_\(stamp).\(ext)")
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(prefix)_\(stamp)-\(index).\(ext)")
            index += 1
        }
        return candidate
    }

    @discardableResult
    func saveImage(_ captured: CapturedImage) throws -> URL {
        let url = imageURL()
        try writePNG(captured.cgImage, scale: captured.scale, to: url)
        NotificationCenter.default.post(name: Self.libraryChanged, object: nil)
        return url
    }

    func saveImage(_ cgImage: CGImage, scale: CGFloat) throws -> URL {
        let url = imageURL()
        try writePNG(cgImage, scale: scale, to: url)
        NotificationCenter.default.post(name: Self.libraryChanged, object: nil)
        return url
    }

    func writePNG(_ cgImage: CGImage, scale: CGFloat, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw GlintError.saveFailed("无法创建 PNG 文件")
        }
        let dpi = 72.0 * max(1, scale)
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw GlintError.saveFailed("写入 PNG 数据时出错")
        }
    }

    func pngData(for captured: CapturedImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: captured.cgImage)
        rep.size = NSSize(
            width: CGFloat(captured.cgImage.width) / max(1, captured.scale),
            height: CGFloat(captured.cgImage.height) / max(1, captured.scale)
        )
        return rep.representation(using: .png, properties: [.compressionFactor: 1.0])
    }

    func copyToPasteboard(_ captured: CapturedImage) -> Bool {
        guard let png = pngData(for: captured) else { return false }
        let image = NSImage(size: NSSize(
            width: CGFloat(captured.cgImage.width) / max(1, captured.scale),
            height: CGFloat(captured.cgImage.height) / max(1, captured.scale)
        ))
        image.addRepresentation(NSBitmapImageRep(data: png) ?? NSBitmapImageRep(cgImage: captured.cgImage))

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        pasteboard.setData(png, forType: .png)
        if let tiff = image.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
        return true
    }

    func copyFileToPasteboard(_ url: URL) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([url as NSURL])
    }

    func recent(limit: Int = 8) -> [CaptureItem] {
        var items: [CaptureItem] = []
        for directory in [imageDirectory, videoDirectory] {
            let urls = (try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for url in urls {
                let ext = url.pathExtension.lowercased()
                let kind: CaptureKind?
                switch ext {
                case "png", "jpg", "jpeg": kind = .image
                case "mp4", "mov": kind = .video
                default: kind = nil
                }
                guard let kind else { continue }
                let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .isRegularFileKey])
                guard values?.isRegularFile != false else { continue }
                let date = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
                items.append(CaptureItem(url: url, kind: kind, createdAt: date))
            }
        }
        return Array(items.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openFolder(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Thumbnails

final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private var cache: [URL: NSImage] = [:]
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "local.glint.thumbnails", qos: .userInitiated, attributes: .concurrent)

    func cached(_ url: URL) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        return cache[url]
    }

    func load(_ item: CaptureItem, completion: @escaping (NSImage?) -> Void) {
        if let image = cached(item.url) {
            completion(image)
            return
        }
        queue.async { [weak self] in
            guard let self else { return }
            let image: NSImage?
            switch item.kind {
            case .image:
                image = Self.imageThumbnail(item.url)
            case .video:
                image = Self.videoThumbnail(item.url)
            }
            if let image {
                self.lock.lock()
                self.cache[item.url] = image
                self.lock.unlock()
            }
            DispatchQueue.main.async { completion(image) }
        }
    }

    private static func imageThumbnail(_ url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 360,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private static func videoThumbnail(_ url: URL) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 360, height: 240)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        for seconds in [0.1, 0.0, 0.5] {
            if let cg = try? generator.copyCGImage(at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil) {
                return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
        }
        return nil
    }
}

// MARK: - Screen lookup

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    var glintName: String {
        localizedName
    }
}

extension SCDisplay {
    var pointSize: CGSize {
        CGSize(width: width, height: height)
    }
}
