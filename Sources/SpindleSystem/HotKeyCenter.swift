import Carbon.HIToolbox
public import SpindleCore

/// Registers global keyboard shortcuts with the Carbon hotkey API.
///
/// Carbon hotkeys need no permission, work in the App Sandbox and consume the key press, so the
/// app in front never sees it. There is one application event target per process, so there is one
/// center, whose event handler is installed once and never removed.
@MainActor
public final class HotKeyCenter {
    public static let shared = HotKeyCenter()

    public enum RegistrationError: Error, Equatable {
        /// Another app already registered this combination.
        case taken
        case failed(Int32)
    }

    private struct Registration {
        var reference: EventHotKeyRef
        var action: @MainActor () -> Void
    }

    private var registrations: [UInt32: Registration] = [:]
    private var nextID: UInt32 = 1
    private var handler: EventHandlerRef?

    private init() {}

    /// Registers `shortcut` and returns an id for ``unregister(_:)``.
    public func register(
        _ shortcut: KeyboardShortcut, action: @escaping @MainActor () -> Void
    ) throws(RegistrationError) -> UInt32 {
        try installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode), Self.carbonModifiers(shortcut.modifiers),
            EventHotKeyID(signature: Self.signature, id: id), GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else {
            throw status == eventHotKeyExistsErr ? .taken : .failed(status)
        }
        registrations[id] = Registration(reference: reference, action: action)
        return id
    }

    public func unregister(_ id: UInt32) {
        guard let registration = registrations.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(registration.reference)
    }

    public func unregisterAll() {
        for id in Array(registrations.keys) { unregister(id) }
    }

    // MARK: - Carbon

    /// 'Spnd'.
    private static let signature: OSType = 0x5370_6E64

    static func carbonModifiers(_ modifiers: KeyboardShortcut.Modifiers) -> UInt32 {
        var result = 0
        if modifiers.contains(.command) { result |= cmdKey }
        if modifiers.contains(.option) { result |= optionKey }
        if modifiers.contains(.shift) { result |= shiftKey }
        if modifiers.contains(.control) { result |= controlKey }
        return UInt32(result)
    }

    private func installHandlerIfNeeded() throws(RegistrationError) {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                guard status == noErr, hotKeyID.signature == HotKeyCenter.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                let center = Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue()
                // Carbon delivers hotkey events on the main thread.
                MainActor.assumeIsolated { center.registrations[hotKeyID.id]?.action() }
                return noErr
            },
            1, &eventType, context, &handler)
        guard status == noErr else { throw .failed(status) }
    }
}
