import SwiftUI

/// The strip under the list: what ↵ will do, and where to find everything else.
struct FooterView: View {
    var targetAppName: String?
    var canPaste: Bool

    var body: some View {
        HStack(spacing: 14) {
            Spacer()
            hint(primaryAction, keys: "↵")
            Divider().frame(height: 14)
            hint(
                String(localized: "Actions", bundle: .spindleUI, comment: "Footer: opens the list of actions."),
                keys: "⌘K")
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .frame(height: 36)
    }

    /// Names the destination, so there's no doubt where the text will go.
    private var primaryAction: String {
        if canPaste, let targetAppName {
            return String(
                localized: "Paste to \(targetAppName)", bundle: .spindleUI,
                comment: "Footer: the Return key pastes into this app.")
        }
        return String(
            localized: "Copy to Clipboard", bundle: .spindleUI, comment: "Footer: the Return key copies the item.")
    }

    private func hint(_ title: String, keys: String) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: title).foregroundStyle(.primary)
            Text(verbatim: keys)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
        }
    }
}
