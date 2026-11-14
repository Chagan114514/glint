import AppKit
import Carbon.HIToolbox

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
        record: @escaping () -> Void
    ) {
        installHandlerIfNeeded()
        unregisterAll()

        actions[1] = area
        actions[2] = window
        actions[3] = fullScreen
        actions[4] = record

        register(id: 1, keyCode: UInt32(kVK_ANSI_1), label: "⌃⌥1")
        register(id: 2, keyCode: UInt32(kVK_ANSI_2), label: "⌃⌥2")
        register(id: 3, keyCode: UInt32(kVK_ANSI_3), label: "⌃⌥3")
        register(id: 4, keyCode: UInt32(kVK_ANSI_4), label: "⌃⌥4")
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

    private func register(id: UInt32, keyCode: UInt32, label: String) {
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(
            keyCode,
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status == noErr, let reference {
            references.append(reference)
        } else {
            failedShortcuts.append(label)
            NSLog("Glint: failed to register \(label) hot key (\(status))")
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
