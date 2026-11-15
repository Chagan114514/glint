import AppKit

final class DashboardWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let headerView = DashboardHeaderView()
    private let permissionBanner = PermissionBannerView()
    private let recentContainer = GlintCardView()
    private let recentStack = NSStackView()
    private var recentHeightConstraint: NSLayoutConstraint!
    private var contentStack: NSStackView!
    private var actionCards: [HotKeyAction: ActionCardView] = [:]
    private var heightUpdateScheduled = false

    var onArea: (() -> Void)?
    var onWindow: (() -> Void)?
    var onFullScreen: (() -> Void)?
    var onRecord: (() -> Void)?
    var onOpenRecent: ((CaptureItem) -> Void)?
    var onRequestPermission: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onScrollCapture: (() -> Void)?
    var onOpenImageFolder: (() -> Void)?
    var onOpenVideoFolder: (() -> Void)?

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()
        configureWindow()
        buildUI()
        NotificationCenter.default.addObserver(self, selector: #selector(libraryChanged), name: CaptureLibrary.libraryChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(libraryChanged), name: CaptureLibrary.settingsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(hotKeysChanged), name: HotKeyStore.changed, object: nil)
        refreshPermission()
        reloadRecent()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func show() {
        refreshPermission()
        reloadRecent()
        if !window.isVisible {
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func refreshPermission() {
        let granted = ScreenPermission.isGranted
        headerView.setPermission(granted: granted)
        permissionBanner.isHidden = granted
        if !granted {
            permissionBanner.startPulse()
        }
        scheduleWindowHeightUpdate(animated: true)
    }

    func refreshRecentAndLibrary() {
        reloadRecent()
    }

    private func refreshShortcuts() {
        for (action, card) in actionCards {
            card.updateShortcut(HotKeyStore.label(for: action))
        }
        headerView.refreshShortcutBadge()
        reloadRecent()
    }

    private func configureWindow() {
        window.title = "Glint"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = Palette.background
        window.isOpaque = true
        window.hasShadow = true
        window.minSize = NSSize(width: 900, height: 680)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.collectionBehavior = [.fullScreenPrimary]
    }

    private func buildUI() {
        let root = DashboardBackgroundView()
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = root

        let stack = NSStackView()
        contentStack = stack
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        stack.addArrangedSubview(headerView)
        stack.addArrangedSubview(permissionBanner)
        stack.addArrangedSubview(makeQuickHeader())
        stack.addArrangedSubview(makeActionRow())
        stack.addArrangedSubview(makeRecentHeader())
        stack.addArrangedSubview(recentContainer)
        stack.addArrangedSubview(makeFooter())

        stack.setCustomSpacing(14, after: headerView)
        stack.setCustomSpacing(18, after: permissionBanner)
        stack.setCustomSpacing(8, after: stack.arrangedSubviews[2])
        stack.setCustomSpacing(24, after: stack.arrangedSubviews[3])
        stack.setCustomSpacing(10, after: stack.arrangedSubviews[4])
        stack.setCustomSpacing(18, after: recentContainer)

        for view in [headerView, permissionBanner, stack.arrangedSubviews[2], stack.arrangedSubviews[3], stack.arrangedSubviews[4], recentContainer, stack.arrangedSubviews[6]] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 48),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -24),

            headerView.heightAnchor.constraint(equalToConstant: 64),
            permissionBanner.heightAnchor.constraint(equalToConstant: 50),
            stack.arrangedSubviews[2].heightAnchor.constraint(equalToConstant: 20),
            stack.arrangedSubviews[3].heightAnchor.constraint(equalToConstant: 150),
            stack.arrangedSubviews[4].heightAnchor.constraint(equalToConstant: 24),
            stack.arrangedSubviews[6].heightAnchor.constraint(equalToConstant: 16),
        ])

        configureRecentContainer()

        headerView.onPermissionTapped = { [weak self] in
            self?.onRequestPermission?()
        }
        headerView.onSettingsTapped = { [weak self] in
            self?.onOpenSettings?()
        }
        permissionBanner.onAuthorize = { [weak self] in
            self?.onRequestPermission?()
        }
        scheduleWindowHeightUpdate(animated: false)
    }

    private func makeQuickHeader() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        let title = makeLabel("快速开始", size: 13, weight: .semibold, color: Palette.text.withAlphaComponent(0.88))
        view.addSubview(title)
        let hint = makeLabel("全局快捷键 · 可在设置中自定义", size: 10.5, weight: .medium, color: Palette.textTertiary)
        view.addSubview(hint)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            title.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            hint.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hint.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        return view
    }

    private func makeActionRow() -> NSView {
        let area = ActionCardView(
            title: "区域截图",
            subtitle: "拖拽框选任意区域",
            symbol: "viewfinder",
            shortcut: HotKeyStore.label(for: .area),
            accent: Palette.accent
        )
        area.onClick = { [weak self] in self?.onArea?() }

        let windowCard = ActionCardView(
            title: "窗口截图",
            subtitle: "选择一个应用窗口",
            symbol: "macwindow",
            shortcut: HotKeyStore.label(for: .window),
            accent: Palette.teal
        )
        windowCard.onClick = { [weak self] in self?.onWindow?() }

        let full = ActionCardView(
            title: "全屏截图",
            subtitle: "选择显示器截取",
            symbol: "display",
            shortcut: HotKeyStore.label(for: .fullScreen),
            accent: NSColor(hex: 0xB8A4FF)
        )
        full.onClick = { [weak self] in self?.onFullScreen?() }

        let scroll = ActionCardView(
            title: "滚动截图",
            subtitle: "自动拼接长页面",
            symbol: "scroll",
            shortcut: HotKeyStore.label(for: .scroll),
            accent: NSColor(hex: 0x62A8FF)
        )
        scroll.onClick = { [weak self] in self?.onScrollCapture?() }

        let record = ActionCardView(
            title: "屏幕录制",
            subtitle: "全屏、区域或窗口",
            symbol: "record.circle",
            shortcut: HotKeyStore.label(for: .record),
            accent: Palette.danger
        )
        record.onClick = { [weak self] in self?.onRecord?() }

        actionCards[.area] = area
        actionCards[.window] = windowCard
        actionCards[.fullScreen] = full
        actionCards[.scroll] = scroll
        actionCards[.record] = record

        let row = NSStackView(views: [area, windowCard, full, scroll, record])
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func makeRecentHeader() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        let title = makeLabel("最近", size: 13, weight: .semibold, color: Palette.text.withAlphaComponent(0.88))
        view.addSubview(title)

        let imageButton = FolderLinkView(title: "图片文件夹")
        imageButton.onClick = { [weak self] in self?.openImages() }
        view.addSubview(imageButton)
        let videoButton = FolderLinkView(title: "录屏文件夹")
        videoButton.onClick = { [weak self] in self?.openVideos() }
        view.addSubview(videoButton)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            title.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            videoButton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            imageButton.trailingAnchor.constraint(equalTo: videoButton.leadingAnchor, constant: -14),
            imageButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        return view
    }

    private func makeFooter() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        let left = makeLabel("支持自定义截图 / 录屏保存目录 · 全部数据仅保留在本机", size: 9.5, weight: .regular, color: Palette.textTertiary)
        view.addSubview(left)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? UpdateChecker.currentVersion
        let right = makeLabel("Glint \(version)", size: 9.5, weight: .medium, color: Palette.textTertiary)
        view.addSubview(right)
        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            left.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            right.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            right.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            right.leadingAnchor.constraint(greaterThanOrEqualTo: left.trailingAnchor, constant: 12),
        ])
        return view
    }

    private func configureRecentContainer() {
        recentContainer.fillColor = Palette.surface
        recentContainer.borderColor = Palette.stroke
        recentContainer.cornerRadius = 14
        recentContainer.translatesAutoresizingMaskIntoConstraints = false

        recentStack.orientation = .vertical
        recentStack.alignment = .leading
        recentStack.spacing = 0
        recentStack.translatesAutoresizingMaskIntoConstraints = false
        recentContainer.addSubview(recentStack)

        recentHeightConstraint = recentContainer.heightAnchor.constraint(equalToConstant: 128)
        recentHeightConstraint.isActive = true

        NSLayoutConstraint.activate([
            recentStack.leadingAnchor.constraint(equalTo: recentContainer.leadingAnchor, constant: 4),
            recentStack.trailingAnchor.constraint(equalTo: recentContainer.trailingAnchor, constant: -4),
            recentStack.topAnchor.constraint(equalTo: recentContainer.topAnchor, constant: 4),
            recentStack.bottomAnchor.constraint(equalTo: recentContainer.bottomAnchor, constant: -4),
        ])
    }

    private func reloadRecent() {
        let items = CaptureLibrary.shared.recent(limit: 4)
        clearRecentStack()

        if items.isEmpty {
            let empty = RecentEmptyView()
            empty.onStart = { [weak self] in self?.onArea?() }
            empty.translatesAutoresizingMaskIntoConstraints = false
            recentStack.addArrangedSubview(empty)
            empty.widthAnchor.constraint(equalTo: recentStack.widthAnchor).isActive = true
            empty.heightAnchor.constraint(equalToConstant: 192).isActive = true
            recentHeightConstraint.constant = 200
            scheduleWindowHeightUpdate(animated: true)
            return
        }

        for (index, item) in items.enumerated() {
            let row = RecentRowView()
            row.configure(item)
            row.onOpen = { [weak self] in self?.onOpenRecent?(item) }
            row.translatesAutoresizingMaskIntoConstraints = false
            recentStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: recentStack.widthAnchor).isActive = true
            row.heightAnchor.constraint(equalToConstant: 56).isActive = true

            if index < items.count - 1 {
                let separator = NSView()
                separator.wantsLayer = true
                separator.layer?.backgroundColor = Palette.stroke.cgColor
                separator.translatesAutoresizingMaskIntoConstraints = false
                recentStack.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalTo: recentStack.widthAnchor).isActive = true
                separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
            }
        }

        let separators = max(0, items.count - 1)
        recentHeightConstraint.constant = CGFloat(items.count * 56 + separators) + 8
        scheduleWindowHeightUpdate(animated: true)
    }

    private func scheduleWindowHeightUpdate(animated: Bool) {
        guard !heightUpdateScheduled else { return }
        heightUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.heightUpdateScheduled = false
            self.updateWindowHeight(animated: animated)
        }
    }

    private func updateWindowHeight(animated: Bool) {
        guard let screen = window.screen ?? NSScreen.main, let contentStack else { return }
        window.contentView?.layoutSubtreeIfNeeded()
        let stackHeight = contentStack.fittingSize.height
        guard stackHeight > 1 else { return }
        var target = 48 + stackHeight + 24
        target = max(600, min(target, min(820, screen.visibleFrame.height - 40)))
        let frame = window.frame
        guard abs(frame.height - target) > 2 else { return }
        let top = frame.maxY
        var newFrame = frame
        newFrame.size.height = target
        newFrame.origin.y = top - target
        window.setFrame(newFrame, display: true, animate: animated)
    }

    private func clearRecentStack() {
        for view in recentStack.arrangedSubviews {
            recentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    @objc private func libraryChanged() {
        reloadRecent()
    }

    @objc private func hotKeysChanged() {
        refreshShortcuts()
    }

    @objc private func openImages() {
        onOpenImageFolder?()
    }

    @objc private func openVideos() {
        onOpenVideoFolder?()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refreshPermission()
    }
}

// MARK: - Header

private final class DashboardHeaderView: NSView {
    private let logo = LogoView()
    private let title = NSTextField(labelWithString: "Glint")
    private let subtitle = NSTextField(labelWithString: "截屏 · 录屏 · 一气呵成")
    private let permissionPill = PermissionPill()
    private let shortcutBadge = ShortcutBadge()
    private let settingsButton = GlintIconButton(symbol: "gearshape", size: 13)
    var onPermissionTapped: (() -> Void)?
    var onSettingsTapped: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        logo.size = 52
        addSubview(logo)

        title.font = NSFont.systemFont(ofSize: 31, weight: .bold)
        title.textColor = Palette.text
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)

        subtitle.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        subtitle.textColor = Palette.textSecondary
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitle)

        permissionPill.onTap = { [weak self] in self?.onPermissionTapped?() }
        addSubview(permissionPill)
        addSubview(shortcutBadge)

        settingsButton.target = self
        settingsButton.action = #selector(settingsTapped)
        settingsButton.toolTip = "设置"
        addSubview(settingsButton)

        NSLayoutConstraint.activate([
            logo.leadingAnchor.constraint(equalTo: leadingAnchor),
            logo.centerYAnchor.constraint(equalTo: centerYAnchor),
            logo.widthAnchor.constraint(equalToConstant: 52),
            logo.heightAnchor.constraint(equalToConstant: 52),

            title.leadingAnchor.constraint(equalTo: logo.trailingAnchor, constant: 15),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 2),

            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor, constant: 1),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: -2),

            settingsButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            settingsButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: 28),
            settingsButton.heightAnchor.constraint(equalToConstant: 28),

            shortcutBadge.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -8),
            shortcutBadge.centerYAnchor.constraint(equalTo: centerYAnchor),
            shortcutBadge.widthAnchor.constraint(equalToConstant: 104),
            shortcutBadge.heightAnchor.constraint(equalToConstant: 28),

            permissionPill.trailingAnchor.constraint(equalTo: shortcutBadge.leadingAnchor, constant: -10),
            permissionPill.centerYAnchor.constraint(equalTo: centerYAnchor),
            permissionPill.widthAnchor.constraint(equalToConstant: 110),
            permissionPill.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func setPermission(granted: Bool) {
        permissionPill.granted = granted
    }

    func refreshShortcutBadge() {
        shortcutBadge.needsDisplay = true
    }

    @objc private func settingsTapped() {
        onSettingsTapped?()
    }
}

private final class PermissionPill: NSControl {
    fileprivate var granted = false
    private var hovered = false
    private var tracking: NSTrackingArea?
    var onTap: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) { nil }
    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }

    @objc private func clicked() {
        onTap?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
        let tint = granted ? Palette.success : Palette.accent
        tint.withAlphaComponent(hovered ? 0.16 : 0.10).setFill()
        path.fill()
        tint.withAlphaComponent(0.25).setStroke()
        path.lineWidth = 1
        path.stroke()

        let dotRect = NSRect(x: 12, y: bounds.midY - 3, width: 6, height: 6)
        tint.setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        let text = granted ? "权限已开启" : "需要屏幕权限"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: tint,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: dotRect.maxX + 6, y: bounds.midY - size.height / 2), withAttributes: attrs)
    }
}

private final class ShortcutBadge: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
        Palette.surface.setFill()
        path.fill()
        Palette.stroke.setStroke()
        path.lineWidth = 1
        path.stroke()

        let icon = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))?
            .tinted(with: Palette.textTertiary)
        icon?.draw(in: NSRect(x: 12, y: bounds.midY - 6, width: 15, height: 12), from: .zero, operation: .sourceOver, fraction: 1)

        let allDefault = HotKeyAction.allCases.allSatisfy { HotKeyStore.combo(for: $0) == $0.defaultCombo }
        let text = allDefault ? "⌃⌥ 1–6" : "已自定义"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold),
            .foregroundColor: Palette.textSecondary,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: 33, y: bounds.midY - size.height / 2), withAttributes: attrs)
    }
}

// MARK: - Action cards

private final class ActionCardView: NSControl {
    private let title: String
    private let subtitle: String
    private let symbol: String
    private var shortcut: String
    private let accent: NSColor
    private var hovered = false
    private var pressed = false
    private var tracking: NSTrackingArea?
    var onClick: (() -> Void)?

    init(title: String, subtitle: String, symbol: String, shortcut: String, accent: NSColor) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.shortcut = shortcut
        self.accent = accent
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        setAccessibilityRole(.button)
        setAccessibilityLabel("\(title)，\(subtitle)")
        let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) { nil }

    func updateShortcut(_ value: String) {
        guard value != shortcut else { return }
        shortcut = value
        needsDisplay = true
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

    @objc private func clicked() {
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16)

        let gradient = NSGradient(colors: [
            hovered ? Palette.surfaceHover : Palette.surface,
            hovered ? NSColor(hex: 0x18222D) : NSColor(hex: 0x121A23),
        ])!
        gradient.draw(in: path, angle: -85)

        accent.withAlphaComponent(hovered ? 0.40 : 0.13).setStroke()
        path.lineWidth = 1
        path.stroke()

        if pressed {
            accent.withAlphaComponent(0.10).setFill()
            path.fill()
        }

        // Icon tile.
        let tileRect = NSRect(x: 18, y: bounds.maxY - 58, width: 40, height: 40)
        let tile = NSBezierPath(roundedRect: tileRect, xRadius: 12, yRadius: 12)
        accent.withAlphaComponent(hovered ? 0.20 : 0.13).setFill()
        tile.fill()
        accent.withAlphaComponent(0.18).setStroke()
        tile.lineWidth = 1
        tile.stroke()

        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 18, weight: .semibold))?
            .tinted(with: accent) {
            let imageSize = NSSize(width: 19, height: 19)
            image.draw(in: NSRect(x: tileRect.midX - imageSize.width / 2, y: tileRect.midY - imageSize.height / 2, width: imageSize.width, height: imageSize.height), from: .zero, operation: .sourceOver, fraction: 1)
        }

        // Shortcut pill.
        let shortcutAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold),
            .foregroundColor: Palette.textTertiary,
        ]
        let shortcutSize = (shortcut as NSString).size(withAttributes: shortcutAttrs)
        let pillWidth = shortcutSize.width + 14
        let pillRect = NSRect(x: bounds.maxX - 18 - pillWidth, y: bounds.maxY - 40, width: pillWidth, height: 20)
        let pill = NSBezierPath(roundedRect: pillRect, xRadius: 7, yRadius: 7)
        NSColor.white.withAlphaComponent(0.045).setFill()
        pill.fill()
        (shortcut as NSString).draw(at: NSPoint(x: pillRect.minX + 7, y: pillRect.midY - shortcutSize.height / 2), withAttributes: shortcutAttrs)

        // Text.
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: Palette.text,
        ]
        (title as NSString).draw(at: NSPoint(x: 18, y: 56), withAttributes: titleAttrs)

        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10.5, weight: .regular),
            .foregroundColor: Palette.textSecondary,
        ]
        (subtitle as NSString).draw(at: NSPoint(x: 18, y: 36), withAttributes: subtitleAttrs)
    }
}

private final class FolderLinkView: NSControl {
    private let text: String
    private var hovered = false
    private var tracking: NSTrackingArea?
    var onClick: (() -> Void)?

    init(title: String) {
        text = title
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        let size = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 10.5, weight: .medium)])
        return NSSize(width: size.width + 2, height: 16)
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

    @objc private func clicked() {
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10.5, weight: .medium),
            .foregroundColor: hovered ? Palette.textSecondary : Palette.textTertiary,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: 0, y: bounds.midY - size.height / 2), withAttributes: attrs)
        if hovered {
            NSColor.white.withAlphaComponent(0.20).setStroke()
            let underline = NSBezierPath()
            underline.move(to: NSPoint(x: 0, y: bounds.midY - size.height / 2 - 1))
            underline.line(to: NSPoint(x: size.width, y: bounds.midY - size.height / 2 - 1))
            underline.lineWidth = 1
            underline.stroke()
        }
    }
}

// MARK: - Recent

private final class RecentRowView: NSControl {
    private let thumbnail = NSImageView()
    private let placeholder = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let kindLabel = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    private var hovered = false
    private var tracking: NSTrackingArea?
    private var item: CaptureItem?
    var onOpen: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.imageAlignment = .alignCenter
        thumbnail.wantsLayer = true
        thumbnail.layer?.backgroundColor = NSColor(hex: 0x0A0E13).cgColor
        thumbnail.layer?.cornerRadius = 7
        thumbnail.layer?.cornerCurve = .continuous
        thumbnail.layer?.masksToBounds = true
        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thumbnail)

        placeholder.imageScaling = .scaleProportionallyUpOrDown
        placeholder.contentTintColor = Palette.textTertiary
        placeholder.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholder)

        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = Palette.text
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.usesSingleLineMode = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        metaLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        metaLabel.textColor = Palette.textTertiary
        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(metaLabel)

        kindLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
        kindLabel.alignment = .center
        kindLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(kindLabel)

        chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
        chevron.contentTintColor = Palette.textTertiary
        chevron.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chevron)

        NSLayoutConstraint.activate([
            thumbnail.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            thumbnail.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnail.widthAnchor.constraint(equalToConstant: 76),
            thumbnail.heightAnchor.constraint(equalToConstant: 42),

            placeholder.centerXAnchor.constraint(equalTo: thumbnail.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: thumbnail.centerYAnchor),
            placeholder.widthAnchor.constraint(equalToConstant: 18),
            placeholder.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: kindLabel.leadingAnchor, constant: -10),

            metaLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            metaLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),

            kindLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -12),
            kindLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            kindLabel.widthAnchor.constraint(equalToConstant: 38),
            kindLabel.heightAnchor.constraint(equalToConstant: 18),

            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 10),
            chevron.heightAnchor.constraint(equalToConstant: 14),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) { nil }

    func configure(_ item: CaptureItem) {
        self.item = item
        titleLabel.stringValue = item.displayName
        metaLabel.stringValue = "\(item.subtitle)  ·  \(item.kind == .image ? "PNG" : "MP4")"

        if item.kind == .image {
            kindLabel.stringValue = "截图"
            kindLabel.textColor = Palette.accent
        } else {
            kindLabel.stringValue = "录屏"
            kindLabel.textColor = Palette.danger
        }
        kindLabel.wantsLayer = true
        kindLabel.layer?.backgroundColor = kindLabel.textColor?.withAlphaComponent(0.10).cgColor
        kindLabel.layer?.cornerRadius = 6
        kindLabel.layer?.masksToBounds = true

        ThumbnailCache.shared.load(item) { [weak self] image in
            guard let self, self.item == item else { return }
            if let image {
                self.thumbnail.image = image.roundedThumbnail(size: NSSize(width: 152, height: 84), radius: 7)
                self.placeholder.isHidden = true
            }
        }
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
        onOpen?()
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovered {
            Palette.whiteLine.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), xRadius: 9, yRadius: 9).fill()
        }
    }
}

private final class RecentEmptyView: NSView {
    var onStart: (() -> Void)?
    private var tracking: NSTrackingArea?
    private var hovered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        let icon = makeSymbol("camera.viewfinder", size: 24, weight: .regular, color: Palette.textTertiary)
        addSubview(icon)

        let title = makeLabel("还没有截图或录屏", size: 13, weight: .semibold, color: Palette.text.withAlphaComponent(0.80))
        addSubview(title)

        let subtitle = makeLabel("按下 \(HotKeyStore.label(for: .area)) 框选，或点击这里开始第一次截图", size: 10.5, weight: .regular, color: Palette.textTertiary)
        addSubview(subtitle)

        let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
        addGestureRecognizer(click)

        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -22),
            icon.widthAnchor.constraint(equalToConstant: 28),
            icon.heightAnchor.constraint(equalToConstant: 28),
            title.centerXAnchor.constraint(equalTo: centerXAnchor),
            title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 8),
            subtitle.centerXAnchor.constraint(equalTo: centerXAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
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
        onStart?()
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovered {
            Palette.whiteLine.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), xRadius: 9, yRadius: 9).fill()
        }
    }
}

// MARK: - Permission banner

private final class PermissionBannerView: NSView {
    var onAuthorize: (() -> Void)?
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let button = GlintButton(title: "去授权", style: .primary)
    private var pulsing = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = Palette.accent.withAlphaComponent(0.08).cgColor
        layer?.borderColor = Palette.accent.withAlphaComponent(0.22).cgColor
        layer?.borderWidth = 1

        icon.image = NSImage(systemSymbolName: "exclamationmark.shield.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .semibold))
        icon.contentTintColor = Palette.accent
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)

        title.stringValue = "需要屏幕录制权限"
        title.font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        title.textColor = Palette.accentSoft
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)

        detail.stringValue = "授权后才能截图与录屏。画面只在本机处理，不会上传。"
        detail.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        detail.textColor = Palette.textSecondary
        detail.translatesAutoresizingMaskIntoConstraints = false
        addSubview(detail)

        button.target = self
        button.action = #selector(authorizeTapped)
        addSubview(button)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),

            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 9),

            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            detail.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -12),

            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 76),
            button.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func startPulse() {
        guard !pulsing else { return }
        pulsing = true
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 0.75
        animation.duration = 1.4
        animation.autoreverses = true
        animation.repeatCount = 2
        layer?.add(animation, forKey: "permissionPulse")
    }

    @objc private func authorizeTapped() {
        onAuthorize?()
    }
}
