import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import SpindleStorage

/// Builds real image files in memory, so the tests exercise ImageIO end to end.
enum TestImages {
    static func make(width: Int, height: Int, transparent: Bool, as type: UTType) -> Data {
        let alpha: CGImageAlphaInfo = transparent ? .premultipliedLast : .noneSkipLast
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: alpha.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: transparent ? 0.5 : 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }
}

@Suite
struct ImageProcessingTests {
    @Test
    func readsPixelSizeWithoutDecoding() throws {
        let png = TestImages.make(width: 640, height: 480, transparent: false, as: .png)
        let size = try #require(ImageProcessing.pixelSize(of: png))
        #expect(size.width == 640)
        #expect(size.height == 480)
    }

    @Test
    func thumbnailsKeepTheAspectRatioWithinTheLimit() throws {
        let png = TestImages.make(width: 1600, height: 900, transparent: false, as: .png)
        let thumbnail = try #require(ImageProcessing.thumbnail(of: png))
        #expect(thumbnail.width == 256)
        #expect(thumbnail.height == 144)
    }

    @Test
    func opaqueImagesBecomeJPEGAndTransparentOnesPNG() throws {
        let opaque = try #require(
            ImageProcessing.thumbnail(of: TestImages.make(width: 500, height: 500, transparent: false, as: .png)))
        let clear = try #require(
            ImageProcessing.thumbnail(of: TestImages.make(width: 500, height: 500, transparent: true, as: .png)))
        #expect(opaque.data.prefix(2) == Data([0xFF, 0xD8]))  // JPEG
        #expect(clear.data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))  // PNG
    }

    @Test
    func smallImagesAreNotScaledUp() throws {
        let thumbnail = try #require(
            ImageProcessing.thumbnail(of: TestImages.make(width: 64, height: 32, transparent: false, as: .png)))
        #expect(thumbnail.width == 64)
        #expect(thumbnail.height == 32)
    }

    @Test
    func tiffIsTranscodedToASmallerPNGOfTheSameSize() throws {
        let tiff = TestImages.make(width: 1200, height: 800, transparent: false, as: .tiff)
        let png = try #require(ImageProcessing.pngData(from: tiff))
        #expect(png.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
        #expect(png.count < tiff.count)
        let size = try #require(ImageProcessing.pixelSize(of: png))
        #expect(size.width == 1200 && size.height == 800)
    }

    @Test
    func garbageIsRejected() {
        let garbage = Data("not an image".utf8)
        #expect(ImageProcessing.thumbnail(of: garbage) == nil)
        #expect(ImageProcessing.pngData(from: garbage) == nil)
        #expect(ImageProcessing.pixelSize(of: garbage) == nil)
    }
}
