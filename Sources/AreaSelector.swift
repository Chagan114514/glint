import AppKit

final class AreaSelectorController: NSObject, NSWindowDelegate {
    enum Purpose {
        case screenshot
        case recording

        var accent: NSColor {
            switch self {
            case .screenshot: return Palette.accent
            case .recording: return Palette.danger
            }
        }

        var title: String {
            switch self {
            case .screenshot: return "拖动框选截图区域"
            case .recording: return "拖动框选录制区域"
            }
        }
    }

    struct Selection {
        let screen: NSScreen
        let rect: CGRect
    }

    private let purpose: Purpose
    private let completion: (Selection?) -> Void
    private var windows: [SelectionWindow] = []
    private var finished = false

    init(purpose: Purpose, completion: @escaping (Selection?) -> Void) {
        self.purpose = purpose
        self.completion = completion
        super.init()
    }

    func begin() {
        NSApp.activate(ignoringOtherApps: true)
        let mouseLocation = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main

        for screen in NSScreen.screens {
            let window = SelectionWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.setFrame(screen.frame, display: true)
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.acceptsMouseMovedEvents = true
            window.ignoresMouseEvents = false
            window.delegate = self

            let view = SelectionView(
                frame: NSRect(origin: .zero, size: screen.frame.size),
                controller: self,
                purpose: purpose,
                screen: screen
            )
            window.contentView = view
            window.makeFirstResponder(view)
            window.orderFrontRegardless()
            windows.append(window)
            if screen == activeScreen {
                window.makeKey()
            }
        }

        if let activeScreen, let index = NSScreen.screens.firstIndex(of: activeScreen), index < windows.count {
            windows[index].makeKey()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    fileprivate func complete(screen: NSScreen, rect: CGRect) {
        guard !finished else { return }
        finished = true
        dismiss()
        completion(Selection(screen: screen, rect: rect))
    }

    fileprivate func cancel() {
        guard !finished else { return }
        finished = true
        dismiss()
        completion(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if !finished {
            cancel()
        }
    }

    private func dismiss() {
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows.removeAll()
        NSCursor.arrow.set()
    }
}

private final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class SelectionView: NSView {
    private weak var controller: AreaSelectorController?
    private let purpose: AreaSelectorController.Purpose
    private let screen: NSScreen

    private var dragStart: NSPoint?
    private var currentPoint: NSPoint?
    private var selection: NSRect = .zero
    private var hasSelection = false

    init(frame: NSRect, controller: AreaSelectorController, purpose: AreaSelectorController.Purpose, screen: NSScreen) {
        self.controller = controller
        self.purpose = purpose
        self.screen = screen
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isFlipped: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            controller?.cancel()
            return
        }
        if event.keyCode == 36, hasSelection, selection.width >= 6, selection.height >= 6 {
            controller?.complete(screen: screen, rect: selection)
            return
        }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        currentPoint = point
        selection = .zero
        hasSelection = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let point = clampToBounds(convert(event.locationInWindow, from: nil))
        currentPoint = point
        selection = normalizedRect(from: start, to: point)
        hasSelection = selection.width >= 1 && selection.height >= 1
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = dragStart else { return }
        let point = clampToBounds(convert(event.locationInWindow, from: nil))
        let rect = normalizedRect(from: start, to: point).integral
        dragStart = nil

        if rect.width >= 6, rect.height >= 6 {
            controller?.complete(screen: screen, rect: rect)
        } else {
            controller?.cancel()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    private func clampToBounds(_ point: NSPoint) -> NSPoint {
        NSPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func normalizedRect(from a: NSPoint, to b: NSPoint) -> NSRect {
        NSRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        context.imageInterpolation = .high

        let dim = NSColor.black.withAlphaComponent(hasSelection ? 0.46 : 0.40)
        if hasSelection {
            drawDim(around: selection, color: dim)
        } else {
            dim.setFill()
            bounds.fill()
        }

        if hasSelection {
            drawSelectionChrome()
        } else {
            drawInstructions()
            if let currentPoint {
                drawCrosshair(at: currentPoint)
            }
        }

        context.restoreGraphicsState()
    }

    private func drawDim(around rect: NSRect, color: NSColor) {
        color.setFill()
        // Top strip.
        NSRect(x: 0, y: rect.maxY, width: bounds.width, height: max(0, bounds.maxY - rect.maxY)).fill()
        // Bottom strip.
        NSRect(x: 0, y: 0, width: bounds.width, height: max(0, rect.minY)).fill()
        // Left strip.
        NSRect(x: 0, y: rect.minY, width: max(0, rect.minX), height: rect.height).fill()
        // Right strip.
        NSRect(x: rect.maxX, y: rect.minY, width: max(0, bounds.maxX - rect.maxX), height: rect.height).fill()
    }

    private func drawSelectionChrome() {
        let rect = selection
        let accent = purpose.accent

        // Drop shadow just outside the selection.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow.shadowBlurRadius = 12
        shadow.shadowOffset = .zero
        shadow.set()
        NSColor.black.withAlphaComponent(0.001).setFill()
        NSBezierPath(rect: rect.insetBy(dx: -1, dy: -1)).fill()
        NSGraphicsContext.restoreGraphicsState()

        // Outer dark line then a bright accent line.
        NSColor.black.withAlphaComponent(0.75).setStroke()
        let outer = NSBezierPath(rect: rect.insetBy(dx: -0.75, dy: -0.75))
        outer.lineWidth = 2.5
        outer.stroke()

        accent.setStroke()
        let border = NSBezierPath(rect: rect.insetBy(dx: 0.75, dy: 0.75))
        border.lineWidth = 1.5
        border.stroke()

        // Corner handles.
        let handle: CGFloat = 7
        for point in [
            NSPoint(x: rect.minX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.minY),
            NSPoint(x: rect.minX, y: rect.maxY),
            NSPoint(x: rect.maxX, y: rect.maxY),
        ] {
            let handleRect = NSRect(x: point.x - handle / 2, y: point.y - handle / 2, width: handle, height: handle)
            let path = NSBezierPath(roundedRect: handleRect, xRadius: 2, yRadius: 2)
            accent.setFill()
            path.fill()
            NSColor.black.withAlphaComponent(0.35).setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        // Dimension badge.
        let scale = screen.backingScaleFactor
        let pxWidth = Int((rect.width * scale).rounded())
        let pxHeight = Int((rect.height * scale).rounded())
        let text = "\(pxWidth) × \(pxHeight) px"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.95),
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let badgeSize = NSSize(width: textSize.width + 18, height: 24)
        var badgeOrigin = NSPoint(x: rect.minX, y: rect.maxY + 9)
        if badgeOrigin.y + badgeSize.height > bounds.maxY - 8 {
            badgeOrigin.y = rect.maxY - badgeSize.height - 9
        }
        if badgeOrigin.x + badgeSize.width > bounds.maxX - 8 {
            badgeOrigin.x = bounds.maxX - badgeSize.width - 8
        }
        if badgeOrigin.x < 8 { badgeOrigin.x = 8 }

        let badgeRect = NSRect(origin: badgeOrigin, size: badgeSize)
        let badge = NSBezierPath(roundedRect: badgeRect, xRadius: 7, yRadius: 7)
        NSColor(hex: 0x10151C, alpha: 0.94).setFill()
        badge.fill()
        accent.withAlphaComponent(0.35).setStroke()
        badge.lineWidth = 1
        badge.stroke()
        (text as NSString).draw(
            at: NSPoint(x: badgeRect.minX + 9, y: badgeRect.minY + (badgeSize.height - textSize.height) / 2),
            withAttributes: attributes
        )

        // Hint under the badge.
        let hint = purpose == .recording ? "松开后开始录制" : "松开后立即截图"
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.68),
        ]
        let hintSize = (hint as NSString).size(withAttributes: hintAttrs)
        var hintPoint = NSPoint(x: badgeRect.minX, y: badgeRect.minY - hintSize.height - 5)
        if hintPoint.y < 8 {
            hintPoint.y = badgeRect.maxY + 5
        }
        (hint as NSString).draw(at: hintPoint, withAttributes: hintAttrs)
    }

    private func drawInstructions() {
        let title = purpose.title
        let subtitle = "ESC 取消  ·  按住拖动选择范围"
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.95),
        ]
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.50),
        ]
        let titleSize = (title as NSString).size(withAttributes: titleAttrs)
        let subtitleSize = (subtitle as NSString).size(withAttributes: subtitleAttrs)
        let width = max(titleSize.width, subtitleSize.width) + 36
        let height: CGFloat = 62
        let origin = NSPoint(x: bounds.midX - width / 2, y: bounds.maxY - height - 54)
        let card = NSRect(x: origin.x, y: origin.y, width: width, height: height)

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
        shadow.shadowBlurRadius = 22
        shadow.shadowOffset = NSSize(width: 0, height: -5)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor(hex: 0x10151C, alpha: 0.92).setFill()
        NSBezierPath(roundedRect: card, xRadius: 14, yRadius: 14).fill()
        NSGraphicsContext.restoreGraphicsState()

        purpose.accent.withAlphaComponent(0.36).setStroke()
        let border = NSBezierPath(roundedRect: card, xRadius: 14, yRadius: 14)
        border.lineWidth = 1
        border.stroke()

        (title as NSString).draw(
            at: NSPoint(x: card.midX - titleSize.width / 2, y: card.maxY - 16 - titleSize.height),
            withAttributes: titleAttrs
        )
        (subtitle as NSString).draw(
            at: NSPoint(x: card.midX - subtitleSize.width / 2, y: card.minY + 14),
            withAttributes: subtitleAttrs
        )
    }

    private func drawCrosshair(at point: NSPoint) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: point.x, y: 0))
        path.line(to: NSPoint(x: point.x, y: bounds.maxY))
        path.move(to: NSPoint(x: 0, y: point.y))
        path.line(to: NSPoint(x: bounds.maxX, y: point.y))
        NSColor.white.withAlphaComponent(0.16).setStroke()
        path.lineWidth = 1
        path.setLineDash([3, 5], count: 2, phase: 0)
        path.stroke()
    }
}
