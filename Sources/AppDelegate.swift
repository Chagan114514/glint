import AppKit
import ScreenCaptureKit

private final class RecordingSession {
    let recorder: ScreenRecorder
    let hud: RecordingHUDController
    let targetLabel: String
    var stopping = false

    init(recorder: ScreenRecorder, hud: RecordingHUDController, targetLabel: String) {
        self.recorder = recorder
        self.hud = hud
        self.targetLabel = targetLabel
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var dashboard: DashboardWindowController!
    private var statusItem: NSStatusItem!
    private var resultPanel: ResultPanelController?
    private var areaSelector: AreaSelectorController?
    private var windowPicker: WindowPickerController?
    private var recordChooser: RecordChooserController?
    private var recordingSession: RecordingSession?
    private var startingRecording = false
    private var activeSound: NSSound?
    private var settingsWindow: SettingsWindowController?
    private var scrollingCapture: ScrollingCaptureController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        buildStatusItem()
        buildDashboard()
        installHotKeys()
        NSApp.activate(ignoringOtherApps: true)
        dashboard.show()
        UpdateChecker.shared.checkOnLaunch()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        dashboard.show()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        dashboard?.refreshPermission()
        dashboard?.refreshRecentAndLibrary()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme?.lowercased() == "glint" {
            let raw = (url.host ?? url.path).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let action = raw.lowercased()
            switch action {
            case "area", "capture-area":
                beginAreaScreenshot()
            case "window", "capture-window":
                beginWindowScreenshot()
            case "full", "fullscreen", "capture-screen":
                captureFullScreen()
            case "scroll", "scrolling", "scrolling-capture":
                beginScrollingCapture()
            case "record", "recording":
                showRecordChooser()
            case "stop", "stop-recording":
                if recordingSession != nil { stopRecording() }
            case "pause", "pause-recording":
                togglePauseRecording()
            case "dashboard", "open":
                dashboard.show()
            case "settings":
                showSettings()
            case "update", "check-update", "checkupdate", "check-for-updates":
                UpdateChecker.shared.checkManually(presenting: NSApp.keyWindow)
            case "permission":
                requestPermissionFromUser()
            default:
                break
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if recordingSession != nil || startingRecording {
            let alert = NSAlert()
            alert.messageText = "正在录制"
            alert.informativeText = "请先停止并保存当前录屏，再退出 Glint。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "知道了")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return .terminateCancel
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        recordingSession?.recorder.cancel()
    }

    // MARK: - Dashboard

    private func buildDashboard() {
        dashboard = DashboardWindowController()
        dashboard.onArea = { [weak self] in self?.beginAreaScreenshot() }
        dashboard.onWindow = { [weak self] in self?.beginWindowScreenshot() }
        dashboard.onFullScreen = { [weak self] in self?.captureFullScreen() }
        dashboard.onRecord = { [weak self] in self?.showRecordChooser() }
        dashboard.onOpenRecent = { [weak self] item in self?.openRecent(item) }
        dashboard.onRequestPermission = { [weak self] in self?.requestPermissionFromUser() }
        dashboard.onOpenSettings = { [weak self] in self?.showSettings() }
        dashboard.onScrollCapture = { [weak self] in self?.beginScrollingCapture() }
        dashboard.onOpenImageFolder = { CaptureLibrary.shared.openFolder(CaptureLibrary.shared.imageDirectory) }
        dashboard.onOpenVideoFolder = { CaptureLibrary.shared.openFolder(CaptureLibrary.shared.videoDirectory) }
        NotificationCenter.default.addObserver(forName: CaptureLibrary.settingsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.dashboard.refreshRecentAndLibrary()
        }
    }

    // MARK: - Status item

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Glint")?
                .withSymbolConfiguration(config)
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Glint 截屏与录屏"
        }
        updateStatusMenu()
    }

    private func updateStatusMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false

        let open = NSMenuItem(title: "打开 Glint", action: #selector(openDashboard), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())

        let area = NSMenuItem(title: "区域截图    ⌃⌥1", action: #selector(areaScreenshotAction), keyEquivalent: "")
        area.target = self
        menu.addItem(area)

        let window = NSMenuItem(title: "窗口截图    ⌃⌥2", action: #selector(windowScreenshotAction), keyEquivalent: "")
        window.target = self
        menu.addItem(window)

        let full = NSMenuItem(title: "全屏截图    ⌃⌥3", action: #selector(fullScreenshotAction), keyEquivalent: "")
        full.target = self
        menu.addItem(full)

        let scroll = NSMenuItem(title: "滚动截图    ⌃⌥6", action: #selector(scrollScreenshotAction), keyEquivalent: "")
        scroll.target = self
        menu.addItem(scroll)

        if let session = recordingSession {
            if !session.stopping {
                let paused = session.recorder.isPaused
                let pause = NSMenuItem(
                    title: paused ? "继续录制    ⌃⌥5" : "暂停录制    ⌃⌥5",
                    action: #selector(pauseRecordingAction),
                    keyEquivalent: ""
                )
                pause.target = self
                menu.addItem(pause)
            }
            let stop = NSMenuItem(
                title: session.stopping ? "正在保存录屏…" : "停止录制    ⌃⌥4",
                action: #selector(stopRecordingAction),
                keyEquivalent: ""
            )
            stop.target = self
            stop.isEnabled = !session.stopping
            menu.addItem(stop)
        } else if startingRecording {
            let starting = NSMenuItem(title: "正在开始录制…", action: nil, keyEquivalent: "")
            starting.isEnabled = false
            menu.addItem(starting)
        } else {
            let record = NSMenuItem(title: "屏幕录制…    ⌃⌥4", action: #selector(recordAction), keyEquivalent: "")
            record.target = self
            menu.addItem(record)
        }

        menu.addItem(.separator())

        let images = NSMenuItem(title: "打开截图文件夹", action: #selector(openImagesAction), keyEquivalent: "")
        images.target = self
        menu.addItem(images)

        let videos = NSMenuItem(title: "打开录屏文件夹", action: #selector(openVideosAction), keyEquivalent: "")
        videos.target = self
        menu.addItem(videos)

        menu.addItem(.separator())

        if !HotKeyManager.shared.failedShortcuts.isEmpty {
            let conflict = NSMenuItem(
                title: "快捷键被占用：\(HotKeyManager.shared.failedShortcuts.joined(separator: "、"))",
                action: nil,
                keyEquivalent: ""
            )
            conflict.isEnabled = false
            menu.addItem(conflict)
        }

        let settings = NSMenuItem(title: "设置…    ⌘,", action: #selector(openSettingsAction), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        let updates = NSMenuItem(title: "检查更新…", action: #selector(checkForUpdatesAction), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)

        let permission = NSMenuItem(title: "屏幕权限设置…", action: #selector(openPermissionSettings), keyEquivalent: "")
        permission.target = self
        menu.addItem(permission)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 Glint", action: #selector(quitApp), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        if recordingSession != nil || startingRecording {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                .applying(.init(paletteColors: [Palette.danger]))
            let image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "正在录制")?
                .withSymbolConfiguration(config)
            image?.isTemplate = false
            button.image = image
            button.toolTip = recordingSession?.recorder.isPaused == true ? "Glint 已暂停录制" : "Glint 正在录制"
        } else {
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Glint")?
                .withSymbolConfiguration(config)
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Glint 截屏与录屏"
        }
    }

    // MARK: - Hot keys

    private func installHotKeys() {
        HotKeyManager.shared.install(
            area: { [weak self] in self?.beginAreaScreenshot() },
            window: { [weak self] in self?.beginWindowScreenshot() },
            fullScreen: { [weak self] in self?.captureFullScreen() },
            record: { [weak self] in self?.toggleRecording() },
            pause: { [weak self] in self?.togglePauseRecording() },
            scroll: { [weak self] in self?.beginScrollingCapture() }
        )
        updateStatusMenu()
    }

    // MARK: - Permission

    private func ensurePermission() -> Bool {
        if ScreenPermission.isGranted { return true }
        _ = ScreenPermission.request()
        dashboard.refreshPermission()
        return ScreenPermission.isGranted
    }

    private func requestPermissionFromUser() {
        _ = ensurePermission()
        dashboard.refreshPermission()
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "需要「屏幕与系统音频录制」权限"
        alert.informativeText = "请在「系统设置 → 隐私与安全性 → 屏幕与系统音频录制」中开启 Glint。\n\n开启后如果仍然无法截图，请退出并重新打开 Glint。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            ScreenPermission.openSettings()
        }
    }

    // MARK: - Settings

    private func showSettings() {
        if let settingsWindow {
            settingsWindow.show()
            return
        }
        let controller = SettingsWindowController { [weak self] in
            self?.settingsWindow = nil
        }
        settingsWindow = controller
        controller.show()
    }

    // MARK: - Scrolling capture

    private func beginScrollingCapture() {
        guard !hasActiveChooser, ensurePermission() else { return }
        let selector = AreaSelectorController(purpose: .scrolling) { [weak self] selection in
            guard let self else { return }
            self.areaSelector = nil
            guard let selection else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self else { return }
                let controller = ScrollingCaptureController(
                    selection: .init(screen: selection.screen, rect: selection.rect),
                    scale: selection.screen.backingScaleFactor
                )
                controller.onFinish = { [weak self] captured, error in
                    guard let self else { return }
                    self.scrollingCapture = nil
                    if let captured {
                        self.persistImage(captured)
                        NSApp.activate(ignoringOtherApps: true)
                    } else if let error {
                        self.showError(title: "滚动截图", message: error)
                    }
                }
                self.scrollingCapture = controller
                controller.begin()
            }
        }
        areaSelector = selector
        selector.begin()
    }

    // MARK: - Screenshots

    private var hasActiveChooser: Bool {
        areaSelector != nil || windowPicker != nil || recordChooser != nil || scrollingCapture != nil
    }

    private func beginAreaScreenshot() {
        guard !hasActiveChooser, ensurePermission() else { return }
        let selector = AreaSelectorController(purpose: .screenshot) { [weak self] selection in
            guard let self else { return }
            self.areaSelector = nil
            guard let selection else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                self.captureArea(selection)
            }
        }
        areaSelector = selector
        selector.begin()
    }

    private func beginWindowScreenshot() {
        guard !hasActiveChooser, ensurePermission() else { return }
        let picker = WindowPickerController(purpose: .screenshot) { [weak self] window in
            guard let self else { return }
            self.windowPicker = nil
            guard let window else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                self.captureWindow(window)
            }
        }
        windowPicker = picker
        picker.show()
    }

    private func captureFullScreen() {
        guard !hasActiveChooser, ensurePermission() else { return }
        guard let screen = screenUnderMouse() else { return }
        Task { @MainActor in
            do {
                let captured = try await CaptureEngine.shared.captureFullScreen(screen: screen)
                self.persistImage(captured)
            } catch {
                self.handleCaptureError(error)
            }
        }
    }

    private func captureArea(_ selection: AreaSelectorController.Selection) {
        Task { @MainActor in
            do {
                let captured = try await CaptureEngine.shared.captureArea(screen: selection.screen, localRect: selection.rect)
                self.persistImage(captured)
            } catch {
                self.handleCaptureError(error)
            }
        }
    }

    private func captureWindow(_ window: SCWindow) {
        Task { @MainActor in
            do {
                let captured = try await CaptureEngine.shared.captureWindow(window)
                self.persistImage(captured)
            } catch {
                self.handleCaptureError(error)
            }
        }
    }

    private func persistImage(_ captured: CapturedImage) {
        let copied = CaptureLibrary.shared.copyToPasteboard(captured)
        do {
            let url = try CaptureLibrary.shared.saveImage(captured)
            playSound("Screen Capture.aif")
            presentResult(mode: .image(captured: captured, url: url), fresh: true, copied: copied)
        } catch {
            showError(title: "保存截图失败", message: error.localizedDescription)
        }
    }

    private func handleCaptureError(_ error: Error) {
        if let glint = error as? GlintError, case .noPermission = glint {
            dashboard.refreshPermission()
            showPermissionAlert()
            return
        }
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        showError(title: "截图失败", message: message)
    }

    // MARK: - Recording

    private func toggleRecording() {
        if recordingSession != nil {
            stopRecording()
        } else {
            showRecordChooser()
        }
    }

    private func showRecordChooser() {
        if recordingSession != nil {
            stopRecording()
            return
        }
        guard !startingRecording, !hasActiveChooser, ensurePermission() else { return }
        let chooser = RecordChooserController { [weak self] choice, audioSource in
            guard let self else { return }
            self.recordChooser = nil
            guard let choice else { return }
            self.handleRecordChoice(choice, audioSource: audioSource)
        }
        recordChooser = chooser
        chooser.show()
    }

    private func handleRecordChoice(_ choice: RecordChoice, audioSource: AudioSource) {
        switch choice {
        case .display:
            guard let screen = screenUnderMouse() else { return }
            Task { @MainActor in
                do {
                    let content = try await CaptureEngine.shared.loadContent()
                    let display = try CaptureEngine.shared.display(for: screen, in: content)
                    self.startRecording(
                        target: .display(display: display, name: screen.glintName),
                        audioSource: audioSource
                    )
                } catch {
                    self.handleRecordError(error)
                }
            }

        case .area:
            let selector = AreaSelectorController(purpose: .recording) { [weak self] selection in
                guard let self else { return }
                self.areaSelector = nil
                guard let selection else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    self.startAreaRecording(selection, audioSource: audioSource)
                }
            }
            areaSelector = selector
            selector.begin()

        case .window:
            let picker = WindowPickerController(purpose: .recording) { [weak self] window in
                guard let self else { return }
                self.windowPicker = nil
                guard let window else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    self.startRecording(target: .window(window: window), audioSource: audioSource)
                }
            }
            windowPicker = picker
            picker.show()
        }
    }

    private func startAreaRecording(_ selection: AreaSelectorController.Selection, audioSource: AudioSource) {
        Task { @MainActor in
            do {
                let content = try await CaptureEngine.shared.loadContent()
                let display = try CaptureEngine.shared.display(for: selection.screen, in: content)
                let screen = selection.screen
                let local = selection.rect
                let sourceRect = CGRect(
                    x: local.minX,
                    y: screen.frame.height - local.maxY,
                    width: local.width,
                    height: local.height
                )
                self.startRecording(
                    target: .area(
                        display: display,
                        sourceRect: sourceRect,
                        name: screen.glintName,
                        pointSize: local.size
                    ),
                    audioSource: audioSource
                )
            } catch {
                self.handleRecordError(error)
            }
        }
    }

    private func startRecording(target: RecordingTarget, audioSource: AudioSource) {
        guard recordingSession == nil, !startingRecording else { return }
        startingRecording = true
        updateStatusMenu()

        let hud = RecordingHUDController()
        let recorder = ScreenRecorder(target: target, audioSource: audioSource)
        recorder.onUnexpectedStop = { [weak self] error in
            guard let self, let session = self.recordingSession else { return }
            session.hud.setFailed()
            self.stopRecording(interruptedBy: error)
        }
        recorder.start { [weak self] result in
            guard let self else { return }
            self.startingRecording = false
            switch result {
            case .success:
                let session = RecordingSession(recorder: recorder, hud: hud, targetLabel: target.label)
                self.recordingSession = session
                hud.onStop = { [weak self] in self?.stopRecording() }
                hud.onPause = { [weak self] in self?.togglePauseRecording() }
                hud.show(startedAt: recorder.startedAt ?? Date(), target: target.label)
                self.playSound("begin_record.caf")
                self.updateStatusMenu()
            case .failure(let error):
                hud.hide(after: 0)
                self.updateStatusMenu()
                self.handleRecordError(error)
            }
        }
    }

    private func togglePauseRecording() {
        guard let session = recordingSession, !session.stopping, !startingRecording else { return }
        if session.recorder.isPaused {
            session.recorder.resume()
            session.hud.setPaused(false)
        } else {
            session.recorder.pause()
            session.hud.setPaused(true)
        }
        updateStatusMenu()
    }

    private func stopRecording(interruptedBy error: Error? = nil) {
        guard let session = recordingSession, !session.stopping else { return }
        session.stopping = true
        session.hud.setSaving()
        updateStatusMenu()

        // UI safety net if the writer never invokes its completion handler.
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self, weak session] in
            guard let self, let session, self.recordingSession === session else { return }
            session.hud.setFailed()
            session.hud.hide(after: 1.5)
            self.recordingSession = nil
            self.updateStatusMenu()
            self.showError(title: "保存录屏失败", message: "保存过程超时，请检查磁盘空间后重试。")
        }

        session.recorder.stop { [weak self] result in
            guard let self else { return }
            self.recordingSession = nil
            session.hud.hide()
            self.updateStatusMenu()
            switch result {
            case .success(let url):
                if let error {
                    self.showError(
                        title: "录制已中断，但已保存",
                        message: "录制过程中出现问题：\(error.localizedDescription)\n已保存可播放的部分。"
                    )
                }
                self.presentResult(mode: .video(url: url), fresh: true, copied: false)
            case .failure(let stopError):
                if let error {
                    self.showError(title: "录制中断", message: "\(error.localizedDescription)\n\n\(stopError.localizedDescription)")
                } else {
                    self.handleRecordError(stopError)
                }
            }
        }
    }

    private func handleRecordError(_ error: Error) {
        if let glint = error as? GlintError, case .noPermission = glint {
            dashboard.refreshPermission()
            showPermissionAlert()
            return
        }
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        showError(title: "无法录制", message: message)
    }

    // MARK: - Result panel

    private func presentResult(mode: ResultPanelController.Mode, fresh: Bool, copied: Bool) {
        resultPanel?.close()
        let panel = ResultPanelController(mode: mode, isFreshCapture: fresh, copied: copied) { [weak self] in
            self?.resultPanel = nil
        }
        resultPanel = panel
        panel.show()
        dashboard.refreshRecentAndLibrary()
    }

    private func openRecent(_ item: CaptureItem) {
        guard FileManager.default.fileExists(atPath: item.url.path) else {
            showError(title: "文件不存在", message: "这个文件可能已经被移动或删除。")
            return
        }
        switch item.kind {
        case .image:
            presentResult(mode: .image(captured: nil, url: item.url), fresh: false, copied: false)
        case .video:
            presentResult(mode: .video(url: item.url), fresh: false, copied: false)
        }
    }

    // MARK: - Utilities

    private func screenUnderMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(location) }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func playSound(_ name: String) {
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/\(name)"
        guard let sound = NSSound(contentsOfFile: path, byReference: true) else { return }
        activeSound = sound
        sound.play()
    }

    private func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Menu actions

    @objc private func openDashboard() {
        dashboard.show()
    }

    @objc private func areaScreenshotAction() {
        beginAreaScreenshot()
    }

    @objc private func windowScreenshotAction() {
        beginWindowScreenshot()
    }

    @objc private func fullScreenshotAction() {
        captureFullScreen()
    }

    @objc private func recordAction() {
        showRecordChooser()
    }

    @objc private func pauseRecordingAction() {
        togglePauseRecording()
    }

    @objc private func stopRecordingAction() {
        stopRecording()
    }

    @objc private func scrollScreenshotAction() {
        beginScrollingCapture()
    }

    @objc private func openSettingsAction() {
        showSettings()
    }

    @objc private func checkForUpdatesAction() {
        UpdateChecker.shared.checkManually(presenting: NSApp.keyWindow)
    }

    @objc private func openImagesAction() {
        CaptureLibrary.shared.openFolder(CaptureLibrary.shared.imageDirectory)
    }

    @objc private func openVideosAction() {
        CaptureLibrary.shared.openFolder(CaptureLibrary.shared.videoDirectory)
    }

    @objc private func openPermissionSettings() {
        ScreenPermission.openSettings()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Main menu

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu

        let about = NSMenuItem(title: "关于 Glint", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(about)
        let preferences = NSMenuItem(title: "设置…", action: #selector(openSettingsAction), keyEquivalent: ",")
        preferences.keyEquivalentModifierMask = [.command]
        preferences.target = self
        appMenu.addItem(preferences)
        appMenu.addItem(.separator())

        let hide = NSMenuItem(title: "隐藏 Glint", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hide.keyEquivalentModifierMask = [.command]
        appMenu.addItem(hide)

        let hideOthers = NSMenuItem(title: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)

        let showAll = NSMenuItem(title: "全部显示", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(showAll)
        appMenu.addItem(.separator())

        let services = NSMenuItem(title: "服务", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu()
        services.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(services)
        appMenu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 Glint", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        appMenu.addItem(quit)

        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "文件")
        fileItem.submenu = fileMenu
        let close = NSMenuItem(title: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        close.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(close)

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "窗口")
        windowItem.submenu = windowMenu
        let minimize = NSMenuItem(title: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        minimize.keyEquivalentModifierMask = [.command]
        windowMenu.addItem(minimize)
        let zoom = NSMenuItem(title: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(zoom)
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "前置全部窗口", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }
}
