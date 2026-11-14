import AppKit
import ScreenCaptureKit

final class WindowPickerController: NSObject, NSWindowDelegate {
    enum Purpose {
        case screenshot
        case recording

        var title: String {
            switch self {
            case .screenshot: return "选择要截取的窗口"
            case .recording: return "选择要录制的窗口"
            }
        }

        var subtitle: String {
            switch self {
            case .screenshot: return "点击任意窗口，立即截取它的完整画面"
            case .recording: return "点击任意窗口，开始录制这个窗口"
            }
        }

        var accent: NSColor {
            switch self {
            case .screenshot: return Palette.accent
            case .recording: return Palette.danger
            }
        }
    }

    private let purpose: Purpose
    private let onFinish: (SCWindow?) -> Void
    private let panel: WindowPickerPanel
    private let scrollView = NSScrollView()
    private let documentView = FlippedView()
    private let loadingStack = NSStackView()
    private let contentHost = NSView()
    private var cards: [WindowCardView] = []
    private var keyMonitor: Any?
    private var finished = false
    private var windows: [SCWindow] = []

    init(purpose: Purpose, onFinish: @escaping (SCWindow?) -> Void) {
        self.purpose = purpose
        self.onFinish = onFinish
        self.panel = WindowPickerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
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
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {
                self.finish(nil)
                return nil
            }
            return event
        }
        loadWindows()
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

    func windowWillClose(_ notification: Notification) {
        finish(nil)
    }

    private func buildUI() {
        let root = PanelSurfaceView(frame: NSRect(x: 0, y: 0, width: 900, height: 640))
        root.wantsLayer = true
        root.layer?.cornerRadius = 22
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = root

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(header)

        let logo = LogoView(frame: .zero)
        logo.size = 38
        header.addSubview(logo)

        let title = makeLabel(purpose.title, size: 20, weight: .semibold, color: Palette.text)
        header.addSubview(title)

        let subtitle = makeLabel(purpose.subtitle, size: 11.5, weight: .regular, color: Palette.textSecondary)
        header.addSubview(subtitle)

        let close = GlintIconButton(symbol: "xmark", size: 13, target: self, action: #selector(closeTapped))
        header.addSubview(close)

        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = Palette.stroke.cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(divider)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = documentView
        scrollView.contentView.drawsBackground = false
        root.addSubview(scrollView)

        contentHost.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(contentHost)

        loadingStack.orientation = .vertical
        loadingStack.alignment = .centerX
        loadingStack.spacing = 12
        loadingStack.translatesAutoresizingMaskIntoConstraints = false
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.startAnimation(nil)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.widthAnchor.constraint(equalToConstant: 22).isActive = true
        spinner.heightAnchor.constraint(equalToConstant: 22).isActive = true
        let loadingLabel = makeLabel("正在读取可见窗口…", size: 12, weight: .medium, color: Palette.textSecondary, alignment: .center)
        loadingStack.addArrangedSubview(spinner)
        loadingStack.addArrangedSubview(loadingLabel)
        contentHost.addSubview(loadingStack)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 34),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -34),
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            header.heightAnchor.constraint(equalToConstant: 48),

            logo.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            logo.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            logo.widthAnchor.constraint(equalToConstant: 38),
            logo.heightAnchor.constraint(equalToConstant: 38),

            title.leadingAnchor.constraint(equalTo: logo.trailingAnchor, constant: 13),
            title.topAnchor.constraint(equalTo: header.topAnchor, constant: 3),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),

            close.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: 4),
            close.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 30),
            close.heightAnchor.constraint(equalToConstant: 30),

            divider.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 34),
            divider.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -34),
            divider.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            divider.heightAnchor.constraint(equalToConstant: 1),

            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 40),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -40),
            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 18),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -34),

            contentHost.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentHost.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentHost.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentHost.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),

            loadingStack.centerXAnchor.constraint(equalTo: contentHost.centerXAnchor),
            loadingStack.centerYAnchor.constraint(equalTo: contentHost.centerYAnchor),
        ])
    }

    private func loadWindows() {
        Task { @MainActor in
            do {
                let fetched = try await CaptureEngine.shared.loadWindows()
                guard !finished else { return }
                windows = fetched
                if fetched.isEmpty {
                    showMessage(
                        symbol: "macwindow.badge.plus",
                        title: "没有找到可选择的窗口",
                        detail: "请先打开一个应用窗口，再重新尝试。"
                    )
                    return
                }
                buildCards(for: fetched)
                for (index, window) in fetched.enumerated() {
                    guard !finished, index < cards.count else { return }
                    if let image = await CaptureEngine.shared.windowThumbnail(window) {
                        guard !finished, index < cards.count else { return }
                        cards[index].setThumbnail(image)
                    }
                }
            } catch {
                guard !finished else { return }
                showMessage(
                    symbol: "exclamationmark.triangle",
                    title: "无法读取窗口列表",
                    detail: error.localizedDescription
                )
            }
        }
    }

    private func buildCards(for windows: [SCWindow]) {
        loadingStack.isHidden = true
        clearDocument()
        contentHost.isHidden = true

        let cardWidth: CGFloat = 264
        let cardHeight: CGFloat = 196
        let gap: CGFloat = 16
        let columns = 3
        let rows = Int(ceil(Double(windows.count) / Double(columns)))
        let docWidth = CGFloat(columns) * cardWidth + CGFloat(columns - 1) * gap
        let docHeight = max(1, CGFloat(rows) * cardHeight + CGFloat(max(0, rows - 1)) * gap)
        documentView.frame = NSRect(x: 0, y: 0, width: docWidth, height: docHeight)

        for (index, window) in windows.enumerated() {
            let row = index / columns
            let column = index % columns
            let card = WindowCardView(frame: NSRect(
                x: CGFloat(column) * (cardWidth + gap),
                y: CGFloat(row) * (cardHeight + gap),
                width: cardWidth,
                height: cardHeight
            ), accent: purpose.accent)
            card.configure(with: window)
            card.onActivate = { [weak self] in
                self?.finish(window)
            }
            documentView.addSubview(card)
            cards.append(card)
        }
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func showMessage(symbol: String, title: String, detail: String) {
        loadingStack.isHidden = true
        clearDocument()
        contentHost.isHidden = true
        documentView.frame = NSRect(x: 0, y: 0, width: 820, height: 430)

        let icon = makeSymbol(symbol, size: 30, weight: .regular, color: Palette.textTertiary)
        icon.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(icon)
        let titleLabel = makeLabel(title, size: 15, weight: .semibold, color: Palette.text, alignment: .center)
        let detailLabel = makeLabel(detail, size: 12, weight: .regular, color: Palette.textSecondary, alignment: .center, lines: 2)
        detailLabel.maximumNumberOfLines = 2
        documentView.addSubview(titleLabel)
        documentView.addSubview(detailLabel)

        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: documentView.centerXAnchor),
            icon.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 150),
            icon.widthAnchor.constraint(equalToConstant: 38),
            icon.heightAnchor.constraint(equalToConstant: 38),
            titleLabel.centerXAnchor.constraint(equalTo: documentView.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 14),
            detailLabel.centerXAnchor.constraint(equalTo: documentView.centerXAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            detailLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 460),
        ])
    }

    private func clearDocument() {
        for subview in documentView.subviews {
            subview.removeFromSuperview()
        }
        cards.removeAll()
    }

    private func finish(_ window: SCWindow?) {
        guard !finished else { return }
        finished = true
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        panel.orderOut(nil)
        let callback = onFinish
        let result = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            callback(result)
        }
    }

    @objc private func closeTapped() {
        finish(nil)
    }
}

private final class WindowPickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class PanelSurfaceView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 22, yRadius: 22)
        let gradient = NSGradient(colors: [NSColor(hex: 0x111821), NSColor(hex: 0x0D131A)])!
        gradient.draw(in: path, angle: -80)
        Palette.whiteLine.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

private final class WindowCardView: NSControl {
    private let accent: NSColor
    private let thumbnailContainer = NSView()
    private let imageView = NSImageView()
    private let placeholderIcon = NSImageView()
    private let spinner = NSProgressIndicator()
    private let appIconView = NSImageView()
    private let appLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private var tracking: NSTrackingArea?
    private var hovered = false
    private var pressed = false
    var onActivate: (() -> Void)?

    init(frame frameRect: NSRect, accent: NSColor) {
        self.accent = accent
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = true
        layer?.cornerRadius = 13
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        thumbnailContainer.wantsLayer = true
        thumbnailContainer.layer?.backgroundColor = NSColor(hex: 0x080C11).cgColor
        thumbnailContainer.layer?.cornerRadius = 9
        thumbnailContainer.layer?.cornerCurve = .continuous
        thumbnailContainer.layer?.masksToBounds = true
        thumbnailContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thumbnailContainer)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailContainer.addSubview(imageView)

        placeholderIcon.imageScaling = .scaleProportionallyUpOrDown
        placeholderIcon.alphaValue = 0.65
        placeholderIcon.translatesAutoresizingMaskIntoConstraints = false
        thumbnailContainer.addSubview(placeholderIcon)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        thumbnailContainer.addSubview(spinner)

        appIconView.imageScaling = .scaleProportionallyUpOrDown
        appIconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(appIconView)

        appLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        appLabel.textColor = Palette.textSecondary
        appLabel.lineBreakMode = .byTruncatingTail
        appLabel.usesSingleLineMode = true
        appLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(appLabel)

        titleLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        titleLabel.textColor = Palette.text
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.usesSingleLineMode = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            thumbnailContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            thumbnailContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            thumbnailContainer.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            thumbnailContainer.heightAnchor.constraint(equalToConstant: 136),

            imageView.leadingAnchor.constraint(equalTo: thumbnailContainer.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: thumbnailContainer.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: thumbnailContainer.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: thumbnailContainer.bottomAnchor),

            placeholderIcon.centerXAnchor.constraint(equalTo: thumbnailContainer.centerXAnchor),
            placeholderIcon.centerYAnchor.constraint(equalTo: thumbnailContainer.centerYAnchor),
            placeholderIcon.widthAnchor.constraint(equalToConstant: 40),
            placeholderIcon.heightAnchor.constraint(equalToConstant: 40),

            spinner.centerXAnchor.constraint(equalTo: thumbnailContainer.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: thumbnailContainer.centerYAnchor),

            appIconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            appIconView.topAnchor.constraint(equalTo: thumbnailContainer.bottomAnchor, constant: 9),
            appIconView.widthAnchor.constraint(equalToConstant: 14),
            appIconView.heightAnchor.constraint(equalToConstant: 14),

            appLabel.leadingAnchor.constraint(equalTo: appIconView.trailingAnchor, constant: 6),
            appLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            appLabel.centerYAnchor.constraint(equalTo: appIconView.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            titleLabel.topAnchor.constraint(equalTo: appIconView.bottomAnchor, constant: 2),
        ])

        spinner.startAnimation(nil)
        let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) { nil }

    func configure(with window: SCWindow) {
        let app = window.owningApplication
        appLabel.stringValue = app?.applicationName ?? "窗口"
        titleLabel.stringValue = window.title ?? ""
        toolTip = "\(app?.applicationName ?? "")\n\(window.title ?? "")"

        var icon: NSImage?
        if let pid = app?.processID {
            icon = NSRunningApplication(processIdentifier: pid)?.icon
        }
        if icon == nil, let bundleID = app?.bundleIdentifier {
            let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path
            if let path { icon = NSWorkspace.shared.icon(forFile: path) }
        }
        appIconView.image = icon
        placeholderIcon.image = icon
    }

    func setThumbnail(_ image: NSImage) {
        imageView.image = image
        placeholderIcon.isHidden = true
        spinner.stopAnimation(nil)
        spinner.isHidden = true
    }

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

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }

    @objc private func clicked() {
        onActivate?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 13, yRadius: 13)
        let fill: NSColor
        if pressed {
            fill = accent.withAlphaComponent(0.14)
        } else if hovered {
            fill = Palette.surfaceHover
        } else {
            fill = Palette.surface
        }
        fill.setFill()
        path.fill()

        if hovered || pressed {
            accent.withAlphaComponent(0.45).setStroke()
        } else {
            Palette.stroke.setStroke()
        }
        path.lineWidth = 1
        path.stroke()
    }
}
