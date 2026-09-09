import Carbon
import Foundation

final class GlobalHotKey: @unchecked Sendable {
    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private let action: @Sendable () -> Void

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping @Sendable () -> Void) {
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
            keyCode,
            modifiers,
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
