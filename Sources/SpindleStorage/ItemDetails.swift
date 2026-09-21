public import Foundation
public import SpindleCore

/// Everything the preview shows about one item. Loaded when the item is selected, never for the
/// whole list.
public struct ItemDetails: Hashable, Sendable {
    public var summary: ItemSummary
    /// The plain text, at most ``ItemDetails/textLimit`` bytes of it.
    public var text: String?
    /// Whether ``text`` stops short of the full copy.
    public var isTextTruncated: Bool
    public var fileURLs: [URL]
    public var imageWidth: Int?
    public var imageHeight: Int?
    public var sourceBundleID: String?
    public var sourceAppName: String?
    /// Every stored payload together, in bytes.
    public var byteSize: Int
    /// The pasteboard formats the item carries, in the order the source offered them.
    public var flavors: [PasteboardFlavor]

    /// How much text the preview shows. More would only slow the panel down.
    public static let textLimit = 100_000
}
