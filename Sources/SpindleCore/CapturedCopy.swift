public import Foundation

/// One flavor of one pasteboard item, with its bytes.
public struct Representation: Hashable, Sendable {
    public var flavor: PasteboardFlavor
    public var data: Data

    public init(flavor: PasteboardFlavor, data: Data) {
        self.flavor = flavor
        self.data = data
    }
}

/// One pasteboard item. Most copies have a single item; copying several files in Finder produces
/// one item per file.
public struct CapturedItem: Hashable, Sendable {
    /// In the order the pasteboard listed them, which is the source app's order of preference.
    public var representations: [Representation]

    public init(representations: [Representation]) {
        self.representations = representations
    }

    public func data(for flavor: PasteboardFlavor) -> Data? {
        representations.first { $0.flavor == flavor }?.data
    }
}

/// Everything Spindle read from the pasteboard for a single copy.
///
/// This is the value that crosses from the main actor, where the pasteboard is read, to the
/// ingestor, which stores it. It holds bytes only; no AppKit objects.
public struct CapturedCopy: Hashable, Sendable {
    public var items: [CapturedItem]

    /// Every type the pasteboard declared, including ones that weren't read. Used to attribute
    /// copies from apps that never become frontmost, such as menu bar password managers.
    public var declaredTypes: [PasteboardFlavor]

    /// The app the copy came from: its own `org.nspasteboard.source` claim if it made one,
    /// otherwise the frontmost app when the copy was noticed.
    public var sourceBundleID: String?

    public var changeCount: Int
    public var capturedAt: Date

    public init(
        items: [CapturedItem],
        declaredTypes: [PasteboardFlavor],
        sourceBundleID: String?,
        changeCount: Int,
        capturedAt: Date
    ) {
        self.items = items
        self.declaredTypes = declaredTypes
        self.sourceBundleID = sourceBundleID
        self.changeCount = changeCount
        self.capturedAt = capturedAt
    }

    public var isEmpty: Bool { items.allSatisfy(\.representations.isEmpty) }

    public var byteCount: Int {
        items.reduce(0) { total, item in total + item.representations.reduce(0) { $0 + $1.data.count } }
    }

    /// True when the copy arrived through Universal Clipboard from another device.
    public var isRemote: Bool { declaredTypes.contains(.remoteClipboard) }

    /// The privacy markers present on the pasteboard, if any.
    public var privacyMarkers: Set<PasteboardFlavor> {
        PasteboardFlavor.privacyMarkers.intersection(declaredTypes)
    }

    /// The plain-text flavor of the first item that has one, decoded as UTF-8.
    public var plainText: String? {
        for item in items {
            if let data = item.data(for: .plainText) {
                return String(decoding: data, as: UTF8.self)
            }
        }
        return nil
    }
}
