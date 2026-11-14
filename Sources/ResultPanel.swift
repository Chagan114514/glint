import AppKit
import AVKit
import ImageIO
import UniformTypeIdentifiers

final class ResultPanelController: NSObject, NSWindowDelegate {
    enum Mode {
        case image(captured: CapturedImage?, url: URL)
        case video(url: URL)
    }

    private let mode: Mode
    private let panel: ResultPanel
    private let statusLabel = NSTextField(labelWithString: "")
    private let copyButton = GlintButton(title: "复制", style: .secondary)
    private let exportButton = GlintButton(title: "导出…", style: .primary)
    private let revealButton = GlintIconButton(symbol: "folder", size: 14)
    private var player: AVPlayer?
    private let onClose: (() -> Void)?
    private let isFreshCapture: Bool
    private var savedURL: URL
    private var didCopy: Bool
    private var closed = false

    init(mode: Mode, isFreshCapture: Bool, copied: Bool, onClose: (() -> Void)? = nil) {
        self.mode = mode
        self.isFreshCapture = isFreshCapture
        self.didCopy = copied
        self.onClose = onClose
        switch mode {
        case .image(_, let url): savedURL = url
        case .video(let url): savedURL = url
        }
        panel = ResultPanel(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 404),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
        buildUI(copied: copied)
    }

    deinit {
        player?.pause()
    }

    func show() {
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.maxX - panel.frame.width - 22,
                y: visible.minY + 22
            ))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        player?.pause()
        panel.orderOut(nil)
        onClose?()
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.delegate = self
        panel.contentMinSize = NSSize(width: 430, height: 404)
        panel.contentMaxSize = NSSize(width: 430, height: 404)
    }

    func windowWillClose(_ notification: Notification) {
        close()
    }

    private func buildUI(copied: Bool) {
        let root = ResultSurfaceView(frame: panel.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 430, height: 404))
        root.wantsLayer = true
        root.layer?.cornerRadius = 20
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = root

        let title: String
        let subtitle: String
        let isVideo: Bool
        switch mode {
        case .image(let captured, let url):
            isVideo = false
            title = isFreshCapture ? "截图完成" : "图片预览"
            subtitle = imageSubtitle(captured: captured, url: url)
        case .video(let url):
            isVideo = true
            title = isFreshCapture ? "录制完成" : "视频预览"
            subtitle = videoSubtitle(url: url)
        }

        let titleLabel = makeLabel(title, size: 16, weight: .semibold, color: Palette.text)
        root.addSubview(titleLabel)

        let subtitleLabel = makeLabel(subtitle, size: 10.5, weight: .regular, color: Palette.textSecondary)
        subtitleLabel.lineBreakMode = .byTruncatingMiddle
        root.addSubview(subtitleLabel)

        let close = GlintIconButton(symbol: "xmark", size: 12, target: self, action: #selector(closeTapped))
        root.addSubview(close)

        let preview = NSView()
        preview.wantsLayer = true
        preview.layer?.backgroundColor = NSColor(hex: 0x080B10).cgColor
        preview.layer?.cornerRadius = 12
        preview.layer?.cornerCurve = .continuous
        preview.layer?.borderColor = Palette.stroke.cgColor
        preview.layer?.borderWidth = 1
        preview.layer?.masksToBounds = true
        preview.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(preview)

        if isVideo, case .video(let url) = mode {
            let player = AVPlayer(url: url)
            player.isMuted = true
            self.player = player
            let playerView = AVPlayerView()
            playerView.player = player
            playerView.controlsStyle = .inline
            playerView.videoGravity = .resizeAspect
            playerView.allowsPictureInPicturePlayback = false
            playerView.translatesAutoresizingMaskIntoConstraints = false
            preview.addSubview(playerView)
            NSLayoutConstraint.activate([
                playerView.leadingAnchor.constraint(equalTo: preview.leadingAnchor),
                playerView.trailingAnchor.constraint(equalTo: preview.trailingAnchor),
                playerView.topAnchor.constraint(equalTo: preview.topAnchor),
                playerView.bottomAnchor.constraint(equalTo: preview.bottomAnchor),
            ])
        } else if case .image(let captured, let url) = mode {
            let imageView = NSImageView()
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.imageAlignment = .alignCenter
            imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
            imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
            imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            if let captured {
                imageView.image = NSImage(
                    cgImage: captured.cgImage,
                    size: NSSize(
                        width: CGFloat(captured.cgImage.width) / max(1, captured.scale),
                        height: CGFloat(captured.cgImage.height) / max(1, captured.scale)
                    )
                )
            } else {
                imageView.image = NSImage(contentsOf: url)
            }
            preview.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: preview.leadingAnchor, constant: 2),
                imageView.trailingAnchor.constraint(equalTo: preview.trailingAnchor, constant: -2),
                imageView.topAnchor.constraint(equalTo: preview.topAnchor, constant: 2),
                imageView.bottomAnchor.constraint(equalTo: preview.bottomAnchor, constant: -2),
            ])
        }

        statusLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        statusLabel.textColor = Palette.textTertiary
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(statusLabel)
        updateStatus(copied: copied, exported: false)

        copyButton.target = self
        copyButton.action = #selector(copyTapped)
        copyButton.setSymbol("doc.on.doc")
        root.addSubview(copyButton)

        exportButton.target = self
        exportButton.action = #selector(exportTapped)
        exportButton.setSymbol("square.and.arrow.up")
        root.addSubview(exportButton)

        revealButton.target = self
        revealButton.action = #selector(revealTapped)
        revealButton.toolTip = "在 Finder 中显示"
        root.addSubview(revealButton)

        let hint = makeLabel("\(isVideo ? "视频" : "图片")已保存到 \(isVideo ? "影片/Glint" : "图片/Glint")", size: 10, weight: .regular, color: Palette.textTertiary)
        root.addSubview(hint)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: close.leadingAnchor, constant: -8),

            close.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            close.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            close.widthAnchor.constraint(equalToConstant: 28),
            close.heightAnchor.constraint(equalToConstant: 28),

            preview.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            preview.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            preview.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            preview.heightAnchor.constraint(equalToConstant: 224),

            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            statusLabel.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 10),

            copyButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            copyButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
            copyButton.widthAnchor.constraint(equalToConstant: 88),
            copyButton.heightAnchor.constraint(equalToConstant: 32),

            exportButton.leadingAnchor.constraint(equalTo: copyButton.trailingAnchor, constant: 8),
            exportButton.centerYAnchor.constraint(equalTo: copyButton.centerYAnchor),
            exportButton.widthAnchor.constraint(equalToConstant: 96),
            exportButton.heightAnchor.constraint(equalToConstant: 32),

            revealButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            revealButton.centerYAnchor.constraint(equalTo: copyButton.centerYAnchor),
            revealButton.widthAnchor.constraint(equalToConstant: 32),
            revealButton.heightAnchor.constraint(equalToConstant: 32),

            hint.trailingAnchor.constraint(equalTo: revealButton.leadingAnchor, constant: -8),
            hint.centerYAnchor.constraint(equalTo: copyButton.centerYAnchor),
            hint.leadingAnchor.constraint(greaterThanOrEqualTo: exportButton.trailingAnchor, constant: 6),
        ])
    }

    private func updateStatus(copied: Bool, exported: Bool) {
        let text: String
        let color: NSColor
        if exported {
            text = "已导出副本 · 原文件仍在 Glint 文件夹"
            color = Palette.teal
        } else if copied {
            text = "已复制到剪贴板 · 已自动保存"
            color = Palette.success
        } else {
            text = "已自动保存 · 可复制或导出"
            color = Palette.textTertiary
        }
        statusLabel.stringValue = text
        statusLabel.textColor = color
    }

    private func imageSubtitle(captured: CapturedImage?, url: URL) -> String {
        var pixels: (Int, Int)?
        if let captured {
            pixels = (captured.cgImage.width, captured.cgImage.height)
        } else if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            let width = properties[kCGImagePropertyPixelWidth] as? Int
            let height = properties[kCGImagePropertyPixelHeight] as? Int
            if let width, let height { pixels = (width, height) }
        }
        var parts: [String] = []
        if let pixels { parts.append("\(pixels.0) × \(pixels.1) px") }
        parts.append(fileSizeString(url))
        return parts.joined(separator: "  ·  ")
    }

    private func videoSubtitle(url: URL) -> String {
        var parts = ["屏幕录制", fileSizeString(url)]
        if let duration = videoDuration(url), duration > 0 {
            parts.insert(formatDuration(duration), at: 1)
        }
        return parts.joined(separator: "  ·  ")
    }

    private func videoDuration(_ url: URL) -> Double? {
        let asset = AVURLAsset(url: url)
        let seconds = asset.duration.seconds
        return seconds.isFinite ? seconds : nil
    }

    private func fileSizeString(_ url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values?.fileSize else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: Int64(size))
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    @objc private func copyTapped() {
        switch mode {
        case .image(let captured, let url):
            if let captured {
                if CaptureLibrary.shared.copyToPasteboard(captured) {
                    didCopy = true
                    updateStatus(copied: true, exported: false)
                    flash(copyButton)
                }
            } else if let data = try? Data(contentsOf: url) {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.declareTypes([.png, .tiff], owner: nil)
                pasteboard.setData(data, forType: .png)
                if let image = NSImage(data: data) {
                    pasteboard.setData(image.tiffRepresentation, forType: .tiff)
                }
                didCopy = true
                updateStatus(copied: true, exported: false)
                flash(copyButton)
            }
        case .video(let url):
            if CaptureLibrary.shared.copyFileToPasteboard(url) {
                didCopy = true
                statusLabel.stringValue = "视频文件已复制，可直接粘贴到聊天或文件夹"
                statusLabel.textColor = Palette.success
                flash(copyButton)
            }
        }
    }

    @objc private func exportTapped() {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.title = "导出到…"
        savePanel.prompt = "导出"
        savePanel.nameFieldStringValue = savedURL.lastPathComponent

        let isVideo: Bool
        switch mode {
        case .image: isVideo = false
        case .video: isVideo = true
        }
        savePanel.allowedContentTypes = [isVideo ? .mpeg4Movie : .png]

        NSApp.activate(ignoringOtherApps: true)
        savePanel.begin { [weak self] response in
            guard let self, response == .OK, let destination = savePanel.url else { return }
            self.performExport(to: destination)
        }
    }

    private func performExport(to destination: URL) {
        if destination.standardizedFileURL == savedURL.standardizedFileURL {
            updateStatus(copied: didCopy, exported: true)
            return
        }

        statusLabel.stringValue = "正在导出…"
        statusLabel.textColor = Palette.textSecondary

        let source = savedURL
        let mode = self.mode
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                switch mode {
                case .image(let captured, _):
                    if let captured {
                        try CaptureLibrary.shared.writePNG(captured.cgImage, scale: captured.scale, to: destination)
                    } else {
                        try FileManager.default.copyItem(at: source, to: destination)
                    }
                case .video:
                    try FileManager.default.copyItem(at: source, to: destination)
                }
                DispatchQueue.main.async {
                    self.statusLabel.stringValue = "已导出到 \(destination.deletingLastPathComponent().lastPathComponent)/\(destination.lastPathComponent)"
                    self.statusLabel.textColor = Palette.teal
                    flash(self.exportButton)
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusLabel.stringValue = "导出失败：\(error.localizedDescription)"
                    self.statusLabel.textColor = Palette.danger
                }
            }
        }
    }

    @objc private func revealTapped() {
        CaptureLibrary.shared.reveal(savedURL)
    }

    @objc private func closeTapped() {
        close()
    }
}

private final class ResultPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class ResultSurfaceView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 20, yRadius: 20)
        let gradient = NSGradient(colors: [NSColor(hex: 0x141C26), NSColor(hex: 0x0E141B)])!
        gradient.draw(in: path, angle: -80)
        Palette.strokeStrong.setStroke()
        path.lineWidth = 1
        path.stroke()

        // Accent glint in the upper-right corner.
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let glow = NSGradient(colors: [Palette.accent.withAlphaComponent(0.10), .clear])!
        glow.draw(in: NSBezierPath(ovalIn: NSRect(x: bounds.maxX - 180, y: bounds.maxY - 120, width: 240, height: 240)), relativeCenterPosition: .zero)
        NSGraphicsContext.restoreGraphicsState()
    }
}
