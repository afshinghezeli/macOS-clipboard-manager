/// Which kinds of items the panel shows (⌘P cycles through them).
public enum HistoryFilter: CaseIterable, Hashable, Sendable {
    case all, text, images, files, links, colors

    /// The kinds shown, or `nil` for all of them.
    public var kinds: Set<ItemKind>? {
        switch self {
        case .all: nil
        case .text: [.text, .richText]
        case .images: [.image]
        case .files: [.file]
        case .links: [.link]
        case .colors: [.color]
        }
    }

    public func includes(_ kind: ItemKind) -> Bool {
        kinds?.contains(kind) ?? true
    }

    public var next: HistoryFilter {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}
