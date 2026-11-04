import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Apple's app icon shape, and the two ways a render is held to it.
///
/// `Resources/TileMask.png` is the shape as Icon Composer renders it (`scripts/tile-mask`):
/// 1024 px, white inside. A fresh render gets it as a grey template image, so the generator
/// draws its tile in about the right place. Then `conform` makes the shape exact: it finds the
/// tile the generator drew, scales it onto the mask's place in the frame and takes the mask as
/// the alpha. The generator's own corners are always a little squarer than Apple's, so the
/// mask trims them and never has to invent pixels.
public enum TileShape {
    /// The tile's side as a share of the render's: 1024 px in a 1254 px render, so the tile
    /// crops to Icon Composer's 1024 px canvas without resampling.
    public static let tileShare = 1024.0 / 1254.0
    /// The side of a render, and of the template.
    public static let renderSide = 1254
    /// How far past the mask the drawn tile is scaled on every side, in pixels of a 1024 px
    /// tile, tried in order until the drawn tile covers the whole mask. A drawn edge goes from
    /// clear to solid over about 3 px; a tile drawn with corners rounder than Apple's needs more.
    static let overscanSteps: [Double] = [3, 5, 8, 12, 16, 20]
    /// Source alpha from which a pixel counts as solid: the mask alone sets its alpha. A
    /// generator's tile is about 252 inside, not 255.
    static let solidAlpha = 192
    /// The template's grey, 0 to 255.
    static let templateGrey = 128
    /// The drawn tile's sides may differ by this factor at most (renders without a template
    /// reach 1.07).
    static let maxAspect = 1.15

    public static func tileSide(for side: Int) -> Int { Int((Double(side) * tileShare).rounded()) }

    /// Why a render could not be fitted. It is then stored as it was rendered.
    public struct Unfit: Error, CustomStringConvertible {
        public var description: String

        public init(description: String) { self.description = description }
    }

    /// A fitted render: the side of the frame and the tile, the size of the tile the generator
    /// drew, and how far past the mask it was scaled on every side, in pixels.
    public struct Fit: Hashable, Sendable {
        public var side: Int
        public var tile: Int
        public var drawnWidth: Int
        public var drawnHeight: Int
        public var overscan: Double
    }

    // MARK: The template

    /// The line a fresh render's prompt ends with. `number` is the template's place among the
    /// reference images.
    public static func templateNote(image number: Int) -> String {
        "Image \(number) is the tile template: a flat grey silhouette of the icon tile's exact outline, "
            + "corner curve, size and position in the frame. The icon's tile fills that silhouette exactly, "
            + "edge to edge, with the same outline, corner curve, size and position. Do not copy the "
            + "template's grey, do not draw its outline, and do not draw a smaller tile inside it. "
            + "Everything outside the silhouette is fully transparent."
    }

    /// `request` with the template as its last reference image and `templateNote` at the end
    /// of its prompt. nil when it already has the most references image_gen takes.
    public static func withTemplate(_ request: ImageRequest, template: URL) -> ImageRequest? {
        guard request.refs.count < ImageRequest.maxRefs else { return nil }
        var request = request
        request.refs.append(template)
        var prompt = request.prompt
        while prompt.last?.isWhitespace == true { prompt.removeLast() }
        request.prompt = prompt + "\n\n" + templateNote(image: request.refs.count)
        return request
    }

    /// Writes the template: the tile in flat grey at its place in a `side` px frame, clear
    /// outside.
    public static func writeTemplate(to url: URL, side: Int = renderSide) throws {
        let mask = try maskPlane(side: side)
        let context = try rgbaContext(side: side, space: sRGB())
        let pixels = bytes(context)
        for i in 0..<(side * side) where mask[i] > 0 {
            let m = Int(mask[i])
            let grey = UInt8((templateGrey * m + 127) / 255)
            pixels[i * 4] = grey
            pixels[i * 4 + 1] = grey
            pixels[i * 4 + 2] = grey
            pixels[i * 4 + 3] = mask[i]
        }
        try writePNG(context, to: url)
    }

    // MARK: Fitting

    /// Fits the render at `source` to the shape and writes it as a PNG at `destination`. The
    /// drawn tile is scaled on each axis so it overlaps the mask by the overscan, centred, and
    /// the mask becomes its alpha; colours keep the render's colour space. Throws `Unfit`,
    /// writing nothing, for a render it cannot read, one that is not square, or one whose tile
    /// it cannot find (an opaque render has no alpha to find it by).
    public static func conform(_ source: URL, to destination: URL) throws -> Fit {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
            let image = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { throw Unfit(description: "not a readable image") }
        let side = image.width
        guard image.height == side, side >= 64 else {
            throw Unfit(description: "the render is \(image.width)x\(image.height), not square")
        }
        // The render's own space when a bitmap context takes it, so colours are not converted.
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? sRGB()
        let original = try (try? rgbaContext(side: side, space: space)) ?? rgbaContext(side: side, space: sRGB())
        let frame = CGRect(x: 0, y: 0, width: side, height: side)
        original.draw(image, in: frame)
        guard let drawn = tileBounds(bytes(original), side: side) else {
            throw Unfit(description: "no tile found: the middle of the render is not solid")
        }
        let width = drawn.maxX - drawn.minX + 1
        let height = drawn.maxY - drawn.minY + 1
        // A tile drawn edge to edge is still a tile when the corners outside its curve are
        // clear, as after a cutout; with solid corners the render is just opaque.
        let source = bytes(original)
        let cornersClear = [0, side - 1, (side - 1) * side, side * side - 1].allSatisfy { source[$0 * 4 + 3] < 8 }
        guard width < side || height < side || cornersClear else {
            throw Unfit(description: "no clear edge around the tile: the render is opaque")
        }
        guard width * 2 >= side, height * 2 >= side else {
            throw Unfit(description: "the drawn tile is only \(width)x\(height) px")
        }
        guard Double(max(width, height)) / Double(min(width, height)) <= maxAspect else {
            throw Unfit(description: "the drawn tile is \(width)x\(height) px, too far from square")
        }

        // The drawn tile's outer pixel edges land `overscan` outside the mask's square, at the
        // first step where no pixel at least half inside the mask is short of solid. Usually
        // the first: about 20 ms a step.
        let tile = tileSide(for: side)
        let origin = (side - tile) / 2
        let mask = try maskPlane(side: side)
        let fitted = try rgbaContext(side: side, space: original.colorSpace ?? sRGB())
        let pixels = bytes(fitted)
        func draw(overscan: Double) {
            let scaleX = (Double(tile) + 2 * overscan) / Double(width)
            let scaleY = (Double(tile) + 2 * overscan) / Double(height)
            let left = Double(origin) - overscan - Double(drawn.minX) * scaleX
            let top = Double(origin) - overscan - Double(drawn.minY) * scaleY
            let size = CGSize(width: Double(side) * scaleX, height: Double(side) * scaleY)
            fitted.clear(frame)
            fitted.draw(image, in: CGRect(origin: CGPoint(x: left, y: Double(side) - top - size.height), size: size))
        }
        func shortfall() -> Int {
            var short = 0
            for i in 0..<(side * side) where mask[i] >= 128 && Int(pixels[i * 4 + 3]) < solidAlpha { short += 1 }
            return short
        }
        let steps = overscanSteps.map { $0 * Double(tile) / 1024 }
        var best = (overscan: steps[0], short: Int.max)
        for overscan in steps {
            draw(overscan: overscan)
            let short = shortfall()
            if short < best.short { best = (overscan, short) }
            if short == 0 { break }
        }
        // No step covered the whole mask: redraw the one that came closest.
        if best.short > 0, best.overscan != steps.last { draw(overscan: best.overscan) }

        // Alpha from the mask. A solid pixel keeps its colour at the mask's alpha; a pixel
        // under `solidAlpha` (only where the drawn tile fell short of the mask) fades with it.
        for i in 0..<(side * side) {
            let p = i * 4
            let m = Int(mask[i])
            guard m > 0 else {
                pixels[p] = 0
                pixels[p + 1] = 0
                pixels[p + 2] = 0
                pixels[p + 3] = 0
                continue
            }
            let a = Int(pixels[p + 3])
            let d = max(a, solidAlpha)
            for c in p..<(p + 3) { pixels[c] = UInt8(min(255, (Int(pixels[c]) * m + d / 2) / d)) }
            pixels[p + 3] = UInt8((min(a, solidAlpha) * m + solidAlpha / 2) / solidAlpha)
        }
        try writePNG(fitted, to: destination)
        return Fit(side: side, tile: tile, drawnWidth: width, drawnHeight: height, overscan: best.overscan)
    }

    /// The drawn tile's pixel bounds, rows top first and inclusive, found from the middle out
    /// along a band through the centre a fifth of the side wide: the last row and column on
    /// each side whose stretch of the band is at least half solid (alpha 128 and up). The
    /// rounded corners, specks outside the tile and a soft shadow under it do not move them.
    /// nil when the centre itself is not solid.
    static func tileBounds(_ rgba: UnsafeMutablePointer<UInt8>, side: Int) -> (minX: Int, maxX: Int, minY: Int, maxY: Int)? {
        let band = (side * 2 / 5)..<(side * 3 / 5)
        func solid(_ x: Int, _ y: Int) -> Bool { rgba[(y * side + x) * 4 + 3] >= 128 }
        func rowIsSolid(_ y: Int) -> Bool { band.count { solid($0, y) } * 2 >= band.count }
        func columnIsSolid(_ x: Int) -> Bool { band.count { solid(x, $0) } * 2 >= band.count }
        let middle = side / 2
        guard rowIsSolid(middle), columnIsSolid(middle) else { return nil }
        var minY = middle, maxY = middle, minX = middle, maxX = middle
        while minY > 0, rowIsSolid(minY - 1) { minY -= 1 }
        while maxY < side - 1, rowIsSolid(maxY + 1) { maxY += 1 }
        while minX > 0, columnIsSolid(minX - 1) { minX -= 1 }
        while maxX < side - 1, columnIsSolid(maxX + 1) { maxX += 1 }
        return (minX, maxX, minY, maxY)
    }

    // MARK: Pixels

    /// The mask at its place in a `side` px frame, one byte per pixel, rows top first; `tile` px wide, centred, which
    /// is a render's tile unless it says otherwise.
    static func maskPlane(side: Int, tile: Int? = nil) throws -> [UInt8] {
        guard let url = CoreResources.url("TileMask", withExtension: "png"),
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw Unfit(description: "TileMask.png is missing from \(CoreResources.bundleName)") }
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { throw Unfit(description: "cannot make a \(side) px mask") }
        context.interpolationQuality = .high
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let tile = tile ?? tileSide(for: side)
        let origin = (side - tile) / 2
        context.draw(image, in: CGRect(x: origin, y: side - origin - tile, width: tile, height: tile))
        guard let data = context.data else { throw Unfit(description: "cannot make a \(side) px mask") }
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: side * side))
    }

    /// A cleared premultiplied RGBA8 context that owns its pixels, rows top first.
    static func rgbaContext(side: Int, space: CGColorSpace) throws -> CGContext {
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw Unfit(description: "cannot make a \(side) px RGBA context") }
        context.interpolationQuality = .high
        context.clear(CGRect(x: 0, y: 0, width: side, height: side))
        return context
    }

    static func bytes(_ context: CGContext) -> UnsafeMutablePointer<UInt8> {
        context.data!.assumingMemoryBound(to: UInt8.self)
    }

    static func sRGB() -> CGColorSpace { CGColorSpace(name: CGColorSpace.sRGB)! }

    static func writePNG(_ context: CGContext, to url: URL) throws {
        guard let image = context.makeImage(),
            let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw Unfit(description: "cannot encode \(url.lastPathComponent)") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw Unfit(description: "cannot write \(url.path)")
        }
    }
}
