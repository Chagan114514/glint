import AppKit

final class DisplayPickerController: NSObject, NSWindowDelegate {
    enum Purpose {
        case screenshot
        case recording
    }

    private let panel: DisplayPickerPanel
    private let onChoose: (NSScreen?) -> Void
    private let purpose: Purpose
    private var keyMonitor: Any?
    private var finished = false

    init(purpose: Purpose, onChoose: @escaping (NSScreen?) -> Void) {
        self.purpose = purpose
        self.onChoose = onChoose
        let screens = NSScreen.screens
        let height = 118 + CGFloat(max(1, screens.count)) * 70
        panel = DisplayPickerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: height),
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
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.cancel()
                return nil
            }
            return event
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
        panel.delegate = self
    }

    private func buildUI() {
        let root = DisplayPickerSurface(frame: NSRect(x: 0, y: 0, width: 540, height: panel.frame.height))
        root.wantsLayer = true
        root.layer?.cornerRadius = 20
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = root
        root.widthAnchor.constraint(equalToConstant: 540).isActive = true
        root.heightAnchor.constraint(equalToConstant: panel.frame.height).isActive = true

        let icon = makeSymbol("display", size: 15, weight: .semibold, color: Palette.accent)
        root.addSubview(icon)
        let title = makeLabel("选择显示器", size: 19, weight: .semibold, color: Palette.text)
        root.addSubview(title)
        let subtitle = makeLabel(
            purpose == .screenshot ? "选择要截取的完整屏幕" : "选择要录制声音与画面的屏幕",
            size: 10.5,
            weight: .regular,
            color: Palette.textSecondary
        )
        root.addSubview(subtitle)
        let close = GlintIconButton(symbol: "xmark", size: 12, target: self, action: #selector(cancelTapped))
        root.addSubview(close)

        let list = NSStackView()
        list.orientation = .vertical
        list.spacing = 8
        list.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(list)

        let mouseScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
        for (index, screen) in NSScreen.screens.enumerated() {
            let row = DisplayRowView(
                screen: screen,
                index: index + 1,
                isMain: screen == NSScreen.main,
                isUnderMouse: screen == mouseScreen,
                action: { [weak self] in self?.choose(screen) }
            )
            list.addArrangedSubview(row)
            row.heightAnchor.constraint(equalToConstant: 62).isActive = true
        }

        let cancel = GlintButton(title: "取消", style: .secondary)
        cancel.target = self
        cancel.action = #selector(cancelTapped)
        root.addSubview(cancel)

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
            list.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 18),

            cancel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),
            cancel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            cancel.widthAnchor.constraint(equalToConstant: 80),
            cancel.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    private func choose(_ screen: NSScreen) {
        guard !finished else { return }
        finished = true
        stopMonitor()
        panel.orderOut(nil)
        onChoose(screen)
    }

    @objc private func cancelTapped() { cancel() }

    private func cancel() {
        guard !finished else { return }
        finished = true
        stopMonitor()
        panel.orderOut(nil)
        onChoose(nil)
    }

    private func stopMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    func windowWillClose(_ notification: Notification) { cancel() }
}

private final class DisplayPickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class DisplayPickerSurface: NSView {
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

private final class DisplayRowView: NSView {
    private let screen: NSScreen
    private let action: () -> Void
    private var hovered = false
    private var tracking: NSTrackingArea?

    init(screen: NSScreen, index: Int, isMain: Bool, isUnderMouse: Bool, action: @escaping () -> Void) {
        self.screen = screen
        self.action = action
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Palette.surface.cgColor
        layer?.borderColor = (isUnderMouse ? Palette.accent.withAlphaComponent(0.5) : Palette.stroke).cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 13
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        toolTip = "点击选择 \(screen.glintName)"

        let icon = makeSymbol("display", size: 16, weight: .regular, color: isUnderMouse ? Palette.accent : Palette.textSecondary)
        addSubview(icon)

        let name = makeLabel(screen.glintName, size: 12.5, weight: .medium, color: Palette.text)
        addSubview(name)
        let detail = makeLabel(
            "\(Int(screen.frame.width)) × \(Int(screen.frame.height)) · \(screen.backingScaleFactor == 2 ? "Retina" : "1x")",
            size: 10,
            weight: .regular,
            color: Palette.textTertiary
        )
        addSubview(detail)

        let badge = makeLabel(
            isUnderMouse ? "鼠标所在" : (isMain ? "主显示器" : "显示器 \(index)"),
            size: 9,
            weight: .semibold,
            color: isUnderMouse ? Palette.accent : Palette.textSecondary,
            alignment: .right
        )
        addSubview(badge)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            name.topAnchor.constraint(equalTo: topAnchor, constant: 13),
            name.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -12),
            detail.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            detail.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 3),
            badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            badge.centerYAnchor.constraint(equalTo: name.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        layer?.backgroundColor = Palette.surfaceHover.cgColor
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        layer?.backgroundColor = Palette.surface.cgColor
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        action()
    }
}
