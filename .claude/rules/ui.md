---
paths:
  - "Sources/SpindleUI/**"
---

# UI conventions

- The panel is keyboard-first. Every action has a shortcut and every shortcut is discoverable in the ⌘K actions menu or the footer. Mouse support is complete but secondary.
- Shortcuts follow Raycast where one exists (↵ paste, ⌘↵ copy, ⇧↵ paste as plain text, ⌘K actions, ⌘P filter, ⌘. pin, ⌘1–9 quick paste, ⌃N/⌃P) so switchers keep their muscle memory. Changing a default shortcut is a breaking change.
- The history list is an `NSTableView` behind `NSViewRepresentable` with fixed row height and cell reuse (ADR 0005). Everything else is SwiftUI.
- Never load the full history into memory. The list pages from `HistoryStore`; previews and thumbnails load lazily for visible rows.
- Sanitize titles before display: strip U+FFFC and control characters, collapse whitespace, cap at 300 characters. macOS 26 CoreText hangs on some U+FFFC sequences.
- Use system materials: `NSVisualEffectView` (`.popover`, `state = .active`) today; Liquid Glass behind `#available(macOS 26, *)` and `#if compiler(>=6.2)`. Respect Reduce Transparency, Reduce Motion and Increase Contrast.
- Use semantic system colors and SF Symbols. No hard-coded colors except in the icon.
- Text in the UI is short, specific and sentence case. The primary action names its destination: "Paste to Safari", not "Paste".
- Every user-facing string goes through `String(localized:)` with a comment for translators.
- Animations are short (≤150 ms) and skipped when Reduce Motion is on. Opening the panel must never wait on an animation or a database read.
- VoiceOver: every row has an accessibility label that describes the item kind and a short summary.
