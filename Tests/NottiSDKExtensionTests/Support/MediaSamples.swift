import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Tiny, valid media files for the download tests. No real content, no real URL.
enum MediaSamples {
    /// A 4x4 solid image encoded by ImageIO, so the system accepts it as an attachment.
    private static func image(type: UTType) -> Data {
        let size = 4
        let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }

    static var png: Data { image(type: .png) }
    static var jpg: Data { image(type: .jpeg) }
    static var gif: Data { image(type: .gif) }

    /// An `ftyp` box with the `isom` brand plus an empty `free` box. Enough for the type check.
    static var mp4: Data {
        var bytes = Data([0, 0, 0, 24])
        bytes.append(Data("ftypisom".utf8))
        bytes.append(Data([0, 0, 2, 0]))
        bytes.append(Data("isomiso2".utf8))
        bytes.append(Data([0, 0, 0, 8]))
        bytes.append(Data("free".utf8))
        return bytes
    }

    /// One MPEG-1 Layer III frame header followed by silence.
    static var mp3: Data {
        var bytes = Data([0xFF, 0xFB, 0x90, 0x00])
        bytes.append(Data(count: 413))
        return bytes
    }

    /// Bytes no media type accepts.
    static var junk: Data { Data("fixture, not media".utf8) }
}
