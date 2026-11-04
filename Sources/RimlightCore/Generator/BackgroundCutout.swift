import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Vision

/// Cuts an opaque render's painted ground away on the Mac, for free: the first step of every
/// transparency fix, before any paid render. A model that can't draw on transparency paints
/// a flat ground, and Codex now and then paints a checkerboard; either sits around the tile.
///
/// The ground is learned from the four corners, which lie outside Apple's tile whatever the
/// model drew, and cleared only where it reaches the frame's edge through pixels of its own
/// colours, so a tile drawn edge to edge loses just its corners and a dark tile on black keeps
/// its inside. When the corners are busy, macOS's own subject cutout is tried. Either result
/// stands only when what is left is shaped like a tile; anything else is left to the paid fix.
public enum BackgroundCutout {
    public enum Method: String, Sendable {
        /// The corners' colours cleared from the edges in.
        case ground
        /// Vision's foreground mask.
        case subject
    }

    /// Writes the cut-out render to `output` and says how; nil when neither way gives a tile.
    public static func cut(_ image: URL, to output: URL) -> Method? {
        guard let source = CGImageSourceCreateWithURL(image as CFURL, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
            cgImage.width == cgImage.height, cgImage.width >= 64,
            var pixels = Pixels(cgImage)
        else { return nil }
        if clearGround(&pixels), looksLikeATile(pixels), (try? pixels.write(to: output)) != nil { return .ground }
        if let masked = subject(cgImage), let cut = Pixels(masked), looksLikeATile(cut),
            (try? cut.write(to: output)) != nil
        {
            return .subject
        }
        return nil
    }

    // MARK: The ground

    /// How far a pixel may be from a ground colour, in 0-255 RGB, and still be ground.
    static let tolerance = 30.0

    /// Clears the ground in place: zero alpha where it is, a soft, de-fringed edge where it
    /// meets the drawing. False when the corners show no ground or the cut is implausible.
    static func clearGround(_ p: inout Pixels) -> Bool {
        guard let ground = groundPalette(p) else { return false }
        let n = p.side
        func distance(_ i: Int) -> Double { ground.distance(p.color(i)) }

        // Ground reachable from the frame's edge through ground-coloured pixels.
        var isGround = [Bool](repeating: false, count: n * n)
        var stack: [Int] = []
        for k in 0..<n {
            for i in [k, (n - 1) * n + k, k * n, k * n + n - 1] where !isGround[i] && distance(i) <= tolerance {
                isGround[i] = true
                stack.append(i)
            }
        }
        while let i = stack.popLast() {
            let x = i % n, y = i / n
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, ny >= 0, nx < n, ny < n else { continue }
                let j = ny * n + nx
                if !isGround[j], distance(j) <= tolerance {
                    isGround[j] = true
                    stack.append(j)
                }
            }
        }
        keepLargestPiece(&isGround, side: n)
        let share = Double(isGround.lazy.filter { $0 }.count) / Double(n * n)
        guard share >= 0.02, share <= 0.8 else { return false }

        // Two rings of the drawing next to the ground fade with their distance from its
        // colour, with the ground's tint taken back out, so no dark or light fringe is left.
        var ring = [UInt8](repeating: 0, count: n * n)
        for pass in 1...2 {
            for i in 0..<(n * n) where !isGround[i] && ring[i] == 0 {
                let x = i % n, y = i / n
                let touches = [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { dx, dy in
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < n, ny < n else { return false }
                    let j = ny * n + nx
                    return pass == 1 ? isGround[j] : ring[j] == 1
                }
                if touches { ring[i] = UInt8(pass) }
            }
        }
        for i in 0..<(n * n) {
            if isGround[i] {
                p.clear(i)
            } else if ring[i] > 0 {
                let nearest = ground.nearest(p.color(i))
                let alpha = min(1, p.distance(i, nearest) / (tolerance * 3))
                p.fade(i, alpha: alpha, from: nearest)
            }
        }
        return true
    }

    /// Turns every piece of the drawing but the largest into ground. A painted ground's noise
    /// leaves specks the flood can't reach, a few pixels each but all over the frame; the
    /// tile is one piece.
    static func keepLargestPiece(_ isGround: inout [Bool], side n: Int) {
        var piece = [Int32](repeating: 0, count: n * n)
        var sizes: [Int] = [0]
        var stack: [Int] = []
        for start in 0..<(n * n) where !isGround[start] && piece[start] == 0 {
            let label = Int32(sizes.count)
            var size = 0
            piece[start] = label
            stack.append(start)
            while let i = stack.popLast() {
                size += 1
                let x = i % n, y = i / n
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < n, ny < n else { continue }
                    let j = ny * n + nx
                    if !isGround[j], piece[j] == 0 {
                        piece[j] = label
                        stack.append(j)
                    }
                }
            }
            sizes.append(size)
        }
        guard sizes.count > 2, let largest = sizes.indices.dropFirst().max(by: { sizes[$0] < sizes[$1] }) else { return }
        for i in 0..<(n * n) where !isGround[i] && piece[i] != Int32(largest) { isGround[i] = true }
    }

    /// The ground's colours: one for a flat ground, or the two of a checkerboard, whose
    /// squares meet in soft, noisy edges that blend one into the other, so any colour between
    /// the two counts as ground too.
    struct Ground {
        var a: SIMD3<Double>
        var b: SIMD3<Double>

        /// The ground colour nearest `c`: on the line from `a` to `b`.
        func nearest(_ c: SIMD3<Double>) -> SIMD3<Double> {
            let span = b - a
            let length = (span * span).sum()
            guard length > 0 else { return a }
            let t = max(0, min(1, ((c - a) * span).sum() / length))
            return a + span * t
        }

        func distance(_ c: SIMD3<Double>) -> Double {
            let d = c - nearest(c)
            return (d * d).sum().squareRoot()
        }
    }

    /// The ground in the four corner patches, nil when the corners are busy, as with a photo
    /// behind the tile or a drawing that runs off the frame. Two colours are found by k-means,
    /// started from the darkest and lightest corner pixels; nine pixels in ten must lie on the
    /// ground for it to count.
    static func groundPalette(_ p: Pixels) -> Ground? {
        let n = p.side
        let patch = max(8, n / 50)
        var samples: [SIMD3<Double>] = []
        for (cx, cy) in [(0, 0), (n - patch, 0), (0, n - patch), (n - patch, n - patch)] {
            for y in cy..<(cy + patch) {
                for x in cx..<(cx + patch) { samples.append(p.color(y * n + x)) }
            }
        }
        func light(_ c: SIMD3<Double>) -> Double { c.sum() }
        var a = samples.min { light($0) < light($1) }!
        var b = samples.max { light($0) < light($1) }!
        for _ in 0..<8 {
            var sumA = SIMD3<Double>.zero, sumB = SIMD3<Double>.zero
            var countA = 0.0, countB = 0.0
            for c in samples {
                let da = c - a, db = c - b
                if (da * da).sum() <= (db * db).sum() {
                    sumA += c
                    countA += 1
                } else {
                    sumB += c
                    countB += 1
                }
            }
            if countA > 0 { a = sumA / countA }
            if countB > 0 { b = sumB / countB }
        }
        // One colour when the two are close: a flat ground and its noise.
        let gap = b - a
        let ground = (gap * gap).sum().squareRoot() < tolerance ? Ground(a: (a + b) / 2, b: (a + b) / 2) : Ground(a: a, b: b)
        let on = samples.lazy.filter { ground.distance($0) <= tolerance }.count
        return Double(on) >= Double(samples.count) * 0.9 ? ground : nil
    }

    // MARK: Vision

    /// The render with everything but its foreground cleared, by Vision's subject mask.
    static func subject(_ image: CGImage) -> CGImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        guard (try? handler.perform([request])) != nil, let result = request.results?.first,
            let buffer = try? result.generateMaskedImage(
                ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: false)
        else { return nil }
        let ci = CIImage(cvPixelBuffer: buffer)
        return CIContext().createCGImage(ci, from: ci.extent)
    }

    // MARK: The check

    /// What is left must be Apple's tile, not a part of the drawing: solid in a roughly square
    /// box at least two fifths of the frame wide, filling most of that box, with the corners
    /// clear. A diagonal bar Vision picked out of the tile fails, and so does a cut that ate
    /// into the tile.
    static func looksLikeATile(_ p: Pixels) -> Bool {
        let n = p.side
        var minX = n, minY = n, maxX = -1, maxY = -1, solid = 0
        for y in 0..<n {
            for x in 0..<n where p.alpha(y * n + x) >= 128 {
                solid += 1
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return false }
        let w = Double(maxX - minX + 1), h = Double(maxY - minY + 1)
        let corners = [0, n - 1, (n - 1) * n, n * n - 1].allSatisfy { p.alpha($0) < 8 }
        return corners && w / h > 0.85 && w / h < 1.18 && w >= Double(n) * 0.4 && Double(solid) / (w * h) >= 0.8
    }
}

/// A square RGBA buffer, straight (not premultiplied) alpha, sRGB.
struct Pixels {
    let side: Int
    var bytes: [UInt8]

    init?(_ image: CGImage) {
        side = image.width
        bytes = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: TileShape.sRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        // Back to straight alpha, so colours compare whatever the coverage.
        for i in 0..<(side * side) {
            let a = Double(bytes[i * 4 + 3])
            guard a > 0, a < 255 else { continue }
            for c in 0..<3 { bytes[i * 4 + c] = UInt8(min(255, (Double(bytes[i * 4 + c]) * 255 / a).rounded())) }
        }
    }

    func color(_ i: Int) -> SIMD3<Double> {
        SIMD3(Double(bytes[i * 4]), Double(bytes[i * 4 + 1]), Double(bytes[i * 4 + 2]))
    }

    func alpha(_ i: Int) -> UInt8 { bytes[i * 4 + 3] }

    func distance(_ i: Int, _ to: SIMD3<Double>) -> Double {
        let d = color(i) - to
        return (d * d).sum().squareRoot()
    }

    mutating func clear(_ i: Int) {
        for c in 0..<4 { bytes[i * 4 + c] = 0 }
    }

    /// Sets `alpha` and takes the `ground` colour's share back out of the pixel.
    mutating func fade(_ i: Int, alpha: Double, from ground: SIMD3<Double>) {
        guard alpha > 0.004 else { return clear(i) }
        let c = (color(i) - ground * (1 - alpha)) / alpha
        for k in 0..<3 { bytes[i * 4 + k] = UInt8(max(0, min(255, c[k].rounded()))) }
        bytes[i * 4 + 3] = UInt8((Double(bytes[i * 4 + 3]) * alpha).rounded())
    }

    /// Writes a PNG with the alpha premultiplied back, as Core Graphics stores it.
    func write(to url: URL) throws {
        var premultiplied = bytes
        for i in 0..<(side * side) {
            let a = Double(premultiplied[i * 4 + 3]) / 255
            for c in 0..<3 { premultiplied[i * 4 + c] = UInt8((Double(premultiplied[i * 4 + c]) * a).rounded()) }
        }
        try premultiplied.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: TileShape.sRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { throw ImageFailure.noImage("cannot draw the cut-out render") }
            try TileShape.writePNG(context, to: url)
        }
    }
}
