import CryptoKit
import Foundation
import SpindleCore

/// A captured copy turned into exactly what gets stored: which representations, the dedup key,
/// the preview and search text, metadata and thumbnail.
///
/// Building one can take tens of milliseconds for large images, so it happens in the ingestor,
/// never on the main thread.
struct PreparedCopy: Sendable {
    struct StoredRepresentation: Sendable {
        var itemIndex: Int
        var flavor: PasteboardFlavor
        var data: Data
    }

    struct Metadata: Codable, Equatable, Sendable {
        var imageWidth: Int?
        var imageHeight: Int?
        var fileCount: Int?
    }

    var kind: ItemKind
    var representations: [StoredRepresentation]
    var dedupKey: ContentHash
    var preview: String
    var searchText: String
    var metadata: Metadata
    var thumbnail: Thumbnail?

    var byteCount: Int { representations.reduce(0) { $0 + $1.data.count } }

    init(_ copy: CapturedCopy) {
        kind = ContentClassifier.kind(of: copy)
        representations = Self.representationsToStore(copy)
        metadata = Metadata()
        thumbnail = nil

        switch kind {
        case .file:
            let names = Self.fileNames(copy)
            preview = TextFolding.preview(of: names.joined(separator: ", "))
            searchText = TextFolding.fold(names.joined(separator: " "))
            metadata.fileCount = names.count
        case .image:
            preview = ""
            searchText = ""
            if let image = Self.preferredImage(in: representations) {
                thumbnail = ImageProcessing.thumbnail(of: image.data)
                if let size = ImageProcessing.pixelSize(of: image.data) {
                    metadata.imageWidth = size.width
                    metadata.imageHeight = size.height
                }
            }
        case .text, .richText, .link, .color:
            let text = copy.plainText ?? ""
            preview = TextFolding.preview(of: text)
            searchText = TextFolding.fold(text)
        }
        dedupKey = Self.dedupKey(kind: kind, copy: copy, representations: representations)
    }

    // MARK: - Representations

    /// Everything captured, except TIFF when the same item also offers a compressed image. An item
    /// that offers only TIFF (a screenshot) gets it re-encoded as PNG.
    private static func representationsToStore(_ copy: CapturedCopy) -> [StoredRepresentation] {
        var stored: [StoredRepresentation] = []
        for (index, item) in copy.items.enumerated() {
            let flavors = Set(item.representations.map(\.flavor))
            let hasCompressedImage = !flavors.isDisjoint(with: [.png, .jpeg, .heic])
            for representation in item.representations {
                if representation.flavor == .tiff {
                    if hasCompressedImage { continue }
                    if let png = ImageProcessing.pngData(from: representation.data) {
                        stored.append(StoredRepresentation(itemIndex: index, flavor: .png, data: png))
                        continue
                    }
                }
                stored.append(
                    StoredRepresentation(itemIndex: index, flavor: representation.flavor, data: representation.data))
            }
        }
        return stored
    }

    private static func preferredImage(in representations: [StoredRepresentation]) -> StoredRepresentation? {
        for flavor in [PasteboardFlavor.png, .heic, .jpeg, .tiff, .pdf] {
            if let match = representations.first(where: { $0.flavor == flavor }) { return match }
        }
        return nil
    }

    private static func fileNames(_ copy: CapturedCopy) -> [String] {
        copy.items.compactMap { item in
            guard let data = item.data(for: .fileURL), let url = URL(dataRepresentation: data, relativeTo: nil)
            else { return nil }
            return url.lastPathComponent
        }
    }

    // MARK: - Identity

    /// What makes two copies "the same item". Copying the same text again, even from another app
    /// with different formatting, moves the existing item to the top instead of adding a
    /// near-duplicate; the newest formatting replaces the old.
    private static func dedupKey(
        kind: ItemKind, copy: CapturedCopy, representations: [StoredRepresentation]
    ) -> ContentHash {
        var hasher = SHA256()
        func add(_ tag: String) { hasher.update(data: Data(tag.utf8)) }

        switch kind {
        case .file:
            add("files")
            for item in copy.items {
                add("\u{0}")
                if let url = item.data(for: .fileURL) { hasher.update(data: url) }
            }
        case .image:
            add("image")
            if let image = copy.items.lazy.flatMap(\.representations).first(where: {
                $0.flavor.isImage || $0.flavor == .pdf
            }) {
                hasher.update(data: image.data)
            }
        case .text, .richText, .link, .color:
            if let text = copy.plainText {
                add("text")
                hasher.update(data: Data(text.utf8))
            } else {
                add("representations")
                for representation in representations {
                    add("\u{0}\(representation.itemIndex)\u{0}\(representation.flavor.rawValue)\u{0}")
                    hasher.update(data: Data(SHA256.hash(data: representation.data)))
                }
            }
        }
        return ContentHash(digest: hasher.finalize())
    }
}
