/// What a history item mainly is. Drives the icon, the preview and the type filter.
///
/// The raw values are stored in the database, so existing cases must never be renumbered.
public enum ItemKind: Int, CaseIterable, Sendable {
    case text = 0
    case richText = 1
    case link = 2
    case image = 3
    case file = 4
    case color = 5
}
