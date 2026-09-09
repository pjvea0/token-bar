import Carbon
import Foundation

struct GlobalShortcut: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
    let key: String

    static let standard = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_R),
        modifiers: UInt32(cmdKey | controlKey | shiftKey),
        key: "R"
    )

    var displayText: String {
        var value = ""
        if modifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        return value + key
    }
}

final class GlobalHotKey: @unchecked Sendable {
    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private let action: @Sendable () -> Void

    init?(shortcut: GlobalShortcut, action: @escaping @Sendable () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotKeyHandler,
            1,
            &eventType,
            context,
            &eventHandler
        ) == noErr else { return nil }

        let identifier = EventHotKeyID(signature: OSType(0x544F4B4E), id: 1) // "TOKN"
        guard RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        ) == noErr else {
            if let eventHandler { RemoveEventHandler(eventHandler) }
            eventHandler = nil
            return nil
        }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    fileprivate func perform() {
        DispatchQueue.main.async(execute: action)
    }
}

private let globalHotKeyHandler: EventHandlerUPP = { _, _, context in
    guard let context else { return OSStatus(eventNotHandledErr) }
    Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue().perform()
    return noErr
}
