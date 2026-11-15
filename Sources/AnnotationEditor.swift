import AppKit
import CoreImage
import ImageIO

enum AnnotationTool: Int, CaseIterable {
    case pen
    case arrow
    case rectangle
    case ellipse
    case text
    case crop
    case mosaic
}

struct Annotation {
    enum Shape {
        case path([CGPoint])
        case arrow(CGPoint, CGPoint)
        case rectangle(CGRect)
        case ellipse(CGRect)
        case text(CGPoint, String)
    }

    var shape: Shape
    var color: NSColor
    var width: CGFloat // normalized to image height
}

final class AnnotationCanvasView: NSView {
    private(set) var image: CGImage
    var tool: AnnotationTool = .pen
    var color: NSColor = Palette.danger
    var width: CGFloat = 0.008
    var onChanged: (() -> Void)?
    var onTextRequested: ((CGPoint) -> Void)?
    var onImageReplaced: ((URL) -> Void)?
    var onStatusChanged: ((String) -> Void)?

    private(set) var annotations: [Annotation] = []
    private var draft: Annotation?
    private var dragStart: CGPoint?
    private var imageSnapshots: [(CGImage, [Annotation])] = []
    private let canvasInset = NSSize(width: 24, height: 18)

    init(image: CGImage) {
        self.image = image
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor(hex: 0x070A0F).cgColor
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    private func imageRect(in rect: NSRect) -> NSRect {
        let available = rect.insetBy(dx: canvasInset.width, dy: canvasInset.height)
        guard available.width > 1, available.height > 1 else { return rect }
        let imageAspect = CGFloat(image.width) / CGFloat(max(1, image.height))
        let areaAspect = available.width / available.height
        var size = available.size
        if imageAspect > areaAspect {
            size.height = available.width / imageAspect
        } else {
            size.width = available.height * imageAspect
        }
        return NSRect(
            x: available.midX - size.width / 2,
            y: available.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func normalized(_ point: NSPoint, in imageRect: NSRect) -> CGPoint {
        CGPoint(
            x: min(max((point.x - imageRect.minX) / imageRect.width, 0), 1),
            y: min(max((point.y - imageRect.minY) / imageRect.height, 0), 1)
        )
    }

    private func viewPoint(_ normalized: CGPoint, in rect: NSRect) -> NSPoint {
        NSPoint(x: rect.minX + normalized.x * rect.width, y: rect.minY + normalized.y * rect.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = imageRect(in: bounds)
        NSColor(hex: 0x05080C).setFill()
        bounds.fill()
        NSGraphicsContext.saveGraphicsState()
        let clip = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        clip.addClip()
        NSImage(cgImage: image, size: rect.size).draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        for annotation in annotations {
            Self.draw(annotation, in: rect)
        }
        if let draft {
            if tool == .crop || tool == .mosaic, case .rectangle(let r) = draft.shape {
                drawSelectionOverlay(Self.viewRect(r, in: rect), mosaic: tool == .mosaic)
            } else {
                Self.draw(draft, in: rect)
            }
        }

        NSColor.white.withAlphaComponent(0.12).setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        border.lineWidth = 1
        border.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let rect = imageRect(in: bounds)
        guard rect.contains(point) else { return }
        let p = normalized(point, in: rect)

        if tool == .text {
            onTextRequested?(p)
            return
        }

        dragStart = p
        switch tool {
        case .pen:
            draft = Annotation(shape: .path([p]), color: color, width: width)
        case .arrow:
            draft = Annotation(shape: .arrow(p, p), color: color, width: width)
        case .rectangle:
            draft = Annotation(shape: .rectangle(CGRect(origin: p, size: .zero)), color: color, width: width)
        case .ellipse:
            draft = Annotation(shape: .ellipse(CGRect(origin: p, size: .zero)), color: color, width: width)
        case .crop, .mosaic:
            draft = Annotation(shape: .rectangle(CGRect(origin: p, size: .zero)), color: color, width: width)
        case .text:
            break
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        let rect = imageRect(in: bounds)
        let p = normalized(point, in: rect)

        switch draft?.shape {
        case .path(var points):
            points.append(p)
            draft?.shape = .path(points)
        case .arrow:
            draft?.shape = .arrow(start, p)
        case .rectangle:
            draft?.shape = .rectangle(Self.normalizedRect(start, p))
        case .ellipse:
            draft?.shape = .ellipse(Self.normalizedRect(start, p))
        default:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStart = nil
            draft = nil
            needsDisplay = true
        }
        guard let draft else { return }
        if (tool == .crop || tool == .mosaic), case .rectangle(let rect) = draft.shape {
            guard rect.width > 0.025, rect.height > 0.025 else {
                onStatusChanged?(tool == .crop ? "裁剪区域太小" : "马赛克区域太小")
                return
            }
            if tool == .crop {
                applyCrop(rect)
            } else {
                applyMosaic(rect)
            }
            return
        }
        if isMeaningful(draft) {
            annotations.append(draft)
            onChanged?()
        }
    }

    var canUndo: Bool { !annotations.isEmpty || !imageSnapshots.isEmpty }

    private func imageURL(from info: NSDraggingInfo) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] else { return nil }
        return urls.first
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let url = imageURL(from: sender),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else { return [] }
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        imageURL(from: sender) == nil ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = imageURL(from: sender),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let dropped = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return false }
        pushSnapshot()
        image = dropped
        annotations = []
        onImageReplaced?(url)
        onStatusChanged?("已载入 \(url.lastPathComponent)")
        onChanged?()
        needsDisplay = true
        return true
    }
    var hasEdits: Bool { !annotations.isEmpty || !imageSnapshots.isEmpty }

    func undo() {
        if let snapshot = imageSnapshots.popLast() {
            image = snapshot.0
            annotations = snapshot.1
            onChanged?()
            needsDisplay = true
            return
        }
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
        onChanged?()
        needsDisplay = true
    }

    private static func viewRect(_ normalized: CGRect, in rect: NSRect) -> NSRect {
        NSRect(
            x: rect.minX + normalized.minX * rect.width,
            y: rect.minY + normalized.minY * rect.height,
            width: normalized.width * rect.width,
            height: normalized.height * rect.height
        )
    }

    private func drawSelectionOverlay(_ selected: NSRect, mosaic: Bool) {
        guard selected.width > 0.5, selected.height > 0.5 else { return }
        NSColor.black.withAlphaComponent(0.48).setFill()
        let shade = NSBezierPath(rect: bounds)
        shade.append(NSBezierPath(rect: selected))
        shade.windingRule = .evenOdd
        shade.fill()

        if mosaic {
            NSColor.white.withAlphaComponent(0.14).setFill()
            let block: CGFloat = 9
            var y = selected.minY
            while y < selected.maxY {
                var x = selected.minX
                while x < selected.maxX {
                    if Int((x - selected.minX) / block + (y - selected.minY) / block) % 2 == 0 {
                        NSBezierPath(rect: NSRect(x: x, y: y, width: min(block, selected.maxX - x), height: min(block, selected.maxY - y))).fill()
                    }
                    x += block
                }
                y += block
            }
        }

        Palette.accent.setStroke()
        let border = NSBezierPath(rect: selected)
        border.lineWidth = 1.4
        let pattern: [CGFloat] = [5, 3]
        border.setLineDash(pattern, count: pattern.count, phase: 0)
        border.stroke()
    }

    private func pushSnapshot() {
        imageSnapshots.append((image, annotations))
        if imageSnapshots.count > 10 { imageSnapshots.removeFirst() }
    }

    private func applyCrop(_ normalizedRect: CGRect) {
        let sourceWidth = CGFloat(image.width)
        let sourceHeight = CGFloat(image.height)
        let pixelRect = CGRect(
            x: floor(normalizedRect.minX * sourceWidth),
            y: floor((1 - normalizedRect.maxY) * sourceHeight),
            width: max(1, floor(normalizedRect.width * sourceWidth)),
            height: max(1, floor(normalizedRect.height * sourceHeight))
        ).integral
        guard pixelRect.width >= 8, pixelRect.height >= 8,
              let cropped = image.cropping(to: pixelRect) else { return }
        pushSnapshot()
        image = cropped

        let map: (CGPoint) -> CGPoint = { point in
            CGPoint(
                x: (point.x - normalizedRect.minX) / normalizedRect.width,
                y: (point.y - normalizedRect.minY) / normalizedRect.height
            )
        }
        annotations = annotations.compactMap { annotation in
            switch annotation.shape {
            case .path(let points):
                let mapped = points.map(map)
                return Annotation(shape: .path(mapped), color: annotation.color, width: annotation.width)
            case .arrow(let start, let end):
                return Annotation(shape: .arrow(map(start), map(end)), color: annotation.color, width: annotation.width)
            case .rectangle(let rect):
                let a = map(rect.origin)
                let b = map(CGPoint(x: rect.maxX, y: rect.maxY))
                let mapped = Self.normalizedRect(a, b)
                return mapped.width > 0.01 && mapped.height > 0.01
                    ? Annotation(shape: .rectangle(mapped), color: annotation.color, width: annotation.width)
                    : nil
            case .ellipse(let rect):
                let a = map(rect.origin)
                let b = map(CGPoint(x: rect.maxX, y: rect.maxY))
                let mapped = Self.normalizedRect(a, b)
                return mapped.width > 0.01 && mapped.height > 0.01
                    ? Annotation(shape: .ellipse(mapped), color: annotation.color, width: annotation.width)
                    : nil
            case .text(let point, let text):
                return Annotation(shape: .text(map(point), text), color: annotation.color, width: annotation.width)
            }
        }
        onStatusChanged?("已裁剪为 \(Int(cropped.width)) × \(Int(cropped.height)) px")
        onChanged?()
        needsDisplay = true
    }

    private func applyMosaic(_ normalizedRect: CGRect) {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return }

        let pixelRect = CGRect(
            x: floor(normalizedRect.minX * CGFloat(width)),
            y: floor(normalizedRect.minY * CGFloat(height)),
            width: max(2, floor(normalizedRect.width * CGFloat(width))),
            height: max(2, floor(normalizedRect.height * CGFloat(height)))
        ).integral
        guard pixelRect.width >= 2, pixelRect.height >= 2 else { return }

        let source = CIImage(cgImage: image)
        let block = max(8, min(24, Int(pixelRect.width / 18)))
        guard let filter = CIFilter(name: "CIPixellate") else { return }
        filter.setValue(source.cropped(to: pixelRect), forKey: kCIInputImageKey)
        filter.setValue(block, forKey: kCIInputScaleKey)
        guard let pixelated = filter.outputImage?.cropped(to: pixelRect) else { return }

        let composite = pixelated.composited(over: source)
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])
        guard let output = ciContext.createCGImage(composite, from: source.extent) else { return }
        pushSnapshot()
        image = output
        onStatusChanged?("已添加马赛克")
        onChanged?()
        needsDisplay = true
    }

    private func isMeaningful(_ annotation: Annotation) -> Bool {
        switch annotation.shape {
        case .path(let points):
            return points.count > 2
        case .arrow(let start, let end):
            return hypot(end.x - start.x, end.y - start.y) > 0.006
        case .rectangle(let rect), .ellipse(let rect):
            return rect.width > 0.006 && rect.height > 0.006
        case .text:
            return true
        }
    }

    func addText(_ text: String, at point: CGPoint) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        annotations.append(Annotation(shape: .text(point, value), color: color, width: width))
        onChanged?()
        needsDisplay = true
    }

    func clear() {
        guard !annotations.isEmpty else { return }
        annotations.removeAll()
        onChanged?()
        needsDisplay = true
    }

    var hasAnnotations: Bool { !annotations.isEmpty }

    func renderFullResolution() -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              ) else { return nil }

        rep.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = context
        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        NSImage(cgImage: image, size: rect.size).draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        for annotation in annotations {
            Self.draw(annotation, in: rect)
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }

    private static func normalizedRect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
    }

    private static func draw(_ annotation: Annotation, in imageRect: NSRect) {
        let color = annotation.color
        let lineWidth = max(1, annotation.width * imageRect.height)
        color.setStroke()
        color.setFill()

        switch annotation.shape {
        case .path(let points):
            guard let first = points.first else { return }
            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: NSPoint(x: imageRect.minX + first.x * imageRect.width, y: imageRect.minY + first.y * imageRect.height))
            for p in points.dropFirst() {
                path.line(to: NSPoint(x: imageRect.minX + p.x * imageRect.width, y: imageRect.minY + p.y * imageRect.height))
            }
            path.stroke()

        case .arrow(let start, let end):
            let a = NSPoint(x: imageRect.minX + start.x * imageRect.width, y: imageRect.minY + start.y * imageRect.height)
            let b = NSPoint(x: imageRect.minX + end.x * imageRect.width, y: imageRect.minY + end.y * imageRect.height)
            let line = NSBezierPath()
            line.lineWidth = lineWidth
            line.lineCapStyle = .round
            line.move(to: a)
            line.line(to: b)
            line.stroke()

            let angle = atan2(b.y - a.y, b.x - a.x)
            let head = max(7, lineWidth * 3.2)
            let left = NSPoint(x: b.x - head * cos(angle - .pi / 6), y: b.y - head * sin(angle - .pi / 6))
            let right = NSPoint(x: b.x - head * cos(angle + .pi / 6), y: b.y - head * sin(angle + .pi / 6))
            let headPath = NSBezierPath()
            headPath.lineWidth = lineWidth
            headPath.lineCapStyle = .round
            headPath.move(to: left)
            headPath.line(to: b)
            headPath.line(to: right)
            headPath.stroke()

        case .rectangle(let rect):
            let r = NSRect(
                x: imageRect.minX + rect.minX * imageRect.width,
                y: imageRect.minY + rect.minY * imageRect.height,
                width: rect.width * imageRect.width,
                height: rect.height * imageRect.height
            )
            let path = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
            path.lineWidth = lineWidth
            color.withAlphaComponent(0.07).setFill()
            path.fill()
            color.setStroke()
            path.stroke()

        case .ellipse(let rect):
            let r = NSRect(
                x: imageRect.minX + rect.minX * imageRect.width,
                y: imageRect.minY + rect.minY * imageRect.height,
                width: rect.width * imageRect.width,
                height: rect.height * imageRect.height
            )
            let path = NSBezierPath(ovalIn: r)
            path.lineWidth = lineWidth
            color.withAlphaComponent(0.07).setFill()
            path.fill()
            color.setStroke()
            path.stroke()

        case .text(let point, let text):
            let fontSize = max(12, imageRect.height * 0.034)
            let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
            shadow.shadowBlurRadius = max(2, fontSize * 0.08)
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .shadow: shadow,
            ]
            let origin = NSPoint(
                x: imageRect.minX + point.x * imageRect.width,
                y: imageRect.minY + point.y * imageRect.height
            )
            (text as NSString).draw(at: origin, withAttributes: attrs)
        }
    }
}

// MARK: - Editor

final class AnnotationEditorController: NSObject, NSWindowDelegate {
    private var sourceURL: URL
    private let sourceImage: CGImage
    private var scale: CGFloat
    private let panel: AnnotationPanel
    private let canvas: AnnotationCanvasView
    private let toolbar = NSView()
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let toolControl = NSSegmentedControl(labels: ["画笔", "箭头", "矩形", "椭圆", "文字", "裁剪", "马赛克"], trackingMode: .selectOne, target: nil, action: nil)
    private let widthControl = NSSegmentedControl(labels: ["细", "中", "粗"], trackingMode: .selectOne, target: nil, action: nil)
    private let undoButton = GlintIconButton(symbol: "arrow.uturn.backward", size: 12)
    private let clearButton = GlintIconButton(symbol: "trash", size: 12)
    private let saveButton = GlintButton(title: "保存副本", style: .primary)
    private let copyButton = GlintButton(title: "复制", style: .secondary)
    private let revealButton = GlintIconButton(symbol: "folder", size: 12)
    private let statusLabel = NSTextField(labelWithString: "选择工具后，在图片上拖拽绘制")
    private var swatches: [ColorSwatchButton] = []
    private var keyMonitor: Any?
    private var savedURL: URL?
    private var closed = false
    private let onClose: (() -> Void)?

    init(sourceURL: URL, image: CGImage, scale: CGFloat, onClose: (() -> Void)? = nil) {
        self.sourceURL = sourceURL
        self.sourceImage = image
        self.scale = scale
        self.onClose = onClose
        self.canvas = AnnotationCanvasView(image: image)
        panel = AnnotationPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 760),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
        buildUI()
        wireActions()
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
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {
                self.closeTapped()
                return nil
            }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "z" {
                self.undoTapped()
                return nil
            }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "s" {
                self.saveTapped()
                return nil
            }
            if !(self.panel.firstResponder is NSTextView),
               event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                let key = event.charactersIgnoringModifiers?.lowercased()
                if key == "p" { self.selectTool(0); return nil }
                if key == "a" { self.selectTool(1); return nil }
                if key == "r" { self.selectTool(2); return nil }
                if key == "e" { self.selectTool(3); return nil }
                if key == "t" { self.selectTool(4); return nil }
                if key == "c" { self.selectTool(5); return nil }
                if key == "m" { self.selectTool(6); return nil }
                switch event.keyCode {
                case 8: self.selectTool(5); return nil
                case 46: self.selectTool(6); return nil
                default: break
                }
            }
            return event
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
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.minSize = NSSize(width: 980, height: 520)
        panel.delegate = self
    }

    private func buildUI() {
        let root = AnnotationSurfaceView(frame: NSRect(x: 0, y: 0, width: 1040, height: 760))
        root.wantsLayer = true
        root.layer?.cornerRadius = 20
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = root

        let icon = makeSymbol("pencil.tip", size: 15, weight: .semibold, color: Palette.accent)
        root.addSubview(icon)
        let title = makeLabel("批注截图", size: 19, weight: .semibold, color: Palette.text)
        root.addSubview(title)
        subtitleLabel.stringValue = "\(sourceURL.lastPathComponent) · 保存为副本，不覆盖原图"
        subtitleLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        subtitleLabel.textColor = Palette.textSecondary
        subtitleLabel.lineBreakMode = .byTruncatingMiddle
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(subtitleLabel)
        let close = GlintIconButton(symbol: "xmark", size: 12, target: self, action: #selector(closeTapped))
        root.addSubview(close)

        canvas.onChanged = { [weak self] in self?.refreshActions() }
        canvas.onTextRequested = { [weak self] point in self?.requestText(at: point) }
        canvas.onImageReplaced = { [weak self] url in self?.imageReplaced(url) }
        canvas.onStatusChanged = { [weak self] message in self?.showStatus(message, success: true) }
        root.addSubview(canvas)

        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor(hex: 0x121A23).cgColor
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(toolbar)

        toolControl.selectedSegment = 0
        toolControl.controlSize = .small
        toolControl.segmentStyle = .rounded
        toolControl.target = self
        toolControl.action = #selector(toolChanged)
        toolControl.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(toolControl)

        let colorNames: [(String, NSColor)] = [
            ("红", Palette.danger),
            ("橙", Palette.accent),
            ("绿", Palette.success),
            ("蓝", NSColor(hex: 0x62A8FF)),
            ("白", .white),
            ("黑", NSColor(hex: 0x111111)),
        ]
        let swatchStack = NSStackView()
        swatchStack.orientation = .horizontal
        swatchStack.spacing = 7
        swatchStack.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(swatchStack)
        for (index, (name, color)) in colorNames.enumerated() {
            let swatch = ColorSwatchButton(color: color)
            swatch.toolTip = name
            swatch.isSelected = index == 0
            swatch.onClick = { [weak self, weak swatch] in
                guard let self, let swatch else { return }
                self.swatches.forEach { $0.isSelected = false }
                swatch.isSelected = true
                self.canvas.color = color
            }
            swatches.append(swatch)
            swatchStack.addArrangedSubview(swatch)
        }

        widthControl.selectedSegment = 1
        widthControl.controlSize = .small
        widthControl.segmentStyle = .rounded
        widthControl.target = self
        widthControl.action = #selector(widthChanged)
        widthControl.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(widthControl)

        undoButton.target = self
        undoButton.action = #selector(undoTapped)
        undoButton.toolTip = "撤销 (⌘Z)"
        toolbar.addSubview(undoButton)

        clearButton.target = self
        clearButton.action = #selector(clearTapped)
        clearButton.toolTip = "清除全部批注"
        toolbar.addSubview(clearButton)

        statusLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .regular)
        statusLabel.textColor = Palette.textTertiary
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(statusLabel)

        saveButton.target = self
        saveButton.action = #selector(saveTapped)
        saveButton.setSymbol("square.and.arrow.down")
        toolbar.addSubview(saveButton)

        copyButton.target = self
        copyButton.action = #selector(copyTapped)
        copyButton.setSymbol("doc.on.doc")
        toolbar.addSubview(copyButton)

        revealButton.target = self
        revealButton.action = #selector(revealTapped)
        revealButton.toolTip = "在 Finder 中显示"
        revealButton.isHidden = true
        toolbar.addSubview(revealButton)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            icon.topAnchor.constraint(equalTo: root.topAnchor, constant: 25),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 19),
            subtitleLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 1),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: close.leadingAnchor, constant: -8),
            close.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            close.topAnchor.constraint(equalTo: root.topAnchor, constant: 17),
            close.widthAnchor.constraint(equalToConstant: 28),
            close.heightAnchor.constraint(equalToConstant: 28),

            canvas.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            canvas.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            canvas.topAnchor.constraint(equalTo: root.topAnchor, constant: 66),
            canvas.bottomAnchor.constraint(equalTo: toolbar.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 64),

            toolControl.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 18),
            toolControl.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            toolControl.widthAnchor.constraint(equalToConstant: 356),
            toolControl.heightAnchor.constraint(equalToConstant: 26),

            swatchStack.leadingAnchor.constraint(equalTo: toolControl.trailingAnchor, constant: 12),
            swatchStack.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            swatchStack.widthAnchor.constraint(equalToConstant: 6 * 22 + 5 * 7),

            widthControl.leadingAnchor.constraint(equalTo: swatchStack.trailingAnchor, constant: 12),
            widthControl.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            widthControl.widthAnchor.constraint(equalToConstant: 104),
            widthControl.heightAnchor.constraint(equalToConstant: 26),

            undoButton.leadingAnchor.constraint(equalTo: widthControl.trailingAnchor, constant: 8),
            undoButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            undoButton.widthAnchor.constraint(equalToConstant: 28),
            undoButton.heightAnchor.constraint(equalToConstant: 28),
            clearButton.leadingAnchor.constraint(equalTo: undoButton.trailingAnchor, constant: 2),
            clearButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 28),
            clearButton.heightAnchor.constraint(equalToConstant: 28),

            copyButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -8),
            copyButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            copyButton.widthAnchor.constraint(equalToConstant: 74),
            copyButton.heightAnchor.constraint(equalToConstant: 30),
            saveButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -18),
            saveButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            saveButton.widthAnchor.constraint(equalToConstant: 96),
            saveButton.heightAnchor.constraint(equalToConstant: 30),
            revealButton.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -6),
            revealButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            revealButton.widthAnchor.constraint(equalToConstant: 28),
            revealButton.heightAnchor.constraint(equalToConstant: 28),

            statusLabel.leadingAnchor.constraint(equalTo: clearButton.trailingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: revealButton.leadingAnchor, constant: -8),
            statusLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
        ])
        refreshActions()
    }

    private func wireActions() {
        toolControl.target = self
        toolControl.action = #selector(toolChanged)
        widthControl.target = self
        widthControl.action = #selector(widthChanged)
    }

    private func refreshActions() {
        undoButton.isEnabled = canvas.canUndo
        undoButton.alphaValue = canvas.canUndo ? 1 : 0.4
        clearButton.isEnabled = !canvas.annotations.isEmpty
        clearButton.alphaValue = !canvas.annotations.isEmpty ? 1 : 0.4
        saveButton.isEnabled = true
        saveButton.alphaValue = 1
        copyButton.isEnabled = true
        copyButton.alphaValue = 1
    }

    private func imageReplaced(_ url: URL) {
        sourceURL = url
        scale = 1
        subtitleLabel.stringValue = "\(url.lastPathComponent) · 拖入新图片 · 保存为副本"
        savedURL = nil
        revealButton.isHidden = true
        refreshActions()
    }

    private func showStatus(_ message: String, success: Bool) {
        statusLabel.stringValue = message
        statusLabel.textColor = success ? Palette.success : Palette.danger
    }

    private func requestText(at point: CGPoint) {
        let alert = NSAlert()
        alert.messageText = "添加文字批注"
        alert.informativeText = "输入要放在截图上的文字。"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = "输入文字…"
        alert.accessoryView = field
        alert.addButton(withTitle: "添加")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            canvas.addText(field.stringValue, at: point)
        }
    }

    private func selectTool(_ index: Int) {
        toolControl.selectedSegment = index
        toolChanged()
    }

    @objc private func toolChanged() {
        guard let tool = AnnotationTool(rawValue: toolControl.selectedSegment) else { return }
        canvas.tool = tool
        switch tool {
        case .crop:
            statusLabel.stringValue = "拖拽选择裁剪区域，松开后立即裁剪"
        case .mosaic:
            statusLabel.stringValue = "拖拽选择马赛克区域，松开后立即应用"
        case .text:
            statusLabel.stringValue = "点击图片位置，输入文字"
        default:
            statusLabel.stringValue = "选择工具后，在图片上拖拽绘制"
        }
        windowFirstResponder()
    }

    private func windowFirstResponder() {
        panel.makeFirstResponder(canvas)
    }

    @objc private func widthChanged() {
        let widths: [CGFloat] = [0.004, 0.008, 0.014]
        let index = max(0, min(2, widthControl.selectedSegment))
        canvas.width = widths[index]
    }

    @objc private func undoTapped() {
        canvas.undo()
        refreshActions()
    }

    @objc private func clearTapped() {
        canvas.clear()
        refreshActions()
    }

    @objc private func saveTapped() {
        guard let rendered = canvas.renderFullResolution() else { return }
        let destination = CaptureLibrary.shared.annotatedURL(for: sourceURL)
        do {
            try CaptureLibrary.shared.writePNG(rendered, scale: scale, to: destination)
            NotificationCenter.default.post(name: CaptureLibrary.libraryChanged, object: nil)
            savedURL = destination
            showStatus("已保存副本：\(destination.lastPathComponent)", success: true)
            revealButton.isHidden = false
            flash(saveButton)
        } catch {
            showStatus("保存失败：\(error.localizedDescription)", success: false)
        }
    }

    @objc private func copyTapped() {
        guard let rendered = canvas.renderFullResolution() else { return }
        let captured = CapturedImage(cgImage: rendered, scale: scale, label: "批注截图")
        if CaptureLibrary.shared.copyToPasteboard(captured) {
            showStatus("批注图片已复制到剪贴板", success: true)
            flash(copyButton)
        }
    }

    @objc private func revealTapped() {
        guard let savedURL else { return }
        CaptureLibrary.shared.reveal(savedURL)
    }

    @objc private func closeTapped() {
        if canvas.hasAnnotations && savedURL == nil {
            let alert = NSAlert()
            alert.messageText = "放弃未保存的批注？"
            alert.informativeText = "当前批注尚未保存副本。"
            alert.addButton(withTitle: "放弃")
            alert.addButton(withTitle: "继续编辑")
            if alert.runModal() == .alertSecondButtonReturn { return }
        }
        close()
    }

    func close() {
        guard !closed else { return }
        closed = true
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        panel.orderOut(nil)
        onClose?()
    }

    func windowWillClose(_ notification: Notification) {
        close()
    }
}

private final class AnnotationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class AnnotationSurfaceView: NSView {
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

private final class ColorSwatchButton: NSButton {
    let color: NSColor
    var isSelected = false {
        didSet { needsDisplay = true }
    }
    var onClick: (() -> Void)?
    private var hovered = false
    private var tracking: NSTrackingArea?

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        isTransparent = true
        focusRingType = .none
        let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
        addGestureRecognizer(click)
        widthAnchor.constraint(equalToConstant: 22).isActive = true
        heightAnchor.constraint(equalToConstant: 22).isActive = true
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    @objc private func clicked() { onClick?() }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 3, dy: 3)
        let circle = NSBezierPath(ovalIn: rect)
        color.setFill()
        circle.fill()
        if isSelected {
            NSColor.white.withAlphaComponent(0.95).setStroke()
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: -2.5, dy: -2.5))
            ring.lineWidth = 2
            ring.stroke()
        } else if hovered {
            NSColor.white.withAlphaComponent(0.35).setStroke()
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: -2, dy: -2))
            ring.lineWidth = 1
            ring.stroke()
        }
    }
}
