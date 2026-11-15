import AppKit
import AVFoundation

final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let panel: SettingsPanel
    private let imageRow = FolderSettingRow(title: "截图保存目录", symbol: "photo")
    private let videoRow = FolderSettingRow(title: "录屏保存目录", symbol: "film")
    private let audioPopup = NSPopUpButton()
    private let micPopup = NSPopUpButton()
    private let micNote = NSTextField(labelWithString: "")
    private let updateSwitch = NSSwitch()
    private let updateStatus = NSTextField(labelWithString: "")
    private let checkUpdateButton = GlintButton(title: "检查更新", style: .secondary)
    private let onClose: (() -> Void)?
    private var devices: [AVCaptureDevice] = []
    private var closed = false

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
        panel = SettingsPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 700),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
        buildUI()
        reload()
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
        panel.makeKeyAndOrderFront(nil)
        reload()
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
        panel.contentMinSize = NSSize(width: 620, height: 700)
        panel.contentMaxSize = NSSize(width: 620, height: 700)
    }

    private func buildUI() {
        let root = SettingsSurface(frame: NSRect(x: 0, y: 0, width: 620, height: 700))
        root.wantsLayer = true
        root.layer?.cornerRadius = 20
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = root
        root.widthAnchor.constraint(equalToConstant: 620).isActive = true
        root.heightAnchor.constraint(equalToConstant: 700).isActive = true

        let icon = makeSymbol("gearshape.fill", size: 15, weight: .semibold, color: Palette.accent)
        root.addSubview(icon)
        let title = makeLabel("设置", size: 20, weight: .semibold, color: Palette.text)
        root.addSubview(title)
        let subtitle = makeLabel("保存位置、声音、识别与更新", size: 10.5, weight: .regular, color: Palette.textSecondary)
        root.addSubview(subtitle)
        let close = GlintIconButton(symbol: "xmark", size: 12, target: self, action: #selector(closeTapped))
        root.addSubview(close)

        let filesTitle = makeLabel("文件保存位置", size: 12, weight: .semibold, color: Palette.text.withAlphaComponent(0.86))
        root.addSubview(filesTitle)

        imageRow.onChange = { [weak self] in self?.chooseImageFolder() }
        imageRow.onOpen = { CaptureLibrary.shared.openFolder(CaptureLibrary.shared.imageDirectory) }
        imageRow.onReset = { [weak self] in
            CaptureLibrary.shared.resetImageDirectory()
            self?.reload()
        }
        root.addSubview(imageRow)

        videoRow.onChange = { [weak self] in self?.chooseVideoFolder() }
        videoRow.onOpen = { CaptureLibrary.shared.openFolder(CaptureLibrary.shared.videoDirectory) }
        videoRow.onReset = { [weak self] in
            CaptureLibrary.shared.resetVideoDirectory()
            self?.reload()
        }
        root.addSubview(videoRow)

        let audioTitle = makeLabel("录制与声音", size: 12, weight: .semibold, color: Palette.text.withAlphaComponent(0.86))
        root.addSubview(audioTitle)

        let audioCard = GlintCardView()
        audioCard.fillColor = Palette.surface
        audioCard.borderColor = Palette.stroke
        audioCard.cornerRadius = 14
        root.addSubview(audioCard)

        let sourceLabel = makeLabel("声音来源", size: 11.5, weight: .medium, color: Palette.text)
        audioCard.addSubview(sourceLabel)

        audioPopup.translatesAutoresizingMaskIntoConstraints = false
        audioPopup.target = self
        audioPopup.action = #selector(audioSourceChanged)
        audioPopup.controlSize = .small
        audioCard.addSubview(audioPopup)

        let micLabel = makeLabel("麦克风设备", size: 11.5, weight: .medium, color: Palette.text)
        audioCard.addSubview(micLabel)

        micPopup.translatesAutoresizingMaskIntoConstraints = false
        micPopup.target = self
        micPopup.action = #selector(micDeviceChanged)
        micPopup.controlSize = .small
        audioCard.addSubview(micPopup)

        micNote.font = NSFont.systemFont(ofSize: 9.5, weight: .regular)
        micNote.textColor = Palette.textTertiary
        micNote.lineBreakMode = .byTruncatingTail
        micNote.translatesAutoresizingMaskIntoConstraints = false
        audioCard.addSubview(micNote)

        let ocrTitle = makeLabel("OCR 文字识别", size: 12, weight: .semibold, color: Palette.text.withAlphaComponent(0.86))
        root.addSubview(ocrTitle)
        let ocrCard = GlintCardView()
        ocrCard.fillColor = Palette.surface
        ocrCard.borderColor = Palette.stroke
        ocrCard.cornerRadius = 14
        root.addSubview(ocrCard)
        let ocrIcon = makeSymbol("text.viewfinder", size: 16, weight: .regular, color: Palette.teal)
        ocrCard.addSubview(ocrIcon)
        let ocrTitle2 = makeLabel("截图文字识别", size: 11.5, weight: .medium, color: Palette.text)
        ocrCard.addSubview(ocrTitle2)
        let ocrDetail = makeLabel("使用 Apple Vision 在本机识别简体中文与英文，不上传图片。", size: 9.5, weight: .regular, color: Palette.textTertiary)
        ocrCard.addSubview(ocrDetail)
        let ocrBadge = makeLabel("本地", size: 9.5, weight: .semibold, color: Palette.teal, alignment: .center)
        ocrBadge.wantsLayer = true
        ocrBadge.layer?.backgroundColor = Palette.teal.withAlphaComponent(0.10).cgColor
        ocrBadge.layer?.cornerRadius = 6
        ocrBadge.layer?.masksToBounds = true
        ocrCard.addSubview(ocrBadge)

        let updateTitle = makeLabel("软件更新", size: 12, weight: .semibold, color: Palette.text.withAlphaComponent(0.86))
        root.addSubview(updateTitle)
        let updateCard = GlintCardView()
        updateCard.fillColor = Palette.surface
        updateCard.borderColor = Palette.stroke
        updateCard.cornerRadius = 14
        root.addSubview(updateCard)
        let updateIcon = makeSymbol("arrow.triangle.2.circlepath", size: 16, weight: .regular, color: Palette.accent)
        updateCard.addSubview(updateIcon)
        let autoLabel = makeLabel("启动时检查更新", size: 11.5, weight: .medium, color: Palette.text)
        updateCard.addSubview(autoLabel)
        let autoDetail = makeLabel("发现新版本时会提示你前往 GitHub。", size: 9.5, weight: .regular, color: Palette.textTertiary)
        updateCard.addSubview(autoDetail)

        updateSwitch.translatesAutoresizingMaskIntoConstraints = false
        updateSwitch.controlSize = .small
        updateSwitch.target = self
        updateSwitch.action = #selector(updateSwitchChanged)
        updateCard.addSubview(updateSwitch)

        updateStatus.font = NSFont.systemFont(ofSize: 9.5, weight: .regular)
        updateStatus.textColor = Palette.textTertiary
        updateStatus.lineBreakMode = .byTruncatingTail
        updateStatus.translatesAutoresizingMaskIntoConstraints = false
        updateCard.addSubview(updateStatus)

        checkUpdateButton.target = self
        checkUpdateButton.action = #selector(checkUpdateTapped)
        updateCard.addSubview(checkUpdateButton)

        let footer = makeLabel("修改立即生效，只影响之后生成的文件。", size: 9.5, weight: .regular, color: Palette.textTertiary, alignment: .center)
        root.addSubview(footer)

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

            filesTitle.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 26),
            filesTitle.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 24),

            imageRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
            imageRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),
            imageRow.topAnchor.constraint(equalTo: filesTitle.bottomAnchor, constant: 8),
            imageRow.heightAnchor.constraint(equalToConstant: 76),

            videoRow.leadingAnchor.constraint(equalTo: imageRow.leadingAnchor),
            videoRow.trailingAnchor.constraint(equalTo: imageRow.trailingAnchor),
            videoRow.topAnchor.constraint(equalTo: imageRow.bottomAnchor, constant: 8),
            videoRow.heightAnchor.constraint(equalToConstant: 76),

            audioTitle.leadingAnchor.constraint(equalTo: filesTitle.leadingAnchor),
            audioTitle.topAnchor.constraint(equalTo: videoRow.bottomAnchor, constant: 20),

            audioCard.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
            audioCard.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),
            audioCard.topAnchor.constraint(equalTo: audioTitle.bottomAnchor, constant: 8),
            audioCard.heightAnchor.constraint(equalToConstant: 118),

            sourceLabel.leadingAnchor.constraint(equalTo: audioCard.leadingAnchor, constant: 16),
            sourceLabel.topAnchor.constraint(equalTo: audioCard.topAnchor, constant: 16),
            audioPopup.trailingAnchor.constraint(equalTo: audioCard.trailingAnchor, constant: -14),
            audioPopup.centerYAnchor.constraint(equalTo: sourceLabel.centerYAnchor),
            audioPopup.widthAnchor.constraint(equalToConstant: 196),

            micLabel.leadingAnchor.constraint(equalTo: sourceLabel.leadingAnchor),
            micLabel.topAnchor.constraint(equalTo: sourceLabel.bottomAnchor, constant: 24),
            micPopup.trailingAnchor.constraint(equalTo: audioPopup.trailingAnchor),
            micPopup.centerYAnchor.constraint(equalTo: micLabel.centerYAnchor),
            micPopup.widthAnchor.constraint(equalToConstant: 196),

            micNote.leadingAnchor.constraint(equalTo: micLabel.leadingAnchor),
            micNote.trailingAnchor.constraint(equalTo: audioCard.trailingAnchor, constant: -14),
            micNote.topAnchor.constraint(equalTo: micLabel.bottomAnchor, constant: 5),

            ocrTitle.leadingAnchor.constraint(equalTo: filesTitle.leadingAnchor),
            ocrTitle.topAnchor.constraint(equalTo: audioCard.bottomAnchor, constant: 20),

            ocrCard.leadingAnchor.constraint(equalTo: imageRow.leadingAnchor),
            ocrCard.trailingAnchor.constraint(equalTo: imageRow.trailingAnchor),
            ocrCard.topAnchor.constraint(equalTo: ocrTitle.bottomAnchor, constant: 8),
            ocrCard.heightAnchor.constraint(equalToConstant: 62),

            ocrIcon.leadingAnchor.constraint(equalTo: ocrCard.leadingAnchor, constant: 16),
            ocrIcon.centerYAnchor.constraint(equalTo: ocrCard.centerYAnchor),
            ocrIcon.widthAnchor.constraint(equalToConstant: 18),
            ocrIcon.heightAnchor.constraint(equalToConstant: 18),
            ocrTitle2.leadingAnchor.constraint(equalTo: ocrIcon.trailingAnchor, constant: 10),
            ocrTitle2.topAnchor.constraint(equalTo: ocrCard.topAnchor, constant: 13),
            ocrDetail.leadingAnchor.constraint(equalTo: ocrTitle2.leadingAnchor),
            ocrDetail.topAnchor.constraint(equalTo: ocrTitle2.bottomAnchor, constant: 2),
            ocrBadge.trailingAnchor.constraint(equalTo: ocrCard.trailingAnchor, constant: -14),
            ocrBadge.centerYAnchor.constraint(equalTo: ocrCard.centerYAnchor),
            ocrBadge.widthAnchor.constraint(equalToConstant: 38),
            ocrBadge.heightAnchor.constraint(equalToConstant: 20),

            updateTitle.leadingAnchor.constraint(equalTo: filesTitle.leadingAnchor),
            updateTitle.topAnchor.constraint(equalTo: ocrCard.bottomAnchor, constant: 18),

            updateCard.leadingAnchor.constraint(equalTo: imageRow.leadingAnchor),
            updateCard.trailingAnchor.constraint(equalTo: imageRow.trailingAnchor),
            updateCard.topAnchor.constraint(equalTo: updateTitle.bottomAnchor, constant: 8),
            updateCard.heightAnchor.constraint(equalToConstant: 96),

            updateIcon.leadingAnchor.constraint(equalTo: updateCard.leadingAnchor, constant: 16),
            updateIcon.topAnchor.constraint(equalTo: updateCard.topAnchor, constant: 15),
            updateIcon.widthAnchor.constraint(equalToConstant: 18),
            updateIcon.heightAnchor.constraint(equalToConstant: 18),
            autoLabel.leadingAnchor.constraint(equalTo: updateIcon.trailingAnchor, constant: 10),
            autoLabel.topAnchor.constraint(equalTo: updateCard.topAnchor, constant: 13),
            autoDetail.leadingAnchor.constraint(equalTo: autoLabel.leadingAnchor),
            autoDetail.topAnchor.constraint(equalTo: autoLabel.bottomAnchor, constant: 2),
            autoDetail.trailingAnchor.constraint(lessThanOrEqualTo: updateSwitch.leadingAnchor, constant: -10),
            updateSwitch.trailingAnchor.constraint(equalTo: updateCard.trailingAnchor, constant: -16),
            updateSwitch.topAnchor.constraint(equalTo: updateCard.topAnchor, constant: 13),

            updateStatus.leadingAnchor.constraint(equalTo: updateCard.leadingAnchor, constant: 16),
            updateStatus.trailingAnchor.constraint(lessThanOrEqualTo: checkUpdateButton.leadingAnchor, constant: -10),
            updateStatus.bottomAnchor.constraint(equalTo: updateCard.bottomAnchor, constant: -16),
            checkUpdateButton.trailingAnchor.constraint(equalTo: updateCard.trailingAnchor, constant: -14),
            checkUpdateButton.bottomAnchor.constraint(equalTo: updateCard.bottomAnchor, constant: -13),
            checkUpdateButton.widthAnchor.constraint(equalToConstant: 84),
            checkUpdateButton.heightAnchor.constraint(equalToConstant: 28),

            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
        ])
    }

    private func reload() {
        imageRow.path = shortPath(CaptureLibrary.shared.imageDirectory)
        imageRow.showsReset = !CaptureLibrary.shared.isUsingDefaultImageDirectory
        videoRow.path = shortPath(CaptureLibrary.shared.videoDirectory)
        videoRow.showsReset = !CaptureLibrary.shared.isUsingDefaultVideoDirectory

        audioPopup.removeAllItems()
        for source in AudioSource.allCases {
            audioPopup.addItem(withTitle: source.title)
        }
        if let index = AudioSource.allCases.firstIndex(of: Prefs.audioSource) {
            audioPopup.selectItem(at: index)
        }

        devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices

        micPopup.removeAllItems()
        micPopup.addItem(withTitle: "系统默认")
        for device in devices {
            micPopup.addItem(withTitle: device.localizedName)
        }
        if let id = Prefs.microphoneDeviceID, let index = devices.firstIndex(where: { $0.uniqueID == id }) {
            micPopup.selectItem(at: index + 1)
        } else {
            micPopup.selectItem(at: 0)
        }
        updateMicState()

        updateSwitch.state = Prefs.updateCheckEnabled ? .on : .off
        updateStatus.stringValue = Prefs.updateCheckEnabled
            ? "当前版本 v\(UpdateChecker.currentVersion)"
            : "已关闭自动检查，仍可手动检查"
    }

    private func updateMicState() {
        let usesMic = Prefs.audioSource.usesMicrophone
        micPopup.isEnabled = usesMic
        if #available(macOS 15.0, *) {
            micNote.stringValue = usesMic
                ? "外部麦克风或系统默认输入；首次录音会请求麦克风权限。"
                : "选择含麦克风的声音来源后可调整设备。"
        } else {
            micNote.stringValue = "麦克风录制需要 macOS 15 或更高版本。"
            micPopup.isEnabled = false
        }
    }

    private func shortPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if url.path.hasPrefix(home) {
            return "~" + url.path.dropFirst(home.count)
        }
        return url.path
    }

    private func chooseImageFolder() {
        chooseFolder(start: CaptureLibrary.shared.imageDirectory) { [weak self] url in
            do {
                try CaptureLibrary.shared.setImageDirectory(url)
                self?.reload()
            } catch {
                self?.showDirectoryError(error)
            }
        }
    }

    private func chooseVideoFolder() {
        chooseFolder(start: CaptureLibrary.shared.videoDirectory) { [weak self] url in
            do {
                try CaptureLibrary.shared.setVideoDirectory(url)
                self?.reload()
            } catch {
                self?.showDirectoryError(error)
            }
        }
    }

    private func chooseFolder(start: URL, completion: @escaping (URL) -> Void) {
        let open = NSOpenPanel()
        open.canChooseFiles = false
        open.canChooseDirectories = true
        open.allowsMultipleSelection = false
        open.canCreateDirectories = true
        open.directoryURL = start
        open.prompt = "选择文件夹"
        open.message = "选择保存位置"
        NSApp.activate(ignoringOtherApps: true)
        open.beginSheetModal(for: panel) { response in
            guard response == .OK, let url = open.url else { return }
            completion(url)
        }
    }

    private func showDirectoryError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "无法使用这个文件夹"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    @objc private func audioSourceChanged() {
        let index = audioPopup.indexOfSelectedItem
        guard index >= 0, index < AudioSource.allCases.count else { return }
        Prefs.audioSource = AudioSource.allCases[index]
        updateMicState()
    }

    @objc private func micDeviceChanged() {
        let index = micPopup.indexOfSelectedItem
        if index <= 0 {
            Prefs.microphoneDeviceID = nil
        } else if index - 1 < devices.count {
            Prefs.microphoneDeviceID = devices[index - 1].uniqueID
        }
    }

    @objc private func updateSwitchChanged() {
        let enabled = updateSwitch.state == .on
        Prefs.updateCheckEnabled = enabled
        updateStatus.stringValue = enabled
            ? "启动时会自动检查更新"
            : "已关闭自动检查，仍可手动检查"
    }

    @objc private func checkUpdateTapped() {
        checkUpdateButton.isEnabled = false
        updateStatus.stringValue = "正在检查更新…"
        UpdateChecker.shared.checkManually(presenting: panel) { [weak self] result in
            guard let self else { return }
            self.checkUpdateButton.isEnabled = true
            switch result {
            case .upToDate:
                self.updateStatus.stringValue = "已是最新版本"
            case .available(let info):
                self.updateStatus.stringValue = "发现新版本 v\(info.version)"
            case .failed:
                self.updateStatus.stringValue = "检查失败，请稍后再试"
            case .disabled:
                self.updateStatus.stringValue = "已关闭自动检查，仍可手动检查"
            }
        }
    }

    @objc private func closeTapped() {
        close()
    }

    private func close() {
        guard !closed else { return }
        closed = true
        panel.orderOut(nil)
        onClose?()
    }

    func windowWillClose(_ notification: Notification) {
        close()
    }
}

private final class SettingsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class SettingsSurface: NSView {
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

private final class FolderSettingRow: NSView {
    private let icon: NSImageView
    private let titleLabel: NSTextField
    private let pathLabel: NSTextField
    private let changeButton = GlintButton(title: "更改…", style: .secondary)
    private let openButton = GlintIconButton(symbol: "folder", size: 13)
    private let resetButton = NSButton(title: "恢复默认", target: nil, action: nil)
    var onChange: (() -> Void)?
    var onOpen: (() -> Void)?
    var onReset: (() -> Void)?

    var path: String = "" {
        didSet { pathLabel.stringValue = path; pathLabel.toolTip = path }
    }

    var showsReset = false {
        didSet { resetButton.isHidden = !showsReset }
    }

    init(title: String, symbol: String) {
        icon = makeSymbol(symbol, size: 16, weight: .regular, color: Palette.textSecondary)
        titleLabel = makeLabel(title, size: 11.5, weight: .medium, color: Palette.text)
        pathLabel = makeLabel("", size: 10, weight: .regular, color: Palette.textTertiary)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = Palette.surface.cgColor
        layer?.borderColor = Palette.stroke.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous

        addSubview(icon)
        addSubview(titleLabel)
        addSubview(pathLabel)

        changeButton.target = self
        changeButton.action = #selector(changeTapped)
        addSubview(changeButton)

        openButton.target = self
        openButton.action = #selector(openTapped)
        openButton.toolTip = "打开文件夹"
        addSubview(openButton)

        resetButton.isBordered = false
        resetButton.isTransparent = true
        resetButton.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        resetButton.contentTintColor = Palette.textTertiary
        resetButton.attributedTitle = NSAttributedString(string: "恢复默认", attributes: [
            .font: NSFont.systemFont(ofSize: 9.5, weight: .medium),
            .foregroundColor: Palette.textTertiary,
        ])
        resetButton.target = self
        resetButton.action = #selector(resetTapped)
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(resetButton)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 13),
            pathLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            pathLabel.trailingAnchor.constraint(lessThanOrEqualTo: changeButton.leadingAnchor, constant: -12),
            pathLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),

            resetButton.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            resetButton.topAnchor.constraint(equalTo: pathLabel.bottomAnchor, constant: 2),

            changeButton.trailingAnchor.constraint(equalTo: openButton.leadingAnchor, constant: -8),
            changeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            changeButton.widthAnchor.constraint(equalToConstant: 70),
            changeButton.heightAnchor.constraint(equalToConstant: 28),

            openButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            openButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            openButton.widthAnchor.constraint(equalToConstant: 30),
            openButton.heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    required init?(coder: NSCoder) { nil }

    @objc private func changeTapped() { onChange?() }
    @objc private func openTapped() { onOpen?() }
    @objc private func resetTapped() { onReset?() }
}
