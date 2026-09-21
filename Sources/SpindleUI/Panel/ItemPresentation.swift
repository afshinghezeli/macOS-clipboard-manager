import AppKit
import SpindleCore
import SpindleStorage

/// How an item is named and drawn in the list, shared by the rows and the preview.
@MainActor
enum ItemPresentation {
    static func title(for item: ItemSummary) -> String {
        if let title = item.title, !title.isEmpty { return title }
        if !item.preview.isEmpty { return item.preview }
        switch item.kind {
        case .image: return String(localized: "Image", bundle: .spindleUI, comment: "List title of a copied image.")
        case .file: return String(localized: "File", bundle: .spindleUI, comment: "List title of a copied file.")
        case .color: return String(localized: "Color", bundle: .spindleUI, comment: "List title of a copied color.")
        case .text, .richText, .link:
            return String(
                localized: "Blank text", bundle: .spindleUI, comment: "List title of text that is only spaces.")
        }
    }

    static func kindName(_ kind: ItemKind) -> String {
        switch kind {
        case .text: String(localized: "Text", bundle: .spindleUI, comment: "Item kind.")
        case .richText: String(localized: "Formatted text", bundle: .spindleUI, comment: "Item kind.")
        case .link: String(localized: "Link", bundle: .spindleUI, comment: "Item kind.")
        case .image: String(localized: "Image", bundle: .spindleUI, comment: "List title of a copied image.")
        case .file: String(localized: "File", bundle: .spindleUI, comment: "List title of a copied file.")
        case .color: String(localized: "Color", bundle: .spindleUI, comment: "List title of a copied color.")
        }
    }

    static func accessibilityLabel(for item: ItemSummary) -> String {
        "\(kindName(item.kind)): \(title(for: item))"
    }

    static func symbol(for kind: ItemKind) -> NSImage? {
        let name =
            switch kind {
            case .text: "text.alignleft"
            case .richText: "doc.richtext"
            case .link: "link"
            case .image: "photo"
            case .file: "doc"
            case .color: "paintpalette"
            }
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    static func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            color.setFill()
            circle.fill()
            NSColor.separatorColor.setStroke()
            circle.lineWidth = 1
            circle.stroke()
            return true
        }
    }
}

/// Turns the hex notation of a copied color into a color for its swatch.
enum ColorParser {
    static func color(from text: String) -> NSColor? {
        var hex = text.trimmingCharacters(in: .whitespaces)
        guard hex.hasPrefix("#") else { return nil }
        hex.removeFirst()
        if hex.count == 3 || hex.count == 4 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
        let hasAlpha = hex.count == 8
        let red = Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let green = Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let blue = Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let alpha = hasAlpha ? Double(value & 0xFF) / 255 : 1
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}
