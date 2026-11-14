import AppKit

final class ScrollingCaptureController {
    struct Selection {
        let screen: NSScreen
        let rect: CGRect
    }

    private let selection: Selection
    private let stitcher: ScrollStitcher
    private let hud = ScrollingHUDController()
    private var active = false
    private var finishing = false
    private var cancelled = false
    private var finalized = false
    private var delivered = false
    private var loopError: String?
    private var frames = 0
    var onFinish: ((CapturedImage?, String?) -> Void)?

    init(selection: Selection, scale: CGFloat) {
        self.selection = selection
        self.stitcher = ScrollStitcher(scale: scale)
    }

    func begin() {
        active = true
        hud.onFinish = { [weak self] in self?.finish() }
        hud.onCancel = { [weak self] in self?.cancel() }
        hud.show()

        // Give the previously active app focus back so the user's scroll
        // gestures go to the page being captured, not to Glint.
        NSApp.deactivate()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            while self.active {
                do {
                    let captured = try await CaptureEngine.shared.captureArea(
                        screen: self.selection.screen,
                        localRect: self.selection.rect
                    )
                    guard self.active else { break }
                    frames += 1
                    let result = self.stitcher.append(captured.cgImage)
                    self.hud.update(frames: self.frames, height: self.stitcher.totalHeight, result: result)
                    if self.stitcher.totalHeight >= ScrollStitcher.maxHeight {
                        self.finish()
                        break
                    }
                } catch {
                    self.loopError = error.localizedDescription
                    self.active = false
                    self.hud.updateError(error.localizedDescription)
                    break
                }
                try? await Task.sleep(nanoseconds: 320_000_000)
            }
            if self.finishing {
                self.finalize()
            } else if !self.cancelled {
                if let loopError = self.loopError {
                    self.deliver(nil, loopError)
                } else if !self.active {
                    self.deliver(nil, "没有捕获到滚动内容")
                }
            }
        }
    }

    private func finish() {
        guard !finishing, !cancelled else { return }
        finishing = true
        active = false
        hud.setStitching()
    }

    private func cancel() {
        guard !finishing, !cancelled else { return }
        cancelled = true
        active = false
        deliver(nil, nil)
    }

    private func finalize() {
        guard !finalized else { return }
        finalized = true
        guard let image = stitcher.makeImage(),
              stitcher.totalHeight > stitcher.frameHeight + 12 else {
            deliver(nil, "没有检测到滚动内容，请慢一点滚动后再试。")
            return
        }
        let captured = CapturedImage(
            cgImage: image,
            scale: stitcher.scale,
            label: "滚动截图 · \(frames) 帧"
        )
        deliver(captured, nil)
    }

    private func deliver(_ captured: CapturedImage?, _ error: String?) {
        guard !delivered else { return }
        delivered = true
        hud.hide()
        onFinish?(captured, error)
    }
}

// MARK: - Stitcher

final class ScrollStitcher {
    enum AppendResult {
        case first
        case skipped
        case appended(overlap: Int, added: Int)
        case noOverlap
        case limitReached
    }

    static let maxHeight = 20_000

    let scale: CGFloat
    private(set) var totalHeight = 0
    private(set) var frameWidth = 0
    private(set) var frameHeight = 0

    private var stitched: [UInt8] = []
    private var previous: [UInt8]?
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    init(scale: CGFloat) {
        self.scale = scale
    }

    func append(_ image: CGImage) -> AppendResult {
        guard let frame = Self.rgbaBytes(from: image, colorSpace: colorSpace) else { return .noOverlap }
        if frameWidth == 0 {
            frameWidth = frame.width
            frameHeight = frame.height
        }
        guard frame.width == frameWidth, frame.height == frameHeight else { return .noOverlap }
        guard frame.height > 8 else { return .noOverlap }

        if totalHeight == 0 {
            stitched = frame.bytes
            totalHeight = frame.height
            previous = frame.bytes
            return .first
        }

        if totalHeight >= Self.maxHeight {
            return .limitReached
        }

        guard let prev = previous else { return .noOverlap }
        if prev == frame.bytes {
            return .skipped
        }
        let overlap: Int
        if let found = Self.findOverlap(previous: prev, next: frame.bytes, width: frame.width, height: frame.height) {
            overlap = found
        } else {
            overlap = 0
        }

        if overlap >= frame.height {
            return .skipped
        }

        if overlap < 8 {
            let remaining = Self.maxHeight - totalHeight
            guard remaining > 0 else { return .limitReached }
            let copyRows = min(frame.height, remaining)
            stitched.append(contentsOf: frame.bytes.prefix(copyRows * frame.width * 4))
            totalHeight += copyRows
            previous = frame.bytes
            return .noOverlap
        }

        let added = frame.height - overlap
        let remaining = Self.maxHeight - totalHeight
        let copyRows = min(added, remaining)
        let start = overlap * frame.width * 4
        let end = start + copyRows * frame.width * 4
        stitched.append(contentsOf: frame.bytes[start..<min(end, frame.bytes.count)])
        totalHeight += copyRows
        previous = frame.bytes
        return .appended(overlap: overlap, added: copyRows)
    }

    func makeImage() -> CGImage? {
        guard totalHeight > 0, frameWidth > 0 else { return nil }
        guard let provider = CGDataProvider(data: Data(stitched) as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        return CGImage(
            width: frameWidth,
            height: totalHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: frameWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    private struct Frame {
        let bytes: [UInt8]
        let width: Int
        let height: Int
    }

    private static func rgbaBytes(from image: CGImage, colorSpace: CGColorSpace) -> Frame? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Frame(bytes: bytes, width: width, height: height)
    }

    private static func findOverlap(previous: [UInt8], next: [UInt8], width: Int, height: Int) -> Int? {
        let bytesPerRow = width * 4
        let maxOverlap = min(height - 1, max(1, Int(Double(height) * 0.90)))
        let minOverlap = min(36, height / 3)
        guard maxOverlap >= minOverlap else { return nil }

        // Sample across the full width rather than a few columns. This keeps
        // repeated rows of text or UI chrome from producing false matches.
        let xStep = max(1, width / 96)
        var bestOverlap = 0
        var bestError = Double.greatestFiniteMagnitude

        for overlap in stride(from: maxOverlap, through: minOverlap, by: -1) {
            var total = 0
            var samples = 0
            let rowSamples = min(18, max(4, overlap / 10))
            let rowStep = max(1, overlap / rowSamples)
            var y = 0
            while y < overlap {
                let prevRow = height - overlap + y
                let pBase = prevRow * bytesPerRow
                let nBase = y * bytesPerRow
                var x = 0
                while x < width {
                    let pi = pBase + x * 4
                    let ni = nBase + x * 4
                    total += abs(Int(previous[pi]) - Int(next[ni]))
                    total += abs(Int(previous[pi + 1]) - Int(next[ni + 1]))
                    total += abs(Int(previous[pi + 2]) - Int(next[ni + 2]))
                    samples += 3
                    x += xStep
                }
                y += rowStep
            }
            guard samples > 0 else { continue }
            let error = Double(total) / Double(samples)
            if error < bestError {
                bestError = error
                bestOverlap = overlap
            }
        }
        return bestError < 9.0 ? bestOverlap : nil
    }
}

// MARK: - HUD

final class ScrollingHUDController {
    private let panel: ScrollingHUDPanel
    private let statusLabel = NSTextField(labelWithString: "缓慢向下滚动页面")
    private let detailLabel = NSTextField(labelWithString: "正在等待画面…")
    private let spinner = NSProgressIndicator()
    private let finishButton = GlintButton(title: "完成", style: .primary)
    private let cancelButton = GlintButton(title: "取消", style: .ghost)
    private let dot = NSView()
    var onFinish: (() -> Void)?
    var onCancel: (() -> Void)?

    init() {
        panel = ScrollingHUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 70),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configurePanel()
        buildUI()
    }

    func show() {
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.midX - panel.frame.width / 2,
                y: visible.maxY - panel.frame.height - 14
            ))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }
    }

    func update(frames: Int, height: Int, result: ScrollStitcher.AppendResult) {
        detailLabel.stringValue = "已捕获 \(frames) 帧 · 拼接高度 \(height) px"
        detailLabel.textColor = Palette.textSecondary
        if case .noOverlap = result {
            detailLabel.stringValue = "已捕获 \(frames) 帧 · 未找到重叠，请慢一点滚动"
            detailLabel.textColor = Palette.accent
        }
    }

    func updateError(_ message: String) {
        detailLabel.stringValue = message
        detailLabel.textColor = Palette.danger
    }

    func setStitching() {
        statusLabel.stringValue = "正在拼接长图…"
        detailLabel.stringValue = "请稍候"
        detailLabel.textColor = Palette.textSecondary
        finishButton.isEnabled = false
        finishButton.alphaValue = 0.5
        cancelButton.isHidden = true
        spinner.isHidden = false
        spinner.startAnimation(nil)
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentMinSize = NSSize(width: 430, height: 70)
        panel.contentMaxSize = NSSize(width: 430, height: 70)
    }

    private func buildUI() {
        let root = ScrollingSurfaceView(frame: NSRect(x: 0, y: 0, width: 430, height: 70))
        root.wantsLayer = true
        root.layer?.cornerRadius = 16
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = root

        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor(hex: 0x62A8FF).cgColor
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(dot)

        statusLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        statusLabel.textColor = NSColor(hex: 0x62A8FF)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(statusLabel)

        detailLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        detailLabel.textColor = Palette.textSecondary
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(detailLabel)

        finishButton.target = self
        finishButton.action = #selector(finishTapped)
        finishButton.setSymbol("checkmark")
        root.addSubview(finishButton)

        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)
        cancelButton.setSymbol("xmark")
        root.addSubview(cancelButton)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isHidden = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(spinner)

        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            dot.topAnchor.constraint(equalTo: root.topAnchor, constant: 17),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),

            statusLabel.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 9),
            statusLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 13),

            detailLabel.leadingAnchor.constraint(equalTo: statusLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 4),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: finishButton.leadingAnchor, constant: -12),

            finishButton.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -8),
            finishButton.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            finishButton.widthAnchor.constraint(equalToConstant: 78),
            finishButton.heightAnchor.constraint(equalToConstant: 30),

            cancelButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            cancelButton.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 62),
            cancelButton.heightAnchor.constraint(equalToConstant: 30),

            spinner.trailingAnchor.constraint(equalTo: finishButton.leadingAnchor, constant: -10),
            spinner.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])
    }

    @objc private func finishTapped() { onFinish?() }
    @objc private func cancelTapped() { onCancel?() }
}

private final class ScrollingHUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class ScrollingSurfaceView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16)
        let gradient = NSGradient(colors: [NSColor(hex: 0x17222E, alpha: 0.98), NSColor(hex: 0x101721, alpha: 0.98)])!
        gradient.draw(in: path, angle: -80)
        Palette.strokeStrong.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
