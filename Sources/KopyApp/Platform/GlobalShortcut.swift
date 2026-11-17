import Carbon.HIToolbox
import KopyCore

@MainActor
final class GlobalShortcut {
    private static let signature: OSType = 0x4B4F5059
    private static var nextID: UInt32 = 0

    private var handler: EventHandlerRef?
    private var binding: (key: EventHotKeyRef, id: UInt32, shortcut: ShelfShortcut, action: () -> Void)?
    var registeredShortcut: ShelfShortcut? { binding?.shortcut }

    func register(_ shortcut: ShelfShortcut, action: @escaping () -> Void) -> Bool {
        if registeredShortcut?.keyCode == shortcut.keyCode, registeredShortcut?.modifiers == shortcut.modifiers {
            binding?.shortcut = shortcut
            binding?.action = action
            return true
        }
        guard installHandler() else { return false }

        let modifiers = [
            (UInt32(1), UInt32(cmdKey)),
            (UInt32(2), UInt32(controlKey)),
            (UInt32(4), UInt32(optionKey)),
            (UInt32(8), UInt32(shiftKey))
        ].reduce(UInt32(0)) { $0 | (shortcut.modifiers & $1.0 != 0 ? $1.1 : 0) }
        Self.nextID &+= 1
        let id = EventHotKeyID(signature: Self.signature, id: Self.nextID)
        var replacement: EventHotKeyRef?
        guard RegisterEventHotKey(
            shortcut.keyCode, modifiers, id, GetEventDispatcherTarget(), 0, &replacement
        ) == noErr, let replacement else { return false }

        if let binding { UnregisterEventHotKey(binding.key) }
        binding = (replacement, id.id, shortcut, action)
        return true
    }

    private func installHandler() -> Bool {
        if handler != nil { return true }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                guard GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id
                ) == noErr else { return OSStatus(eventNotHandledErr) }
                let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
                return MainActor.assumeIsolated {
                    guard let binding = shortcut.binding, id.signature == GlobalShortcut.signature,
                          id.id == binding.id else {
                        return OSStatus(eventNotHandledErr)
                    }
                    binding.action()
                    return OSStatus(noErr)
                }
            },
            1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler
        )
        return status == noErr
    }

    func clear() {
        if let binding { UnregisterEventHotKey(binding.key) }
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        binding = nil
    }
}
