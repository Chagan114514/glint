import AppKit

final class DownloadWindowController: NSObject, NSWindowDelegate {
    private let panel: DownloadPanel
    private let urlField = NSTextField()
    private let folderLabel = NSTextField(labelWithString: "")
    private let threadsPopup = NSPopUpButton()
    private let progressBar = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")
    private let speedLabel = NSTextField(labelWithString: "")
    private let startButton = GlintButton(title: "开始下载", style: .primary)
    private let cancelButton = GlintButton(title: "取消", style: .secondary)
    private let revealButton = GlintIconButton(symbol: "folder", size: 13)
    private var downloader: MultiThreadDownloader?
    private var destinationDirectory: URL
    private var savedFile: URL?
    private var closed = false
    private let onClose: (() -> Void)?

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        destinationDirectory = downloads
        panel = DownloadPanel(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 370),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
        buildUI()
        reload()
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
        panel.contentMinSize = NSSize(width: 580, height: 370)
        panel.contentMaxSize = NSSize(width: 580, height: 370)
    }

    private func buildUI() {
        let root = DownloadSurface(frame: NSRect(x: 0, y: 0, width: 580, height: 370))
        root.wantsLayer = true
        root.layer?.cornerRadius = 20
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = root
        root.widthAnchor.constraint(equalToConstant: 580).isActive = true
        root.heightAnchor.constraint(equalToConstant: 370).isActive = true

        let icon = makeSymbol("arrow.down.circle", size: 15, weight: .semibold, color: Palette.accent)
        root.addSubview(icon)
        let title = makeLabel("下载器", size: 19, weight: .semibold, color: Palette.text)
        root.addSubview(title)
        let subtitle = makeLabel("多线程下载任意 http/https 文件，自建分段引擎", size: 10.5, weight: .regular, color: Palette.textSecondary)
        root.addSubview(subtitle)
        let close = GlintIconButton(symbol: "xmark", size: 12, target: self, action: #selector(closeTapped))
        root.addSubview(close)

        let urlTitle = makeLabel("文件链接", size: 11, weight: .medium, color: Palette.text.withAlphaComponent(0.82))
        root.addSubview(urlTitle)
        urlField.placeholderString = "https://example.com/file.zip"
        urlField.font = NSFont.systemFont(ofSize: 12)
        urlField.controlSize = .regular
        urlField.bezelStyle = .roundedBezel
        urlField.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(urlField)

        let folderTitle = makeLabel("保存到", size: 11, weight: .medium, color: Palette.text.withAlphaComponent(0.82))
        root.addSubview(folderTitle)
        folderLabel.font = NSFont.systemFont(ofSize: 11)
        folderLabel.textColor = Palette.textSecondary
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(folderLabel)
        let chooseFolder = GlintButton(title: "更改…", style: .secondary)
        chooseFolder.target = self
        chooseFolder.action = #selector(chooseFolderTapped)
        root.addSubview(chooseFolder)

        let threadsTitle = makeLabel("线程", size: 11, weight: .medium, color: Palette.text.withAlphaComponent(0.82))
        root.addSubview(threadsTitle)
        threadsPopup.addItems(withTitles: ["1 线程", "2 线程", "4 线程", "8 线程"])
        threadsPopup.selectItem(at: 2)
        threadsPopup.font = NSFont.systemFont(ofSize: 11)
        threadsPopup.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(threadsPopup)

        progressBar.isIndeterminate = true
        progressBar.controlSize = .small
        progressBar.style = .bar
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(progressBar)

        statusLabel.font = NSFont.systemFont(ofSize: 10.5)
        statusLabel.textColor = Palette.textSecondary
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(statusLabel)

        speedLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        speedLabel.textColor = Palette.textTertiary
        speedLabel.alignment = .right
        speedLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(speedLabel)

        startButton.target = self
        startButton.action = #selector(startTapped)
        root.addSubview(startButton)
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)
        cancelButton.isEnabled = false
        cancelButton.alphaValue = 0.5
        root.addSubview(cancelButton)
        revealButton.target = self
        revealButton.action = #selector(revealTapped)
        revealButton.toolTip = "在 Finder 中显示"
        revealButton.isHidden = true
        root.addSubview(revealButton)

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

            urlTitle.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            urlTitle.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 24),
            urlField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            urlField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            urlField.topAnchor.constraint(equalTo: urlTitle.bottomAnchor, constant: 6),
            urlField.heightAnchor.constraint(equalToConstant: 28),

            folderTitle.leadingAnchor.constraint(equalTo: urlField.leadingAnchor),
            folderTitle.topAnchor.constraint(equalTo: urlField.bottomAnchor, constant: 18),
            folderLabel.leadingAnchor.constraint(equalTo: folderTitle.leadingAnchor),
            folderLabel.topAnchor.constraint(equalTo: folderTitle.bottomAnchor, constant: 6),
            folderLabel.trailingAnchor.constraint(lessThanOrEqualTo: chooseFolder.leadingAnchor, constant: -10),
            chooseFolder.trailingAnchor.constraint(equalTo: urlField.trailingAnchor),
            chooseFolder.centerYAnchor.constraint(equalTo: folderLabel.centerYAnchor),
            chooseFolder.widthAnchor.constraint(equalToConstant: 70),
            chooseFolder.heightAnchor.constraint(equalToConstant: 26),

            threadsTitle.leadingAnchor.constraint(equalTo: urlField.leadingAnchor),
            threadsTitle.topAnchor.constraint(equalTo: folderLabel.bottomAnchor, constant: 18),
            threadsPopup.leadingAnchor.constraint(equalTo: threadsTitle.trailingAnchor, constant: 12),
            threadsPopup.centerYAnchor.constraint(equalTo: threadsTitle.centerYAnchor),
            threadsPopup.widthAnchor.constraint(equalToConstant: 104),

            progressBar.leadingAnchor.constraint(equalTo: urlField.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: urlField.trailingAnchor),
            progressBar.topAnchor.constraint(equalTo: threadsPopup.bottomAnchor, constant: 22),
            progressBar.heightAnchor.constraint(equalToConstant: 6),

            statusLabel.leadingAnchor.constraint(equalTo: urlField.leadingAnchor),
            statusLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: speedLabel.leadingAnchor, constant: -10),
            speedLabel.trailingAnchor.constraint(equalTo: urlField.trailingAnchor),
            speedLabel.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),

            startButton.trailingAnchor.constraint(equalTo: urlField.trailingAnchor),
            startButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
            startButton.widthAnchor.constraint(equalToConstant: 96),
            startButton.heightAnchor.constraint(equalToConstant: 30),
            cancelButton.trailingAnchor.constraint(equalTo: startButton.leadingAnchor, constant: -8),
            cancelButton.centerYAnchor.constraint(equalTo: startButton.centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 76),
            cancelButton.heightAnchor.constraint(equalToConstant: 30),
            revealButton.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -6),
            revealButton.centerYAnchor.constraint(equalTo: startButton.centerYAnchor),
            revealButton.widthAnchor.constraint(equalToConstant: 28),
            revealButton.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    private func reload() {
        folderLabel.stringValue = shortPath(destinationDirectory)
    }

    private func shortPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if url.path.hasPrefix(home) { return "~" + url.path.dropFirst(home.count) }
        return url.path
    }

    @objc private func chooseFolderTapped() {
        let open = NSOpenPanel()
        open.canChooseFiles = false
        open.canChooseDirectories = true
        open.allowsMultipleSelection = false
        open.canCreateDirectories = true
        open.directoryURL = destinationDirectory
        open.prompt = "选择文件夹"
        open.message = "选择下载文件保存位置"
        NSApp.activate(ignoringOtherApps: true)
        open.beginSheetModal(for: panel) { [weak self] response in
            guard let self, response == .OK, let url = open.url else { return }
            self.destinationDirectory = url
            self.reload()
        }
    }

    @objc private func startTapped() {
        guard let raw = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
              let url = URL(string: raw) else {
            showStatus("请输入有效的文件链接", success: false)
            return
        }
        startDownload(url: url)
    }

    @objc private func cancelTapped() {
        downloader?.cancel()
        downloader = nil
        finishUI(success: false, message: "下载已取消")
    }

    @objc private func revealTapped() {
        guard let savedFile else { return }
        NSWorkspace.shared.activateFileViewerSelecting([savedFile])
    }

    private func startDownload(url: URL) {
        cancelTapped()
        savedFile = nil
        revealButton.isHidden = true
        startButton.isEnabled = false
        startButton.alphaValue = 0.5
        cancelButton.isEnabled = true
        cancelButton.alphaValue = 1
        progressBar.isIndeterminate = true
        progressBar.startAnimation(nil)
        statusLabel.textColor = Palette.textSecondary
        speedLabel.stringValue = ""
        showStatus("正在连接服务器…", success: true)

        let threads = [1, 2, 4, 8][max(0, min(3, threadsPopup.indexOfSelectedItem))]
        let downloader = MultiThreadDownloader()
        self.downloader = downloader
        downloader.start(url: url, destinationDirectory: destinationDirectory, threads: threads) { [weak self] progress in
            DispatchQueue.main.async {
                guard let self else { return }
                if let fraction = progress.fraction {
                    self.progressBar.isIndeterminate = false
                    self.progressBar.doubleValue = fraction * 100
                }
                let done = progress.total > 0
                    ? "\(Self.bytes(progress.received)) / \(Self.bytes(progress.total))"
                    : "\(Self.bytes(progress.received))"
                self.showStatus("已下载 \(done) · \(progress.partsDone)/\(progress.partsTotal) 段", success: true)
                self.speedLabel.stringValue = progress.bytesPerSecond > 0 ? "\(Self.bytes(Int64(progress.bytesPerSecond)))/s" : ""
            }
        } completion: { [weak self] result in
            guard let self else { return }
            self.downloader = nil
            switch result {
            case .success(let file):
                self.savedFile = file
                self.finishUI(success: true, message: "已保存 \(file.lastPathComponent)")
                self.revealButton.isHidden = false
                self.speedLabel.stringValue = ""
            case .failure(let error):
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.finishUI(success: false, message: message)
            }
        }
    }

    private func finishUI(success: Bool, message: String) {
        progressBar.stopAnimation(nil)
        progressBar.isIndeterminate = false
        if success { progressBar.doubleValue = 100 }
        startButton.isEnabled = true
        startButton.alphaValue = 1
        cancelButton.isEnabled = false
        cancelButton.alphaValue = 0.5
        showStatus(message, success: success)
    }

    private func showStatus(_ message: String, success: Bool) {
        statusLabel.stringValue = message
        statusLabel.textColor = success ? Palette.textSecondary : Palette.danger
    }

    private static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: max(0, value))
    }

    @objc private func closeTapped() { close() }

    private func close() {
        guard !closed else { return }
        closed = true
        downloader?.cancel()
        downloader = nil
        panel.orderOut(nil)
        onClose?()
    }

    func windowWillClose(_ notification: Notification) { close() }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private final class DownloadPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class DownloadSurface: NSView {
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
