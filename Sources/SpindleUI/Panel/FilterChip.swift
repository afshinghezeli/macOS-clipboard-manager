import SpindleCore
import SwiftUI

/// Shows which kinds of items are listed; click or press ⌘P for the next filter.
struct FilterChip: View {
    var filter: HistoryFilter
    var next: () -> Void

    var body: some View {
        Button(action: next) {
            HStack(spacing: 6) {
                Text(verbatim: Self.title(filter))
                Text(verbatim: "⌘P").foregroundStyle(.tertiary)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(filter == .all ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.tint.opacity(0.2))))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.title(filter))
    }

    static func title(_ filter: HistoryFilter) -> String {
        switch filter {
        case .all: String(localized: "All Types", bundle: .spindleUI, comment: "Filter: every kind of item.")
        case .text: String(localized: "Text", bundle: .spindleUI, comment: "Item kind.")
        case .images: String(localized: "Images", bundle: .spindleUI, comment: "Filter: only images.")
        case .files: String(localized: "Files", bundle: .spindleUI, comment: "Filter: only files.")
        case .links: String(localized: "Links", bundle: .spindleUI, comment: "Filter: only links.")
        case .colors: String(localized: "Colors", bundle: .spindleUI, comment: "Filter: only colors.")
        }
    }
}
