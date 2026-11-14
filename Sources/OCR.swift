import AppKit
import Vision

enum OCRError: LocalizedError {
    case noImage
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noImage: return "无法读取这张图片。"
        case .failed(let reason): return "文字识别失败：\(reason)"
        }
    }
}

struct OCRResult {
    let text: String
    let lineCount: Int
}

enum OCRService {
    static func recognize(cgImage: CGImage) async throws -> OCRResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["zh-Hans", "en-US"]
                if #available(macOS 13.0, *) {
                    request.automaticallyDetectsLanguage = true
                }

                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
                do {
                    try handler.perform([request])
                    let observations = request.results ?? []
                    let sorted = observations.sorted { lhs, rhs in
                        let ly = lhs.boundingBox.midY
                        let ry = rhs.boundingBox.midY
                        if abs(ly - ry) > 0.012 {
                            return ly > ry
                        }
                        return lhs.boundingBox.minX < rhs.boundingBox.minX
                    }

                    var lines: [String] = []
                    var lastY: CGFloat?
                    for observation in sorted {
                        guard let candidate = observation.topCandidates(1).first else { continue }
                        let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { continue }
                        if let lastY, abs(lastY - observation.boundingBox.midY) <= 0.012,
                           let last = lines.popLast() {
                            lines.append(last + " " + text)
                        } else {
                            lines.append(text)
                        }
                        lastY = observation.boundingBox.midY
                    }

                    let text = lines.joined(separator: "\n")
                    continuation.resume(returning: OCRResult(text: text, lineCount: lines.count))
                } catch {
                    continuation.resume(throwing: OCRError.failed(error.localizedDescription))
                }
            }
        }
    }
}

final class OCRPanelController: NSObject, NSWindowDelegate {
    private let panel: OCRPanel
    private let image: CGImage
    private let onClose: (() -> Void)?
    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private let statusLabel = NSTextField(labelWithString: "正在识别…")
    private let copyButton = GlintButton(title: "复制全部", style: .primary)
    private let saveButton = GlintButton(title: "保存 TXT…", style: .secondary)
    private let spinner = NSProgressIndicator()
    private var result: OCRResult?
    private var closed = false

    init(image: CGImage, onClose: (() -> Void)? = nil) {
        self.image = image
        self.onClose = onClose
        panel = OCRPanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 520),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
        buildUI()
        runOCR()
    }

    deinit {}

    func show() {
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.midX - panel.frame.width / 2,
                y: visible.midY - panel.frame.height / 2
            ))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
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
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.delegate = self
        panel.contentMinSize = NSSize(width: 540, height: 520)
        panel.contentMaxSize = NSSize(width: 540, height: 520)
    }

    private func buildUI() {
        let root = OCRSurfaceView(frame: NSRect(x: 0, y: 0, width: 540, height: 520))
        root.wantsLayer = true
        root.layer?.cornerRadius = 20
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = root

        let icon = makeSymbol("text.viewfinder", size: 16, weight: .semibold, color: Palette.teal)
        root.addSubview(icon)
        let title = makeLabel("识别文字", size: 19, weight: .semibold, color: Palette.text)
        root.addSubview(title)
        let subtitle = makeLabel("使用 Apple Vision 在本机识别，不会上传截图", size: 10, weight: .regular, color: Palette.textSecondary)
        root.addSubview(subtitle)
        let close = GlintIconButton(symbol: "xmark", size: 12, target: self, action: #selector(closeTapped))
        root.addSubview(close)

        let background = OCRTextBackgroundView()
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.cornerCurve = .continuous
        background.layer?.borderColor = Palette.stroke.cgColor
        background.layer?.borderWidth = 1
        background.layer?.masksToBounds = true
        background.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(background)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textColor = Palette.text
        textView.font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 496, height: CGFloat.greatestFiniteMagnitude)
        textView.frame = NSRect(x: 0, y: 0, width: 496, height: 328)
        textView.string = ""
        scrollView.documentView = textView

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(spinner)

        statusLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        statusLabel.textColor = Palette.textTertiary
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(statusLabel)

        copyButton.target = self
        copyButton.action = #selector(copyTapped)
        copyButton.setSymbol("doc.on.doc")
        copyButton.isEnabled = false
        copyButton.alphaValue = 0.5
        root.addSubview(copyButton)

        saveButton.target = self
        saveButton.action = #selector(saveTapped)
        saveButton.setSymbol("square.and.arrow.up")
        saveButton.isEnabled = false
        saveButton.alphaValue = 0.5
        root.addSubview(saveButton)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            icon.topAnchor.constraint(equalTo: root.topAnchor, constant: 25),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 19),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 1),
            close.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            close.topAnchor.constraint(equalTo: root.topAnchor, constant: 17),
            close.widthAnchor.constraint(equalToConstant: 28),
            close.heightAnchor.constraint(equalToConstant: 28),

            background.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            background.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            background.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 16),
            background.heightAnchor.constraint(equalToConstant: 332),

            scrollView.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 2),
            scrollView.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -2),
            scrollView.topAnchor.constraint(equalTo: background.topAnchor, constant: 2),
            scrollView.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -2),

            spinner.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: background.centerYAnchor),

            statusLabel.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 2),
            statusLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            statusLabel.topAnchor.constraint(equalTo: background.bottomAnchor, constant: 10),

            copyButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            copyButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
            copyButton.widthAnchor.constraint(equalToConstant: 100),
            copyButton.heightAnchor.constraint(equalToConstant: 32),

            saveButton.leadingAnchor.constraint(equalTo: copyButton.trailingAnchor, constant: 8),
            saveButton.centerYAnchor.constraint(equalTo: copyButton.centerYAnchor),
            saveButton.widthAnchor.constraint(equalToConstant: 100),
            saveButton.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    private func runOCR() {
        spinner.startAnimation(nil)
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let result = try await OCRService.recognize(cgImage: self.image)
                await MainActor.run {
                    self.result = result
                    self.spinner.stopAnimation(nil)
                    self.spinner.isHidden = true
                    self.textView.string = result.text.isEmpty ? "未识别到文字。\n\n请尝试放大截图或选择更清晰的图片。" : result.text
                    self.statusLabel.stringValue = result.text.isEmpty
                        ? "没有识别到文字"
                        : "\(result.lineCount) 行 · \(result.text.count) 个字符"
                    self.statusLabel.textColor = result.text.isEmpty ? Palette.accent : Palette.textTertiary
                    let hasText = !result.text.isEmpty
                    self.copyButton.isEnabled = hasText
                    self.saveButton.isEnabled = hasText
                    self.copyButton.alphaValue = hasText ? 1 : 0.5
                    self.saveButton.alphaValue = hasText ? 1 : 0.5
                }
            } catch {
                await MainActor.run {
                    self.spinner.stopAnimation(nil)
                    self.spinner.isHidden = true
                    self.textView.string = "文字识别失败。\n\n\(error.localizedDescription)"
                    self.statusLabel.stringValue = "识别失败"
                    self.statusLabel.textColor = Palette.danger
                }
            }
        }
    }

    @objc private func copyTapped() {
        guard let result, !result.text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(result.text, forType: .string)
        statusLabel.stringValue = "已复制 \(result.text.count) 个字符到剪贴板"
        statusLabel.textColor = Palette.success
        flash(copyButton)
    }

    @objc private func saveTapped() {
        guard let result, !result.text.isEmpty else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "Glint-OCR.txt"
        savePanel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        savePanel.beginSheetModal(for: panel) { [weak self] response in
            guard let self, response == .OK, let url = savePanel.url else { return }
            do {
                try result.text.write(to: url, atomically: true, encoding: .utf8)
                self.statusLabel.stringValue = "已保存到 \(url.lastPathComponent)"
                self.statusLabel.textColor = Palette.teal
            } catch {
                self.statusLabel.stringValue = "保存失败：\(error.localizedDescription)"
                self.statusLabel.textColor = Palette.danger
            }
        }
    }

    @objc private func closeTapped() {
        close()
    }

    func close() {
        guard !closed else { return }
        closed = true
        panel.orderOut(nil)
        onClose?()
    }

    func windowWillClose(_ notification: Notification) {
        close()
    }
}

private final class OCRPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class OCRSurfaceView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 20, yRadius: 20)
        let gradient = NSGradient(colors: [NSColor(hex: 0x131B25), NSColor(hex: 0x0E141B)])!
        gradient.draw(in: path, angle: -80)
        Palette.strokeStrong.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

private final class OCRTextBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor(hex: 0x0A0E13).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
    }
}
