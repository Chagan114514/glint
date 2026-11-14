import AppKit

enum RecordChoice {
    case display
    case area
    case window
}

final class RecordChooserController: NSObject, NSWindowDelegate {
    private let panel: RecordChooserPanel
    private let onChoose: (RecordChoice?, AudioSource) -> Void
    private let audioPopup = NSPopUpButton()
    private var keyMonitor: Any?
    private var finished = false

    init(onChoose: @escaping (RecordChoice?, AudioSource) -> Void) {
        self.onChoose = onChoose
        panel = RecordChooserPanel(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 412),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
        buildUI()
        panel.setContentSize(NSSize(width: 430, height: 412))
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
            context.duration = 0.18
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
        panel.contentMinSize = NSSize(width: 430, height: 412)
        panel.contentMaxSize = NSSize(width: 430, height: 412)
    }

    func windowWillClose(_ notification: Notification) {
        cancel()
    }

    private func buildUI() {
        let root = RecordChooserSurface(frame: NSRect(x: 0, y: 0, width: 430, height: 412))
        root.wantsLayer = true
        root.layer?.cornerRadius = 20
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = root
        root.widthAnchor.constraint(equalToConstant: 430).isActive = true
        root.heightAnchor.constraint(equalToConstant: 412).isActive = true

        let recDot = NSView()
        recDot.wantsLayer = true
        recDot.layer?.backgroundColor = Palette.danger.cgColor
        recDot.layer?.cornerRadius = 4
        recDot.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(recDot)

        let title = makeLabel("开始录屏", size: 20, weight: .semibold, color: Palette.text)
        root.addSubview(title)
        let subtitle = makeLabel("选择录制范围，点击即可开始", size: 11, weight: .regular, color: Palette.textSecondary)
        root.addSubview(subtitle)

        let close = GlintIconButton(symbol: "xmark", size: 12, target: self, action: #selector(closeTapped))
        root.addSubview(close)

        let display = RecordChoiceRow(
            title: "全屏",
            subtitle: "录制鼠标所在的整个显示器",
            symbol: "display",
            accent: Palette.accent
        )
        display.onClick = { [weak self] in self?.choose(.display) }

        let area = RecordChoiceRow(
            title: "区域",
            subtitle: "拖拽框选任意一块屏幕区域",
            symbol: "viewfinder",
            accent: Palette.teal
        )
        area.onClick = { [weak self] in self?.choose(.area) }

        let window = RecordChoiceRow(
            title: "窗口",
            subtitle: "选择一个应用窗口单独录制",
            symbol: "macwindow",
            accent: NSColor(hex: 0xB8A4FF)
        )
        window.onClick = { [weak self] in self?.choose(.window) }

        let rows = NSStackView(views: [display, area, window])
        rows.orientation = .vertical
        rows.spacing = 8
        rows.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(rows)

        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = Palette.stroke.cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(divider)

        let audioTitle = makeLabel("声音来源", size: 11.5, weight: .medium, color: Palette.text)
        root.addSubview(audioTitle)
        let audioDetail = makeLabel("系统声音、麦克风，或两者同时录制", size: 9.5, weight: .regular, color: Palette.textTertiary)
        root.addSubview(audioDetail)

        audioPopup.removeAllItems()
        for source in AudioSource.allCases {
            audioPopup.addItem(withTitle: source.title)
        }
        if let index = AudioSource.allCases.firstIndex(of: Prefs.audioSource) {
            audioPopup.selectItem(at: index)
        }
        audioPopup.controlSize = .small
        audioPopup.font = NSFont.systemFont(ofSize: 10.5)
        audioPopup.target = self
        audioPopup.action = #selector(audioChanged)
        audioPopup.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(audioPopup)

        let footer = makeLabel("开始后，按 ⌃⌥4 或点击悬浮条上的「停止」结束录制", size: 9.5, weight: .regular, color: Palette.textTertiary, alignment: .center)
        root.addSubview(footer)

        NSLayoutConstraint.activate([
            recDot.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            recDot.topAnchor.constraint(equalTo: root.topAnchor, constant: 26),
            recDot.widthAnchor.constraint(equalToConstant: 8),
            recDot.heightAnchor.constraint(equalToConstant: 8),

            title.leadingAnchor.constraint(equalTo: recDot.trailingAnchor, constant: 10),
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 19),

            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 1),

            close.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            close.topAnchor.constraint(equalTo: root.topAnchor, constant: 17),
            close.widthAnchor.constraint(equalToConstant: 28),
            close.heightAnchor.constraint(equalToConstant: 28),

            rows.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            rows.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            rows.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 16),

            display.heightAnchor.constraint(equalToConstant: 64),
            area.heightAnchor.constraint(equalToConstant: 64),
            window.heightAnchor.constraint(equalToConstant: 64),

            divider.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            divider.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            divider.topAnchor.constraint(equalTo: rows.bottomAnchor, constant: 16),
            divider.heightAnchor.constraint(equalToConstant: 1),

            audioTitle.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            audioTitle.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 16),

            audioDetail.leadingAnchor.constraint(equalTo: audioTitle.leadingAnchor),
            audioDetail.topAnchor.constraint(equalTo: audioTitle.bottomAnchor, constant: 2),

            audioPopup.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            audioPopup.centerYAnchor.constraint(equalTo: audioTitle.centerYAnchor, constant: 7),
            audioPopup.widthAnchor.constraint(equalToConstant: 190),

            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
        ])
    }

    private func choose(_ choice: RecordChoice) {
        guard !finished else { return }
        finished = true
        close()
        let audio = Prefs.audioSource
        let callback = onChoose
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            callback(choice, audio)
        }
    }

    private func close() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        panel.orderOut(nil)
    }

    private func cancel() {
        guard !finished else { return }
        finished = true
        close()
        onChoose(nil, Prefs.audioSource)
    }

    @objc private func audioChanged() {
        let index = audioPopup.indexOfSelectedItem
        guard index >= 0, index < AudioSource.allCases.count else { return }
        Prefs.audioSource = AudioSource.allCases[index]
    }

    @objc private func closeTapped() {
        cancel()
    }
}

private final class RecordChooserPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class RecordChooserSurface: NSView {
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

private final class RecordChoiceRow: NSControl {
    private let title: String
    private let subtitle: String
    private let symbol: String
    private let accent: NSColor
    private var hovered = false
    private var pressed = false
    private var tracking: NSTrackingArea?
    var onClick: (() -> Void)?

    init(title: String, subtitle: String, symbol: String, accent: NSColor) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.accent = accent
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
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

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }

    @objc private func clicked() {
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        let fill = pressed ? accent.withAlphaComponent(0.16) : (hovered ? Palette.whiteLine : Palette.surface)
        fill.setFill()
        path.fill()
        (hovered ? accent.withAlphaComponent(0.35) : Palette.stroke).setStroke()
        path.lineWidth = 1
        path.stroke()

        let tileRect = NSRect(x: 12, y: bounds.midY - 19, width: 38, height: 38)
        let tile = NSBezierPath(roundedRect: tileRect, xRadius: 10, yRadius: 10)
        accent.withAlphaComponent(0.13).setFill()
        tile.fill()

        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 17, weight: .semibold))?
            .tinted(with: accent) {
            image.draw(in: NSRect(x: tileRect.midX - 10, y: tileRect.midY - 10, width: 20, height: 20), from: .zero, operation: .sourceOver, fraction: 1)
        }

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: Palette.text,
        ]
        (title as NSString).draw(at: NSPoint(x: 62, y: bounds.midY + 2), withAttributes: titleAttrs)

        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: Palette.textSecondary,
        ]
        (subtitle as NSString).draw(at: NSPoint(x: 62, y: bounds.midY - 16), withAttributes: subtitleAttrs)

        let chevron = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))?
            .tinted(with: hovered ? accent : Palette.textTertiary)
        chevron?.draw(in: NSRect(x: bounds.maxX - 26, y: bounds.midY - 7, width: 8, height: 14), from: .zero, operation: .sourceOver, fraction: 1)
    }
}
