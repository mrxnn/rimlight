import CoreGraphics
import Foundation
import ImageIO

/// Whether a render is really transparent, judged from its pixels. The header alone is not
/// enough: a generator can paint a checkerboard into an RGBA file with alpha 255 everywhere.
///
/// ImageIO decodes the PNG once, downsampled to at most 128 px, into an RGBA8 buffer of 64 KB
/// (about 10 ms for a 1254 px render). The render is transparent when each of the four corner
/// patches (6% of the side) has a mean alpha below 8 and at least 0.5% of all pixels have alpha
/// below 8. The clear share is only a floor: a tile filling 97% of the frame leaves about 3%
/// clear, and the corners are what tell a real transparent render from a painted one. A header
/// without alpha is opaque and nothing is decoded.
public struct ImageProbe: Hashable, Sendable {
    /// The longest side of the decoded sample.
    public static let sampleSize = 128
    /// A corner patch's side as a share of the image's side.
    public static let cornerShare = 0.06
    /// Alpha below this counts as clear.
    public static let clearAlpha = 8
    /// The share of clear pixels a transparent render has at least.
    public static let minClearShare = 0.005

    public var header: PNGHeader
    public var isTransparent: Bool
    /// The highest of the four corner patches' mean alpha, 0 to 255. 255 when not decoded.
    public var cornerAlpha: Double
    /// The share of sampled pixels with alpha below `clearAlpha`. 0 when not decoded.
    public var clearShare: Double

    public init(header: PNGHeader, isTransparent: Bool, cornerAlpha: Double, clearShare: Double) {
        self.header = header
        self.isTransparent = isTransparent
        self.cornerAlpha = cornerAlpha
        self.clearShare = clearShare
    }

    /// The size from the header and `alpha` from the pixels, as `icon.json` stores it.
    public var imageInfo: ImageInfo { ImageInfo(width: header.width, height: header.height, alpha: isTransparent) }

    /// nil for a missing file, anything that is not a PNG, or a PNG ImageIO cannot decode.
    public static func read(_ url: URL) -> ImageProbe? {
        guard let header = PNGHeader.read(url) else { return nil }
        guard header.hasAlpha else {
            return ImageProbe(header: header, isTransparent: false, cornerAlpha: 255, clearShare: 0)
        }
        guard let sample = alphaSample(url) else { return nil }
        let (cornerAlpha, clearShare) = measure(sample.alpha, width: sample.width, height: sample.height)
        return ImageProbe(
            header: header, isTransparent: cornerAlpha < Double(clearAlpha) && clearShare >= minClearShare,
            cornerAlpha: cornerAlpha, clearShare: clearShare)
    }

    /// The highest corner patch mean and the clear share of an alpha plane, row-major.
    static func measure(_ alpha: [UInt8], width: Int, height: Int) -> (cornerAlpha: Double, clearShare: Double) {
        let pw = max(1, Int((Double(width) * cornerShare).rounded()))
        let ph = max(1, Int((Double(height) * cornerShare).rounded()))
        var cornerAlpha = 0.0
        for (x0, y0) in [(0, 0), (width - pw, 0), (0, height - ph), (width - pw, height - ph)] {
            var sum = 0
            for y in y0..<(y0 + ph) {
                for x in x0..<(x0 + pw) { sum += Int(alpha[y * width + x]) }
            }
            cornerAlpha = max(cornerAlpha, Double(sum) / Double(pw * ph))
        }
        let clear = alpha.reduce(0) { $0 + ($1 < clearAlpha ? 1 : 0) }
        return (cornerAlpha, Double(clear) / Double(max(1, alpha.count)))
    }

    /// The alpha plane of the image downsampled to `sampleSize`, read through an RGBA8 context.
    private static func alphaSample(_ url: URL) -> (alpha: [UInt8], width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: sampleSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
            let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        let width = image.width
        let height = image.height
        // Zeroed, so drawing over it equals copying the image's alpha.
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var alpha = [UInt8](repeating: 0, count: width * height)
        for i in alpha.indices { alpha[i] = rgba[i * 4 + 3] }
        return (alpha, width, height)
    }
}
