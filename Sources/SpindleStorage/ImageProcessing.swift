import CoreGraphics
public import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A small preview image for the history list.
public struct Thumbnail: Hashable, Sendable {
    /// JPEG, or PNG when the image has transparency.
    public var data: Data
    public var width: Int
    public var height: Int
}

/// Image work done off the main thread during ingest. ImageIO only; nothing here decodes a full
/// image into memory.
enum ImageProcessing {
    static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard
            let source = CGImageSourceCreateWithData(
                data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }

    /// Scales the image so its longer side is at most `maxPixelSize`, decoding only the scaled
    /// bitmap. About 30–60 ms for a 5K screenshot on an M4.
    static func thumbnail(of data: Data, maxPixelSize: Int = 256) -> Thumbnail? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let type: UTType = hasAlpha(image) ? .png : .jpeg
        guard let encoded = encode(image, as: type, quality: 0.8) else { return nil }
        return Thumbnail(data: encoded, width: image.width, height: image.height)
    }

    /// Re-encodes an image as PNG. Screenshots arrive on the pasteboard as uncompressed TIFF, about
    /// 59 MB for a 5K display; the same image as PNG is typically a tenth of that.
    static func pngData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return encode(image, as: .png, quality: nil)
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }

    private static func encode(_ image: CGImage, as type: UTType, quality: Double?) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            return nil
        }
        let properties = quality.map { [kCGImageDestinationLossyCompressionQuality: $0] as CFDictionary }
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
