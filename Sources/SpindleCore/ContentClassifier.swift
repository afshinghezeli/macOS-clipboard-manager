public import Foundation

/// Decides what a copy mainly is, from the flavors present and, for text, the text itself.
///
/// Everything here is cheap and local: no file system access, no data detectors, no network. Text
/// longer than a short single line is never treated as a link, color or path.
public enum ContentClassifier {
    /// What a single line of copied text looks like.
    public enum TextShape: Equatable, Sendable {
        case link(URL)
        case email
        case color
        case filePath
        case plain
    }

    /// Longest text that can still be a link, color or path.
    private static let shapeLimit = 2048

    public static func kind(of copy: CapturedCopy) -> ItemKind {
        let flavors = Set(copy.items.flatMap { $0.representations.map(\.flavor) })
        if flavors.contains(.fileURL) { return .file }

        let text = copy.plainText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty {
            // Browsers put images on the pasteboard without a text flavor. Spreadsheets add a picture
            // of the copied cells *next to* the text, which is why text wins when there is any.
            if flavors.contains(where: \.isImage) || flavors.contains(.pdf) { return .image }
            if flavors.contains(.color) { return .color }
            if flavors.contains(.url) { return .link }
            return .text
        }

        switch shape(of: text) {
        case .link: return .link
        case .color: return .color
        case .email, .filePath, .plain: break
        }
        let rich: Set<PasteboardFlavor> = [.rtf, .rtfd, .html]
        return flavors.isDisjoint(with: rich) ? .text : .richText
    }

    public static func shape(of text: String) -> TextShape {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= shapeLimit, !text.contains(where: \.isNewline) else {
            return .plain
        }
        if let url = webURL(text) { return .link(url) }
        if isColor(text) { return .color }
        if isEmail(text) { return .email }
        if isFilePath(text) { return .filePath }
        return .plain
    }

    // MARK: - Shapes

    private static func webURL(_ text: String) -> URL? {
        guard !text.contains(" "), let url = URL(string: text), let scheme = url.scheme?.lowercased(),
            ["http", "https", "ftp"].contains(scheme), let host = url.host(), !host.isEmpty
        else { return nil }
        return url
    }

    private static func isEmail(_ text: String) -> Bool {
        let address = text.lowercased().hasPrefix("mailto:") ? String(text.dropFirst(7)) : text
        let parts = address.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !address.contains(" ") else { return false }
        let domain = parts[1]
        guard let dot = domain.lastIndex(of: "."), dot != domain.startIndex else { return false }
        return domain[domain.index(after: dot)...].count >= 2
    }

    private static func isFilePath(_ text: String) -> Bool {
        guard text.hasPrefix("/") || text.hasPrefix("~/") else { return false }
        // A lone slash or "//" is more likely a comment marker or a divider than a path.
        return text.count > 1 && !text.hasPrefix("//")
    }

    /// `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`, and CSS `rgb()`, `rgba()`, `hsl()`, `hsla()`.
    private static func isColor(_ text: String) -> Bool {
        if text.first == "#" {
            let digits = text.dropFirst()
            return [3, 4, 6, 8].contains(digits.count) && digits.allSatisfy(\.isHexDigit)
        }
        let lower = text.lowercased()
        guard let open = lower.firstIndex(of: "("), lower.last == ")" else { return false }
        let function = lower[..<open]
        guard ["rgb", "rgba", "hsl", "hsla"].contains(function) else { return false }
        let arguments = lower[lower.index(after: open)..<lower.index(before: lower.endIndex)]
        let components = arguments.split { $0 == "," || $0 == " " || $0 == "/" }
        guard components.count == 3 || components.count == 4 else { return false }
        return components.allSatisfy { component in
            let number = component.trimmingSuffix("%").trimmingSuffix("deg")
            return !number.isEmpty && Double(number) != nil
        }
    }
}

extension Substring {
    fileprivate func trimmingSuffix(_ suffix: String) -> Substring {
        hasSuffix(suffix) ? dropLast(suffix.count) : self
    }
}
