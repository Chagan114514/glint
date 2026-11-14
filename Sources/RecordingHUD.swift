import AppKit

final class RecordingHUDController: NSObject {
    private let panel: RecordingHUDPanel
    private let timerLabel = NSTextField(labelWithString: "00:00")
    private let targetLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "正在录制")
    private let stopButton = GlintButton(title: "停止", style: .danger)
    private let dot = PulseDotView()
    private let spinner = NSProgressIndicator()
    private var timer: Timer?
    private var startedAt: Date?
    private var pausedAt: Date?
    var onStop: (() -> Void)?

    override init() {
        panel = RecordingHUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 66),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
        buildUI()
    }

    deinit {
        timer?.invalidate()
    }

    func show(startedAt: Date, target: String) {
        self.startedAt = startedAt
        targetLabel.stringValue = target
        targetLabel.toolTip = target
        timerLabel.stringValue = "00:00"
        startTimer()

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
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func setSaving() {
        timer?.invalidate()
        timer = nil
        pausedAt = Date()
        dot.stop()
        dot.alphaValue = 0.4
        statusLabel.stringValue = "正在保存"
        statusLabel.textColor = Palette.textSecondary
        stopButton.isEnabled = false
        stopButton.alphaValue = 0.55
        stopButton.title = "保存中"
        stopButton.setSymbol("hourglass")
        spinner.isHidden = false
        spinner.startAnimation(nil)
        updateElapsed()
    }

    func setFailed() {
        timer?.invalidate()
        timer = nil
        dot.stop()
        dot.alphaValue = 0.4
        dot.layer?.backgroundColor = Palette.danger.cgColor
        statusLabel.stringValue = "录制中断"
        statusLabel.textColor = Palette.danger
        stopButton.isHidden = true
        spinner.isHidden = true
        spinner.stopAnimation(nil)
    }

    func hide(after delay: TimeInterval = 0.2) {
        timer?.invalidate()
        timer = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
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
    }

    private func buildUI() {
        let root = RecordingSurfaceView(frame: NSRect(x: 0, y: 0, width: 450, height: 66))
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

            targetLabel.leadingAnchor.constraint(equalTo: timerLabel.trailingAnchor, constant: 14),
            targetLabel.trailingAnchor.constraint(lessThanOrEqualTo: stopButton.leadingAnchor, constant: -16),
            targetLabel.centerYAnchor.constraint(equalTo: root.centerYAnchor),

            stopButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            stopButton.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            stopButton.widthAnchor.constraint(equalToConstant: 82),
            stopButton.heightAnchor.constraint(equalToConstant: 32),

            spinner.trailingAnchor.constraint(equalTo: stopButton.leadingAnchor, constant: -10),
            spinner.centerYAnchor.constraint(equalTo: root.centerYAnchor),
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
        let seconds = max(0, Int(end.timeIntervalSince(startedAt)))
        timerLabel.stringValue = String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    @objc private func stopTapped() {
        onStop?()
    }
}

private final class RecordingHUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
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
