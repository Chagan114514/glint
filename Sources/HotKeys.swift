import AppKit
import Carbon.HIToolbox

enum HotKeyAction: String, CaseIterable {
    case area
    case window
    case fullScreen
    case record
    case pause
    case scroll

    var id: UInt32 {
        switch self {
        case .area: return 1
        case .window: return 2
        case .fullScreen: return 3
        case .record: return 4
        case .pause: return 5
        case .scroll: return 6
        }
    }

    var title: String {
        switch self {
        case .area: return "区域截图"
        case .window: return "窗口截图"
        case .fullScreen: return "全屏截图"
        case .record: return "开始/停止录屏"
        case .pause: return "暂停/继续录屏"
        case .scroll: return "滚动截图"
        }
    }

    var defaultKeyCode: UInt32 {
        switch self {
        case .area: return UInt32(kVK_ANSI_1)
        case .window: return UInt32(kVK_ANSI_2)
        case .fullScreen: return UInt32(kVK_ANSI_3)
        case .record: return UInt32(kVK_ANSI_4)
        case .pause: return UInt32(kVK_ANSI_5)
        case .scroll: return UInt32(kVK_ANSI_6)
        }
    }

    var defaultCombo: HotKeyCombo {
        HotKeyCombo(keyCode: defaultKeyCode, carbonModifiers: UInt32(controlKey | optionKey), keyLabel: hotKeyName(for: defaultKeyCode, fallback: String(Int(defaultKeyCode))))
    }
}

struct HotKeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var keyLabel: String

    var display: String {
        var text = ""
        if carbonModifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + keyLabel
    }

    static func from(event: NSEvent) -> HotKeyCombo? {
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        guard flags.contains(.control) || flags.contains(.option) || flags.contains(.command) else { return nil }
        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }

        let raw = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let label: String
        if !raw.isEmpty, raw.unicodeScalars.allSatisfy({ !$0.properties.isWhitespace }) {
            label = raw.uppercased()
        } else {
            label = hotKeyName(for: UInt32(event.keyCode), fallback: "键\(event.keyCode)")
        }
        return HotKeyCombo(keyCode: UInt32(event.keyCode), carbonModifiers: carbon, keyLabel: label)
    }
}

enum HotKeyStore {
    static let changed = Notification.Name("GlintHotKeysChanged")
    private static let key = "GlintHotKeyCombos"

    static func combo(for action: HotKeyAction) -> HotKeyCombo {
        guard let data = UserDefaults.standard.data(forKey: key),
              let map = try? JSONDecoder().decode([String: HotKeyCombo].self, from: data),
              let combo = map[action.rawValue] else {
            return action.defaultCombo
        }
        return combo
    }

    static func set(_ combo: HotKeyCombo, for action: HotKeyAction) {
        var map = all()
        map[action.rawValue] = combo
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: key)
        }
        NotificationCenter.default.post(name: changed, object: nil)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
    }

    static func all() -> [String: HotKeyCombo] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let map = try? JSONDecoder().decode([String: HotKeyCombo].self, from: data) else {
            return [:]
        }
        return map
    }

    static func label(for action: HotKeyAction) -> String {
        combo(for: action).display
    }
}

private func hotKeyName(for keyCode: UInt32, fallback: String) -> String {
    switch Int(keyCode) {
    case kVK_ANSI_A: return "A"
    case kVK_ANSI_B: return "B"
    case kVK_ANSI_C: return "C"
    case kVK_ANSI_D: return "D"
    case kVK_ANSI_E: return "E"
    case kVK_ANSI_F: return "F"
    case kVK_ANSI_G: return "G"
    case kVK_ANSI_H: return "H"
    case kVK_ANSI_I: return "I"
    case kVK_ANSI_J: return "J"
    case kVK_ANSI_K: return "K"
    case kVK_ANSI_L: return "L"
    case kVK_ANSI_M: return "M"
    case kVK_ANSI_N: return "N"
    case kVK_ANSI_O: return "O"
    case kVK_ANSI_P: return "P"
    case kVK_ANSI_Q: return "Q"
    case kVK_ANSI_R: return "R"
    case kVK_ANSI_S: return "S"
    case kVK_ANSI_T: return "T"
    case kVK_ANSI_U: return "U"
    case kVK_ANSI_V: return "V"
    case kVK_ANSI_W: return "W"
    case kVK_ANSI_X: return "X"
    case kVK_ANSI_Y: return "Y"
    case kVK_ANSI_Z: return "Z"
    case kVK_ANSI_0: return "0"
    case kVK_ANSI_1: return "1"
    case kVK_ANSI_2: return "2"
    case kVK_ANSI_3: return "3"
    case kVK_ANSI_4: return "4"
    case kVK_ANSI_5: return "5"
    case kVK_ANSI_6: return "6"
    case kVK_ANSI_7: return "7"
    case kVK_ANSI_8: return "8"
    case kVK_ANSI_9: return "9"
    case kVK_Space: return "Space"
    case kVK_Return: return "Return"
    case kVK_Tab: return "Tab"
    case kVK_LeftArrow: return "←"
    case kVK_RightArrow: return "→"
    case kVK_UpArrow: return "↑"
    case kVK_DownArrow: return "↓"
    case kVK_F1: return "F1"
    case kVK_F2: return "F2"
    case kVK_F3: return "F3"
    case kVK_F4: return "F4"
    case kVK_F5: return "F5"
    case kVK_F6: return "F6"
    case kVK_F7: return "F7"
    case kVK_F8: return "F8"
    case kVK_F9: return "F9"
    case kVK_F10: return "F10"
    case kVK_F11: return "F11"
    case kVK_F12: return "F12"
    default: return fallback
    }
}

final class HotKeyManager {
    static let shared = HotKeyManager()

    private let signature: OSType = 0x474C4E54 // 'GLNT'
    private var actions: [UInt32: () -> Void] = [:]
    private var references: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var handlerInstalled = false
    private(set) var failedShortcuts: [String] = []

    private init() {}

    func install(
        area: @escaping () -> Void,
        window: @escaping () -> Void,
        fullScreen: @escaping () -> Void,
        record: @escaping () -> Void,
        pause: @escaping () -> Void,
        scroll: @escaping () -> Void
    ) {
        installHandlerIfNeeded()
        unregisterAll()

        actions[HotKeyAction.area.id] = area
        actions[HotKeyAction.window.id] = window
        actions[HotKeyAction.fullScreen.id] = fullScreen
        actions[HotKeyAction.record.id] = record
        actions[HotKeyAction.pause.id] = pause
        actions[HotKeyAction.scroll.id] = scroll

        for action in HotKeyAction.allCases {
            let combo = HotKeyStore.combo(for: action)
            register(action: action, combo: combo)
        }
    }

    func suspend() {
        unregisterAll()
    }

    func resume() {
        reinstall()
    }

    func reinstall() {
        guard let area = actions[HotKeyAction.area.id],
              let window = actions[HotKeyAction.window.id],
              let full = actions[HotKeyAction.fullScreen.id],
              let record = actions[HotKeyAction.record.id],
              let pause = actions[HotKeyAction.pause.id],
              let scroll = actions[HotKeyAction.scroll.id] else { return }
        install(area: area, window: window, fullScreen: full, record: record, pause: pause, scroll: scroll)
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let result = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard result == noErr else { return result }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.actions[hotKeyID.id]?()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        if status != noErr {
            NSLog("Glint: failed to install hot key handler (\(status))")
        }
        handlerInstalled = status == noErr
    }

    private func register(action: HotKeyAction, combo: HotKeyCombo) {
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: action.id)
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status == noErr, let reference {
            references.append(reference)
        } else {
            failedShortcuts.append("\(action.title) \(combo.display)")
            NSLog("Glint: failed to register \(action.title) hot key \(combo.display) (\(status))")
        }
    }

    private func unregisterAll() {
        for reference in references {
            UnregisterEventHotKey(reference)
        }
        references.removeAll()
        failedShortcuts.removeAll()
    }

    deinit {
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
