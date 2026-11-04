import Accelerate
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// One image of the layered build: a picked tile, a layer the image model drew, a fitted layer or a
/// review sheet.
///
/// RGBA, straight (not premultiplied) Float 0...1, sRGB-encoded values, rows top first. Float
/// so keying, fitting and compositing never round to 8 bits between steps; straight because a
/// keyed layer's colour has to survive where its alpha is low. Reads convert any PNG to sRGB
/// (ictool writes Display P3, which pasted raw looks washed out); writes are 8-bit sRGB PNGs.
public struct LayerImage: Hashable, Sendable {
    public let width: Int
    public let height: Int
    /// `width * height * 4` values, RGBA interleaved, rows top first.
    public var pixels: [Float]

    /// Why an image could not be read, written or worked on.
    public struct Failure: Error, CustomStringConvertible {
        public var description: String

        public init(description: String) { self.description = description }
    }

    public init(width: Int, height: Int, pixels: [Float]) {
        precondition(width > 0 && height > 0 && pixels.count == width * height * 4, "pixels do not match \(width)x\(height)")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// An image filled with one straight RGBA colour; clear by default.
    public init(width: Int, height: Int, fill: SIMD4<Float> = .zero) {
        precondition(width > 0 && height > 0, "an image needs pixels")
        self.width = width
        self.height = height
        var pixels = [Float](repeating: 0, count: width * height * 4)
        if fill != .zero {
            for i in 0..<(width * height) {
                pixels[i * 4] = fill.x
                pixels[i * 4 + 1] = fill.y
                pixels[i * 4 + 2] = fill.z
                pixels[i * 4 + 3] = fill.w
            }
        }
        self.pixels = pixels
    }

    public init(side: Int, fill: SIMD4<Float> = .zero) { self.init(width: side, height: side, fill: fill) }

    public var isSquare: Bool { width == height }

    /// The straight RGBA value at (x, y), y from the top.
    public subscript(x: Int, y: Int) -> SIMD4<Float> {
        get {
            let i = (y * width + x) * 4
            return SIMD4(pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])
        }
        set {
            let i = (y * width + x) * 4
            pixels[i] = newValue.x
            pixels[i + 1] = newValue.y
            pixels[i + 2] = newValue.z
            pixels[i + 3] = newValue.w
        }
    }

    // MARK: Reading and writing

    /// Any image ImageIO reads, converted to sRGB. An image without alpha reads as alpha 1, an
    /// untagged one as sRGB.
    public static func read(_ url: URL) throws -> LayerImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw Failure(description: "cannot read \(url.lastPathComponent) as an image") }
        return try LayerImage(cgImage: image)
    }

    /// The image's pixels in sRGB. vImage's converter goes through ColorSync, keeps alpha
    /// straight (no 8-bit premultiplied step to lose a faint edge's colour) and fills alpha 1
    /// for an opaque image.
    public init(cgImage image: CGImage) throws {
        guard var format = vImage_CGImageFormat(
            bitsPerComponent: 32, bitsPerPixel: 128, colorSpace: Self.sRGB,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | CGBitmapInfo.floatComponents.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue))
        else { throw Failure(description: "cannot describe a float RGBA format") }
        let buffer: vImage.PixelBuffer<vImage.InterleavedFx4>
        do {
            buffer = try vImage.PixelBuffer<vImage.InterleavedFx4>(cgImage: image, cgImageFormat: &format)
        } catch {
            throw Failure(description: "cannot convert a \(image.width)x\(image.height) image to sRGB: \(error)")
        }
        var pixels = buffer.array
        // Display P3 colours outside sRGB come back a little below 0 or above 1.
        vDSP.clip(pixels, to: 0...1, result: &pixels)
        self.init(width: image.width, height: image.height, pixels: pixels)
    }

    /// The image as an 8-bit straight-alpha sRGB CGImage.
    public func cgImage() throws -> CGImage {
        let bytes = Data(eightBit())
        guard let provider = CGDataProvider(data: bytes as CFData),
            let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: Self.sRGB, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw Failure(description: "cannot make a \(width)x\(height) image") }
        return image
    }

    /// Writes an 8-bit RGBA PNG tagged sRGB, encoded whole and then renamed into place, so the app never reads half
    /// of a layer or a render while a build runs.
    public func write(to url: URL) throws {
        let image = try cgImage()
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil)
        else { throw Failure(description: "cannot encode \(url.lastPathComponent)") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure(description: "cannot encode \(url.lastPathComponent)") }
        try AtomicFile.write(data as Data, to: url)
    }

    /// The image cut to Apple's tile filling its whole frame, as Icon Composer renders one: alpha outside the
    /// shape goes to 0, its edge is the mask's antialiased one.
    public func maskedToTile() throws -> LayerImage {
        precondition(isSquare, "a tile is square")
        let mask = try TileShape.maskPlane(side: width, tile: width)
        var out = self
        for i in 0..<(width * height) { out.pixels[i * 4 + 3] *= Float(mask[i]) / 255 }
        return out
    }

    /// The values as bytes, rounded to nearest.
    func eightBit() -> [UInt8] {
        var scaled = [Float](repeating: 0, count: pixels.count)
        vDSP.clip(pixels, to: 0...1, result: &scaled)
        vDSP.multiply(255, scaled, result: &scaled)
        var bytes = [UInt8](repeating: 0, count: pixels.count)
        vDSP.convertElements(of: scaled, to: &bytes, rounding: .towardNearestInteger)
        return bytes
    }

    // MARK: Premultiplied values

    /// RGBA with the colour multiplied by alpha: the form every resample, warp and "over" works
    /// in, so a clear pixel's colour never bleeds into its neighbours.
    func premultiplied() -> [Float] {
        var out = pixels
        out.withUnsafeMutableBufferPointer { p in
            for i in stride(from: 0, to: p.count, by: 4) {
                let a = p[i + 3]
                p[i] *= a
                p[i + 1] *= a
                p[i + 2] *= a
            }
        }
        return out
    }

    /// Straight values from premultiplied ones, clamped; colour 0 where alpha is about 0. Lanczos overshoots alpha
    /// past 1 just inside an edge; the colour is divided by that alpha, not the clamped one, or it comes out lighter
    /// in a band along the outline.
    init(width: Int, height: Int, premultiplied p: [Float]) {
        var out = p
        out.withUnsafeMutableBufferPointer { q in
            for i in stride(from: 0, to: q.count, by: 4) {
                let raw = q[i + 3]
                let a = min(max(raw, 0), 1)
                q[i + 3] = a
                if a > 1e-4 {
                    for c in i..<(i + 3) { q[c] = min(max(q[c] / max(raw, a), 0), 1) }
                } else {
                    q[i] = 0
                    q[i + 1] = 0
                    q[i + 2] = 0
                }
            }
        }
        self.init(width: width, height: height, pixels: out)
    }

    // MARK: Geometry

    /// The image at `side` by `side` px.
    public func resized(to side: Int) -> LayerImage { resized(width: side, height: side) }

    /// The image resampled with Lanczos (vImage's high quality) on premultiplied values, so an
    /// edge does not fringe with the colour of the clear pixels beside it.
    public func resized(width w: Int, height h: Int) -> LayerImage {
        if w == width && h == height { return self }
        let out = Self.lanczos(premultiplied(), width: width, height: height, to: w, h)
        return LayerImage(width: w, height: h, premultiplied: out)
    }

    /// Lanczos resampling of a premultiplied RGBA plane. vImage's ARGB call does not care
    /// which channel is alpha: it filters all four alike.
    static func lanczos(_ plane: [Float], width: Int, height: Int, to w: Int, _ h: Int) -> [Float] {
        var src = plane
        var out = [Float](repeating: 0, count: w * h * 4)
        src.withUnsafeMutableBytes { s in
            out.withUnsafeMutableBytes { d in
                var source = vImage_Buffer(data: s.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width * 16)
                var dest = vImage_Buffer(data: d.baseAddress, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w * 16)
                _ = vImageScale_ARGBFFFF(&source, &dest, nil, vImage_Flags(kvImageHighQualityResampling))
            }
        }
        return out
    }

    /// The part inside `box`, clipped to the image. Throws for a box with nothing inside.
    public func cropped(to box: LayerBox) throws -> LayerImage {
        let x0 = max(0, box.x0), y0 = max(0, box.y0), x1 = min(width, box.x1), y1 = min(height, box.y1)
        guard x1 > x0, y1 > y0 else { throw Failure(description: "the box \(box) misses the \(width)x\(height) image") }
        let w = x1 - x0
        var out = [Float](repeating: 0, count: w * (y1 - y0) * 4)
        for y in y0..<y1 {
            let from = (y * width + x0) * 4
            let to = (y - y0) * w * 4
            out.replaceSubrange(to..<(to + w * 4), with: pixels[from..<(from + w * 4)])
        }
        return LayerImage(width: w, height: y1 - y0, pixels: out)
    }

    /// The bounds of the pixels whose alpha is above `threshold`, end exclusive; nil when none is.
    public func alphaBounds(above threshold: Float) -> LayerBox? {
        var x0 = width, y0 = height, x1 = -1, y1 = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > threshold {
                x0 = min(x0, x)
                x1 = max(x1, x)
                y0 = min(y0, y)
                y1 = max(y1, y)
            }
        }
        return x1 < 0 ? nil : LayerBox(x0: x0, y0: y0, x1: x1 + 1, y1: y1 + 1)
    }

    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
}

/// A box in tile pixels, end exclusive: where the plan says a layer roughly sits, or the part
/// of the tile an aid shows. Coded as `[x0, y0, x1, y1]`, the plan's own form.
public struct LayerBox: Hashable, Sendable, Codable, CustomStringConvertible {
    public var x0: Int
    public var y0: Int
    public var x1: Int
    public var y1: Int

    public init(x0: Int, y0: Int, x1: Int, y1: Int) {
        self.x0 = x0
        self.y0 = y0
        self.x1 = x1
        self.y1 = y1
    }

    /// nil unless `values` is four numbers with x1 > x0 and y1 > y0.
    public init?(_ values: [Int]) {
        guard values.count == 4, values[2] > values[0], values[3] > values[1] else { return nil }
        self.init(x0: values[0], y0: values[1], x1: values[2], y1: values[3])
    }

    public var width: Int { x1 - x0 }
    public var height: Int { y1 - y0 }
    public var values: [Int] { [x0, y0, x1, y1] }
    public var description: String { "[\(x0), \(y0), \(x1), \(y1)]" }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.singleValueContainer().decode([Int].self)
        guard let box = LayerBox(values) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "a box is [x0, y0, x1, y1] with x1 > x0 and y1 > y0"))
        }
        self = box
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
}
