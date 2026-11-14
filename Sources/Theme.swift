import AppKit

// MARK: - Palette

enum Palette {
    static let background = NSColor(hex: 0x0B0F14)
    static let backgroundLift = NSColor(hex: 0x111821)
    static let surface = NSColor(hex: 0x151D27)
    static let surfaceHover = NSColor(hex: 0x1B2531)
    static let stroke = NSColor.white.withAlphaComponent(0.08)
    static let strokeStrong = NSColor.white.withAlphaComponent(0.14)

    static let accent = NSColor(hex: 0xFFC66D)
    static let accentDeep = NSColor(hex: 0xFF9F43)
    static let accentSoft = NSColor(hex: 0xFFD99A)
    static let teal = NSColor(hex: 0x62E3C8)
    static let danger = NSColor(hex: 0xFF5D5D)
    static let success = NSColor(hex: 0x6EE7B7)

    static let text = NSColor.white.withAlphaComponent(0.95)
    static let textSecondary = NSColor.white.withAlphaComponent(0.56)
    static let textTertiary = NSColor.white.withAlphaComponent(0.34)
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}

// MARK: - Typography

enum Type {
    static func display(_ size: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .bold)
    }

    static func title(_ size: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .semibold)
    }

    static func body(_ size: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .regular)
    }

    static func medium(_ size: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .medium)
    }

    static func mono(_ size: CGFloat) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
    }
}

func makeLabel(
    _ text: String,
    size: CGFloat,
    weight: NSFont.Weight = .regular,
    color: NSColor = Palette.text,
    alignment: NSTextAlignment = .left,
    lines: Int = 1
) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = NSFont.systemFont(ofSize: size, weight: weight)
    field.textColor = color
    field.alignment = alignment
    field.maximumNumberOfLines = lines
    field.lineBreakMode = lines > 1 ? .byTruncatingTail : .byTruncatingTail
    field.translatesAutoresizingMaskIntoConstraints = false
    return field
}

func makeSymbol(
    _ name: String,
    size: CGFloat,
    weight: NSFont.Weight = .semibold,
    color: NSColor = Palette.text
) -> NSImageView {
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
    let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(config)
    let view = NSImageView(image: image ?? NSImage())
    view.contentTintColor = color
    view.imageScaling = .scaleProportionallyUpOrDown
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
}

// MARK: - Views

/// A subtle rounded panel used throughout the dashboard.
final class GlintCardView: NSView {
    var fillColor: NSColor = Palette.surface { didSet { layer?.backgroundColor = fillColor.cgColor } }
    var borderColor: NSColor = Palette.stroke { didSet { layer?.borderColor = borderColor.cgColor } }
    var cornerRadius: CGFloat = 16 { didSet { layer?.cornerRadius = cornerRadius } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = fillColor.cgColor
        layer?.borderColor = borderColor.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { nil }
}

final class LogoView: NSView {
    var size: CGFloat = 48

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { NSSize(width: size, height: size) }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.27, yRadius: rect.width * 0.27)

        let gradient = NSGradient(colors: [NSColor(hex: 0xFFE7AD), NSColor(hex: 0xFFB259), NSColor(hex: 0xFF8A3D)])!
        gradient.draw(in: path, angle: -55)

        // Soft inner highlight.
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let shine = NSGradient(colors: [NSColor.white.withAlphaComponent(0.34), NSColor.white.withAlphaComponent(0)])
        shine?.draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: 90)
        NSGraphicsContext.restoreGraphicsState()

        // Capture brackets.
        let bracket = NSBezierPath()
        let inset: CGFloat = rect.width * 0.28
        let inner = rect.insetBy(dx: inset, dy: inset * 1.12)
        let arm = inner.width * 0.34
        let radius: CGFloat = rect.width * 0.055
        let color = NSColor(hex: 0x3A2410)
        color.setStroke()
        bracket.lineWidth = max(2.2, rect.width * 0.055)
        bracket.lineCapStyle = .round
        bracket.lineJoinStyle = .round

        bracket.move(to: NSPoint(x: inner.minX, y: inner.minY + arm))
        bracket.line(to: NSPoint(x: inner.minX, y: inner.minY + radius))
        bracket.appendArc(withCenter: NSPoint(x: inner.minX + radius, y: inner.minY + radius), radius: radius, startAngle: 180, endAngle: 270)
        bracket.line(to: NSPoint(x: inner.minX + arm, y: inner.minY))

        bracket.move(to: NSPoint(x: inner.maxX - arm, y: inner.minY))
        bracket.line(to: NSPoint(x: inner.maxX - radius, y: inner.minY))
        bracket.appendArc(withCenter: NSPoint(x: inner.maxX - radius, y: inner.minY + radius), radius: radius, startAngle: 270, endAngle: 360)
        bracket.line(to: NSPoint(x: inner.maxX, y: inner.minY + arm))

        bracket.move(to: NSPoint(x: inner.maxX, y: inner.maxY - arm))
        bracket.line(to: NSPoint(x: inner.maxX, y: inner.maxY - radius))
        bracket.appendArc(withCenter: NSPoint(x: inner.maxX - radius, y: inner.maxY - radius), radius: radius, startAngle: 0, endAngle: 90)
        bracket.line(to: NSPoint(x: inner.maxX - arm, y: inner.maxY))

        bracket.move(to: NSPoint(x: inner.minX + arm, y: inner.maxY))
        bracket.line(to: NSPoint(x: inner.minX + radius, y: inner.maxY))
        bracket.appendArc(withCenter: NSPoint(x: inner.minX + radius, y: inner.maxY - radius), radius: radius, startAngle: 90, endAngle: 180)
        bracket.line(to: NSPoint(x: inner.minX, y: inner.maxY - arm))

        bracket.stroke()

        // Sparkle in the middle.
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let sparkle = NSBezierPath()
        let r = rect.width * 0.15
        let q = r * 0.23
        sparkle.move(to: NSPoint(x: center.x, y: center.y + r))
        sparkle.curve(to: NSPoint(x: center.x + r, y: center.y), controlPoint1: NSPoint(x: center.x + q, y: center.y + q), controlPoint2: NSPoint(x: center.x + q, y: center.y + q))
        sparkle.curve(to: NSPoint(x: center.x, y: center.y - r), controlPoint1: NSPoint(x: center.x + q, y: center.y - q), controlPoint2: NSPoint(x: center.x + q, y: center.y - q))
        sparkle.curve(to: NSPoint(x: center.x - r, y: center.y), controlPoint1: NSPoint(x: center.x - q, y: center.y - q), controlPoint2: NSPoint(x: center.x - q, y: center.y - q))
        sparkle.curve(to: NSPoint(x: center.x, y: center.y + r), controlPoint1: NSPoint(x: center.x - q, y: center.y + q), controlPoint2: NSPoint(x: center.x - q, y: center.y + q))
        color.setFill()
        sparkle.fill()
    }
}

// MARK: - Buttons

final class GlintButton: NSButton {
    enum Style {
        case primary
        case secondary
        case ghost
        case danger

        var fill: NSColor {
            switch self {
            case .primary: return Palette.accent
            case .secondary: return NSColor.white.withAlphaComponent(0.07)
            case .ghost: return .clear
            case .danger: return Palette.danger.withAlphaComponent(0.16)
            }
        }

        var hoverFill: NSColor {
            switch self {
            case .primary: return NSColor(hex: 0xFFD28B)
            case .secondary: return NSColor.white.withAlphaComponent(0.12)
            case .ghost: return NSColor.white.withAlphaComponent(0.07)
            case .danger: return Palette.danger.withAlphaComponent(0.26)
            }
        }

        var foreground: NSColor {
            switch self {
            case .primary: return NSColor(hex: 0x2B1B06)
            case .secondary: return Palette.text
            case .ghost: return Palette.textSecondary
            case .danger: return Palette.danger
            }
        }

        var border: NSColor {
            switch self {
            case .primary: return .clear
            case .secondary: return NSColor.white.withAlphaComponent(0.10)
            case .ghost: return .clear
            case .danger: return Palette.danger.withAlphaComponent(0.24)
            }
        }
    }

    private(set) var style: Style
    private var hovered = false
    private var pressed = false
    private var tracking: NSTrackingArea?

    init(title: String, style: Style, target: AnyObject? = nil, action: Selector? = nil) {
        self.style = style
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        isTransparent = true
        font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { nil }

    func setSymbol(_ name: String) {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        image?.isTemplate = true
    }

    override var intrinsicContentSize: NSSize {
        let textWidth = (title as NSString).size(withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 12.5)]).width
        let imageWidth: CGFloat = image == nil ? 0 : 20
        return NSSize(width: textWidth + imageWidth + 26, height: 32)
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
        NSCursor.pointingHand.set()
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        needsDisplay = true
        super.mouseDown(with: event)
        pressed = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        let background = pressed ? style.hoverFill.blended(withFraction: 0.12, of: .black) ?? style.hoverFill : (hovered ? style.hoverFill : style.fill)
        background.setFill()
        path.fill()

        if style.border.alphaComponent > 0 {
            style.border.setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        let foreground = style.foreground
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 12.5, weight: .semibold),
            .foregroundColor: foreground,
        ]
        let titleSize = (title as NSString).size(withAttributes: attributes)
        let imageSize = image == nil ? NSSize.zero : NSSize(width: 15, height: 15)
        let gap: CGFloat = image == nil ? 0 : 6
        let totalWidth = imageSize.width + gap + titleSize.width
        var x = bounds.midX - totalWidth / 2
        let y = bounds.midY - titleSize.height / 2

        if let image {
            let colored = image.tinted(with: foreground)
            colored?.draw(
                in: NSRect(x: x, y: bounds.midY - imageSize.height / 2, width: imageSize.width, height: imageSize.height),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
            x += imageSize.width + gap
        }

        (title as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
    }
}

final class GlintIconButton: NSButton {
    private var hovered = false
    private var tracking: NSTrackingArea?
    var tint: NSColor = Palette.textSecondary

    init(symbol: String, size: CGFloat = 13, target: AnyObject? = nil, action: Selector? = nil) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        isTransparent = true
        imagePosition = .imageOnly
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol)?.withSymbolConfiguration(config)
        image?.isTemplate = true
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityRole(.button)
        setAccessibilityLabel(symbol)
    }

    required init?(coder: NSCoder) { nil }

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

    override func draw(_ dirtyRect: NSRect) {
        if hovered {
            NSColor.white.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        }
        if let image {
            let targetRect = NSRect(
                x: bounds.midX - image.size.width / 2,
                y: bounds.midY - image.size.height / 2,
                width: image.size.width,
                height: image.size.height
            )
            let colored = image.tinted(with: hovered ? Palette.text : tint)
            colored?.draw(in: targetRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }
}

// MARK: - Helpers

extension NSImage {
    func tinted(with color: NSColor) -> NSImage? {
        guard let copy = self.copy() as? NSImage else { return nil }
        copy.lockFocus()
        color.set()
        NSRect(origin: .zero, size: copy.size).fill(using: .sourceAtop)
        copy.unlockFocus()
        copy.isTemplate = false
        return copy
    }

    func roundedThumbnail(size target: NSSize, radius: CGFloat = 8) -> NSImage {
        let result = NSImage(size: target)
        result.lockFocus()
        let rect = NSRect(origin: .zero, size: target)
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
        let sourceAspect = self.size.width / max(1, self.size.height)
        let targetAspect = target.width / max(1, target.height)
        var drawRect = rect
        if sourceAspect > targetAspect {
            drawRect.size.width = target.height * sourceAspect
            drawRect.origin.x = (target.width - drawRect.width) / 2
        } else {
            drawRect.size.height = target.width / sourceAspect
            drawRect.origin.y = (target.height - drawRect.height) / 2
        }
        draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
        result.unlockFocus()
        return result
    }
}

func formatShortcut(_ keys: String) -> String {
    keys.replacingOccurrences(of: "cmd", with: "⌘")
        .replacingOccurrences(of: "shift", with: "⇧")
        .replacingOccurrences(of: "opt", with: "⌥")
        .replacingOccurrences(of: "ctrl", with: "⌃")
}

func flash(_ view: NSView) {
    view.wantsLayer = true
    let animation = CAKeyframeAnimation(keyPath: "opacity")
    animation.values = [1.0, 0.55, 1.0]
    animation.duration = 0.22
    view.layer?.add(animation, forKey: "flash")
}

/// A view that draws the ambient dashboard background.
final class DashboardBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let gradient = NSGradient(colors: [NSColor(hex: 0x090C11), NSColor(hex: 0x0D141C), NSColor(hex: 0x0A0E14)])!
        gradient.draw(in: bounds, angle: -70)

        let glow = NSGradient(colors: [Palette.accent.withAlphaComponent(0.16), Palette.accent.withAlphaComponent(0.03), .clear])!
        let glowRect = NSRect(x: -180, y: bounds.maxY - 210, width: 640, height: 500)
        glow.draw(in: NSBezierPath(ovalIn: glowRect), relativeCenterPosition: .zero)

        let tealGlow = NSGradient(colors: [Palette.teal.withAlphaComponent(0.075), .clear])!
        let tealRect = NSRect(x: bounds.maxX - 420, y: -220, width: 660, height: 560)
        tealGlow.draw(in: NSBezierPath(ovalIn: tealRect), relativeCenterPosition: .zero)

        // Hairline border.
        Palette.whiteLine.setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
    }
}

extension Palette {
    static let whiteLine = NSColor.white.withAlphaComponent(0.06)
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class DraggableVisualEffectView: NSVisualEffectView {
    override var mouseDownCanMoveWindow: Bool { true }
}
