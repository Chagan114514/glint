import AppKit

final class ShortcutSettingsController: NSObject, NSWindowDelegate {
    private let panel: ShortcutPanel
    private var rows: [HotKeyAction: ShortcutRowView] = [:]
    private var keyMonitor: Any?
    private var recordingAction: HotKeyAction?
    private var closed = false

    override init() {
        panel = ShortcutPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 500),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
        buildUI()
    }

    func show() {
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.midX - panel.frame.width / 2,
                y: visible.midY - panel.frame.height / 2
            ))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        refreshRows()
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
        panel.delegate = self
        panel.contentMinSize = NSSize(width: 560, height: 500)
        panel.contentMaxSize = NSSize(width: 560, height: 500)
    }

    private func buildUI() {
        let root = ShortcutSurface(frame: NSRect(x: 0, y: 0, width: 560, height: 500))
        root.wantsLayer = true
        root.layer?.cornerRadius = 20
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = root
        root.widthAnchor.constraint(equalToConstant: 560).isActive = true
        root.heightAnchor.constraint(equalToConstant: 500).isActive = true

        let icon = makeSymbol("keyboard", size: 15, weight: .semibold, color: Palette.accent)
        root.addSubview(icon)
        let title = makeLabel("快捷键", size: 19, weight: .semibold, color: Palette.text)
        root.addSubview(title)
        let subtitle = makeLabel("点击右侧快捷键后，按下新的组合键", size: 10.5, weight: .regular, color: Palette.textSecondary)
        root.addSubview(subtitle)
        let close = GlintIconButton(symbol: "xmark", size: 12, target: self, action: #selector(closeTapped))
        root.addSubview(close)

        let list = NSStackView()
        list.orientation = .vertical
        list.spacing = 6
        list.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(list)

        for action in HotKeyAction.allCases {
            let row = ShortcutRowView(action: action) { [weak self] in self?.beginRecording(action) }
            rows[action] = row
            list.addArrangedSubview(row)
            row.heightAnchor.constraint(equalToConstant: 52).isActive = true
        }

        let reset = GlintButton(title: "恢复默认", style: .secondary)
        reset.target = self
        reset.action = #selector(resetTapped)
        root.addSubview(reset)
        let done = GlintButton(title: "完成", style: .primary)
        done.target = self
        done.action = #selector(closeTapped)
        root.addSubview(done)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            icon.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 1),
            close.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            close.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            close.widthAnchor.constraint(equalToConstant: 28),
            close.heightAnchor.constraint(equalToConstant: 28),

            list.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
            list.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),
            list.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 16),

            reset.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
            reset.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            reset.widthAnchor.constraint(equalToConstant: 92),
            reset.heightAnchor.constraint(equalToConstant: 28),
            done.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),
            done.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            done.widthAnchor.constraint(equalToConstant: 80),
            done.heightAnchor.constraint(equalToConstant: 28),
        ])
        refreshRows()
    }

    private func beginRecording(_ action: HotKeyAction) {
        if recordingAction != nil {
            stopRecording(cancelled: true)
        } else {
            stopMonitor()
        }
        // While recording, Carbon hot keys must not swallow the new combo.
        HotKeyManager.shared.suspend()
        recordingAction = action
        rows[action]?.setRecording(true)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {
                self.stopRecording(cancelled: true)
                return nil
            }
            guard let combo = HotKeyCombo.from(event: event) else {
                NSSound.beep()
                return nil
            }
            if let duplicate = HotKeyAction.allCases.first(where: { $0 != action && HotKeyStore.combo(for: $0) == combo }) {
                self.showDuplicate(duplicate)
                self.stopRecording(cancelled: true)
                return nil
            }
            HotKeyStore.set(combo, for: action)
            self.stopRecording(cancelled: false)
            self.refreshRows()
            return nil
        }
    }

    private func stopRecording(cancelled: Bool) {
        if let recordingAction { rows[recordingAction]?.setRecording(false) }
        recordingAction = nil
        stopMonitor()
        HotKeyManager.shared.resume()
        if cancelled { refreshRows() }
    }

    private func stopMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func refreshRows() {
        for action in HotKeyAction.allCases {
            rows[action]?.setCombo(HotKeyStore.combo(for: action))
        }
    }

    private func showDuplicate(_ action: HotKeyAction) {
        let alert = NSAlert()
        alert.messageText = "快捷键已被使用"
        alert.informativeText = "\(action.title) 已经使用了这个组合键，请换一个。"
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func resetTapped() {
        HotKeyStore.reset()
        refreshRows()
    }

    @objc private func closeTapped() { close() }

    private func close() {
        guard !closed else { return }
        closed = true
        stopMonitor()
        HotKeyManager.shared.resume()
        panel.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) { close() }
}

private final class ShortcutPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class ShortcutSurface: NSView {
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

private final class ShortcutRowView: NSView {
    private let action: HotKeyAction
    private let button = GlintButton(title: "", style: .secondary)
    private let titleLabel: NSTextField
    private let detailLabel: NSTextField
    private let onRecord: () -> Void
    private var recording = false

    init(action: HotKeyAction, onRecord: @escaping () -> Void) {
        self.action = action
        self.onRecord = onRecord
        titleLabel = makeLabel(action.title, size: 12, weight: .medium, color: Palette.text)
        detailLabel = makeLabel("", size: 9.5, weight: .regular, color: Palette.textTertiary)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Palette.surface.cgColor
        layer?.borderColor = Palette.stroke.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(detailLabel)
        button.target = self
        button.action = #selector(recordTapped)
        button.widthAnchor.constraint(equalToConstant: 128).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        addSubview(button)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func setCombo(_ combo: HotKeyCombo) {
        recording = false
        button.title = combo.display
        detailLabel.stringValue = "点击后按下新组合键"
    }

    func setRecording(_ value: Bool) {
        recording = value
        button.title = value ? "按下快捷键…" : HotKeyStore.combo(for: action).display
        detailLabel.stringValue = value ? "按 Esc 取消" : "点击后按下新组合键"
    }

    @objc private func recordTapped() { onRecord() }
}
