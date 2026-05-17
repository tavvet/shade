import AppKit
import Carbon.HIToolbox

@MainActor
final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var action: (() -> Void)?

    @discardableResult
    func register(keyCode: UInt32 = UInt32(kVK_F12),
                  modifiers: UInt32 = 0,
                  onTrigger: @escaping () -> Void) -> Bool {
        action = onTrigger

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyCallback,
            1,
            &spec,
            selfPtr,
            &eventHandler
        )
        guard installStatus == noErr else { return false }

        let hotKeyID = EventHotKeyID(signature: shadeSignature, id: 1)
        let regStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        return regStatus == noErr
    }

    fileprivate func fire() {
        action?()
    }
}

private let shadeSignature: FourCharCode = {
    let chars = Array("shde".utf8)
    return (FourCharCode(chars[0]) << 24)
        | (FourCharCode(chars[1]) << 16)
        | (FourCharCode(chars[2]) << 8)
        |  FourCharCode(chars[3])
}()

private let hotkeyCallback: EventHandlerUPP = { _, _, userData in
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async { MainActor.assumeIsolated { manager.fire() } }
    return noErr
}
