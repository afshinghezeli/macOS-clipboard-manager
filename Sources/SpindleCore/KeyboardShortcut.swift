/// A key plus modifiers, as stored in settings and registered as a global hotkey.
///
/// The key is a virtual key code: a physical position on the keyboard, independent of layout.
public struct KeyboardShortcut: Hashable, Sendable, Codable {
    public struct Modifiers: OptionSet, Hashable, Sendable, Codable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)

        /// In the order macOS menus show them: ⌃⌥⇧⌘.
        public var symbols: String {
            [(Modifiers.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
                .filter { contains($0.0) }.map(\.1).joined()
        }
    }

    public var keyCode: UInt16
    public var modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⌃⌘V (ADR 0008). 9 is the V key's position on an ANSI keyboard.
    public static let openPanelDefault = KeyboardShortcut(keyCode: 9, modifiers: [.control, .command])

    /// A global shortcut needs ⌘ or ⌃: combinations with only ⌥ or ⇧ type characters, and macOS
    /// 15.0–15.1 refused to register them.
    public var isValidGlobalShortcut: Bool {
        !modifiers.isDisjoint(with: [.command, .control])
    }
}
