import AppKit

final class RecordingHUDController: NSObject {
    private let panel: RecordingHUDPanel
    private let timerLabel = NSTextField(labelWithString: "00:00")
    private let targetLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "正在录制")
    private let stopButton = GlintButton(title: "停止", style: .danger)
    private let pauseButton = GlintButton(title: "暂停", style: .secondary)
    private let collapseButton = GlintIconButton(symbol: "chevron.right", size: 12)
    private let dot = PulseDotView()
    private let spinner = NSProgressIndicator()

    private let compactPanel: CompactHUDPanel
    private var compactTimerLabel: NSTextField!
    private var compactDot: PulseDotView!
    private var compactStateLabel: NSTextField!

    private var timer: Timer?
    private var startedAt: Date?
    private var pausedAt: Date?
    private var accumulatedPause: TimeInterval = 0
    private var isPaused = false
    private var isSaving = false
    private(set) var isCollapsed = false
    var onStop: (() -> Void)?
    var onPause: (() -> Void)?

    override init() {
        panel = RecordingHUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: 570, height: 68),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        compactPanel = CompactHUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: 142, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
        configureCompactPanel()
        buildUI()
        buildCompactUI()
    }

    deinit {
        timer?.invalidate()
    }

    func show(startedAt: Date, target: String) {
        self.startedAt = startedAt
        targetLabel.stringValue = target
        targetLabel.toolTip = target
        timerLabel.stringValue = "00:00"
        isPaused = false
        isSaving = false
        accumulatedPause = 0
        pausedAt = nil
        statusLabel.stringValue = "正在录制"
        statusLabel.textColor = Palette.danger
        pauseButton.title = "暂停"
        pauseButton.setSymbol("pause.fill")
        pauseButton.isHidden = false
        collapseButton.isHidden = false
        stopButton.isHidden = false
        spinner.isHidden = true
        dot.alphaValue = 1
        dot.layer?.backgroundColor = Palette.danger.cgColor
        dot.start()
        startTimer()
        showFullPanel(animated: true)
        updateElapsed()
    }

    func setPaused(_ paused: Bool) {
        guard !isSaving else { return }
        if paused {
            guard !isPaused else { return }
            isPaused = true
            pausedAt = Date()
            statusLabel.stringValue = "已暂停"
            statusLabel.textColor = Palette.accent
            pauseButton.title = "继续"
            pauseButton.setSymbol("play.fill")
            dot.stop()
            dot.alphaValue = 0.45
            dot.layer?.backgroundColor = Palette.accent.cgColor
            compactDot.stop()
            compactDot.alphaValue = 0.45
            compactDot.layer?.backgroundColor = Palette.accent.cgColor
            compactStateLabel.stringValue = "已暂停"
            compactStateLabel.textColor = Palette.accent
        } else {
            guard isPaused else { return }
            if let pausedAt {
                accumulatedPause += Date().timeIntervalSince(pausedAt)
            }
            isPaused = false
            pausedAt = nil
            statusLabel.stringValue = "正在录制"
            statusLabel.textColor = Palette.danger
            pauseButton.title = "暂停"
            pauseButton.setSymbol("pause.fill")
            dot.layer?.backgroundColor = Palette.danger.cgColor
            dot.alphaValue = 1
            dot.start()
            compactDot.layer?.backgroundColor = Palette.danger.cgColor
            compactDot.alphaValue = 1
            compactDot.start()
            compactStateLabel.stringValue = "REC"
            compactStateLabel.textColor = Palette.danger
        }
        updateElapsed()
    }

    func setSaving() {
        isSaving = true
        if !isPaused { pausedAt = Date() }
        isPaused = true
        timer?.invalidate()
        timer = nil
        pauseButton.isEnabled = false
        pauseButton.alphaValue = 0.45
        collapseButton.isHidden = true
        dot.stop()
        dot.alphaValue = 0.4
        dot.layer?.backgroundColor = Palette.danger.cgColor
        statusLabel.stringValue = "正在保存"
        statusLabel.textColor = Palette.textSecondary
        stopButton.isEnabled = false
        stopButton.alphaValue = 0.55
        stopButton.title = "保存中"
        stopButton.setSymbol("hourglass")
        spinner.isHidden = false
        spinner.startAnimation(nil)
        expand()
        updateElapsed()
    }

    func setFailed() {
        isSaving = false
        timer?.invalidate()
        timer = nil
        dot.stop()
        dot.alphaValue = 0.4
        dot.layer?.backgroundColor = Palette.danger.cgColor
        statusLabel.stringValue = "录制中断"
        statusLabel.textColor = Palette.danger
        stopButton.isHidden = true
        pauseButton.isHidden = true
        collapseButton.isHidden = true
        spinner.isHidden = true
        spinner.stopAnimation(nil)
        expand()
    }

    func hide(after delay: TimeInterval = 0.2) {
        timer?.invalidate()
        timer = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
            self.compactPanel.orderOut(nil)
        }
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
        panel.contentMinSize = NSSize(width: 570, height: 68)
        panel.contentMaxSize = NSSize(width: 570, height: 68)
    }

    private func configureCompactPanel() {
        compactPanel.isOpaque = false
        compactPanel.backgroundColor = .clear
        compactPanel.hasShadow = true
        compactPanel.level = .floating
        compactPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        compactPanel.hidesOnDeactivate = false
        compactPanel.isReleasedWhenClosed = false
        compactPanel.becomesKeyOnlyIfNeeded = true
        compactPanel.contentMinSize = NSSize(width: 142, height: 36)
        compactPanel.contentMaxSize = NSSize(width: 142, height: 36)
    }

    private func buildUI() {
        let root = RecordingSurfaceView(frame: NSRect(x: 0, y: 0, width: 570, height: 68))
        root.wantsLayer = true
        root.layer?.cornerRadius = 16
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = root

        dot.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(dot)

        statusLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .bold)
        statusLabel.textColor = Palette.danger
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(statusLabel)

        timerLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 17, weight: .medium)
        timerLabel.textColor = Palette.text
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(timerLabel)

        targetLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        targetLabel.textColor = Palette.textSecondary
        targetLabel.lineBreakMode = .byTruncatingTail
        targetLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(targetLabel)

        pauseButton.target = self
        pauseButton.action = #selector(pauseTapped)
        pauseButton.setSymbol("pause.fill")
        root.addSubview(pauseButton)

        collapseButton.target = self
        collapseButton.action = #selector(collapseTapped)
        collapseButton.toolTip = "收起控制条"
        root.addSubview(collapseButton)

        stopButton.target = self
        stopButton.action = #selector(stopTapped)
        stopButton.setSymbol("stop.fill")
        root.addSubview(stopButton)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isHidden = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(spinner)

        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            dot.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10),

            statusLabel.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 10),
            statusLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 15),

            timerLabel.leadingAnchor.constraint(equalTo: statusLabel.leadingAnchor),
            timerLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 2),

            stopButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            stopButton.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            stopButton.widthAnchor.constraint(equalToConstant: 82),
            stopButton.heightAnchor.constraint(equalToConstant: 32),

            collapseButton.trailingAnchor.constraint(equalTo: stopButton.leadingAnchor, constant: -6),
            collapseButton.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            collapseButton.widthAnchor.constraint(equalToConstant: 28),
            collapseButton.heightAnchor.constraint(equalToConstant: 28),

            pauseButton.trailingAnchor.constraint(equalTo: collapseButton.leadingAnchor, constant: -6),
            pauseButton.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            pauseButton.widthAnchor.constraint(equalToConstant: 76),
            pauseButton.heightAnchor.constraint(equalToConstant: 32),

            targetLabel.leadingAnchor.constraint(equalTo: timerLabel.trailingAnchor, constant: 14),
            targetLabel.trailingAnchor.constraint(lessThanOrEqualTo: pauseButton.leadingAnchor, constant: -14),
            targetLabel.centerYAnchor.constraint(equalTo: root.centerYAnchor),

            spinner.trailingAnchor.constraint(equalTo: stopButton.leadingAnchor, constant: -10),
            spinner.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])
    }

    private func buildCompactUI() {
        let root = CompactSurfaceView(frame: NSRect(x: 0, y: 0, width: 142, height: 36))
        root.wantsLayer = true
        root.layer?.cornerRadius = 18
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true
        root.translatesAutoresizingMaskIntoConstraints = false
        root.onActivate = { [weak self] in self?.expand() }
        compactPanel.contentView = root

        compactDot = PulseDotView()
        compactDot.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(compactDot)

        compactStateLabel = NSTextField(labelWithString: "REC")
        compactStateLabel.font = NSFont.systemFont(ofSize: 8.5, weight: .bold)
        compactStateLabel.textColor = Palette.danger
        compactStateLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(compactStateLabel)

        compactTimerLabel = NSTextField(labelWithString: "00:00")
        compactTimerLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        compactTimerLabel.textColor = Palette.text
        compactTimerLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(compactTimerLabel)

        let expandIcon = makeSymbol("chevron.left", size: 9, weight: .semibold, color: Palette.textTertiary)
        root.addSubview(expandIcon)

        NSLayoutConstraint.activate([
            compactDot.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            compactDot.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            compactDot.widthAnchor.constraint(equalToConstant: 8),
            compactDot.heightAnchor.constraint(equalToConstant: 8),

            compactStateLabel.leadingAnchor.constraint(equalTo: compactDot.trailingAnchor, constant: 6),
            compactStateLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 7),

            compactTimerLabel.leadingAnchor.constraint(equalTo: compactStateLabel.leadingAnchor),
            compactTimerLabel.topAnchor.constraint(equalTo: compactStateLabel.bottomAnchor, constant: -1),

            expandIcon.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            expandIcon.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            expandIcon.widthAnchor.constraint(equalToConstant: 8),
            expandIcon.heightAnchor.constraint(equalToConstant: 12),
        ])
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.updateElapsed()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        updateElapsed()
    }

    private func updateElapsed() {
        guard let startedAt else { return }
        let end = pausedAt ?? Date()
        let active = max(0, end.timeIntervalSince(startedAt) - accumulatedPause)
        let seconds = Int(active)
        let text = String(format: "%02d:%02d", seconds / 60, seconds % 60)
        timerLabel.stringValue = text
        compactTimerLabel.stringValue = text
    }

    private func showFullPanel(animated: Bool) {
        isCollapsed = false
        compactPanel.orderOut(nil)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.midX - panel.frame.width / 2,
                y: visible.maxY - panel.frame.height - 14
            ))
        }
        panel.alphaValue = animated ? 0 : 1
        panel.orderFrontRegardless()
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
    }

    func collapse() {
        guard !isSaving else { return }
        isCollapsed = true
        panel.orderOut(nil)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            compactPanel.setFrameOrigin(NSPoint(
                x: visible.maxX - compactPanel.frame.width - 16,
                y: visible.maxY - compactPanel.frame.height - 14
            ))
        }
        compactPanel.alphaValue = 0
        compactPanel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            compactPanel.animator().alphaValue = 1
        }
    }

    func expand() {
        guard isCollapsed || isSaving else { return }
        showFullPanel(animated: true)
    }

    @objc private func pauseTapped() {
        onPause?()
    }

    @objc private func collapseTapped() {
        collapse()
    }

    @objc private func stopTapped() {
        onStop?()
    }
}

private final class RecordingHUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class CompactHUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class CompactSurfaceView: NSView {
    var onActivate: (() -> Void)?
    private var hovered = false
    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18)
        let gradient = NSGradient(colors: [NSColor(hex: 0x1B222C, alpha: 0.98), NSColor(hex: 0x11171F, alpha: 0.98)])!
        gradient.draw(in: path, angle: -80)
        (hovered ? Palette.strokeStrong : Palette.stroke).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    @objc private func clicked() {
        onActivate?()
    }
}

private final class RecordingSurfaceView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16)
        let gradient = NSGradient(colors: [NSColor(hex: 0x1B222C, alpha: 0.98), NSColor(hex: 0x11171F, alpha: 0.98)])!
        gradient.draw(in: path, angle: -80)
        Palette.strokeStrong.setStroke()
        path.lineWidth = 1
        path.stroke()

        // Left red accent bar.
        let bar = NSBezierPath(roundedRect: NSRect(x: 0, y: 15, width: 3, height: bounds.height - 30), xRadius: 1.5, yRadius: 1.5)
        Palette.danger.withAlphaComponent(0.8).setFill()
        bar.fill()
    }
}

private final class PulseDotView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Palette.danger.cgColor
        layer?.cornerRadius = 5
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { start() }
    }

    func start() {
        layer?.removeAllAnimations()
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.28
        pulse.duration = 0.65
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(pulse, forKey: "pulse")
    }

    func stop() {
        layer?.removeAllAnimations()
        layer?.opacity = 1
    }
}
