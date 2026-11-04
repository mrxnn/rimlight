import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns what an image API returns into what the rest of Rimlight expects from a render: a
/// square PNG, 1254 px a side like Codex's, alpha kept. The tile fit, the template and the
/// layer references are all measured in that frame, and APIs only take sizes in steps of 16.
public enum RenderNormalizer {
    /// How far from square a render may be and still be centre-cropped: 2 % of its longer side.
    public static let squareTolerance = 0.02

    /// Writes `data`, an image in any format ImageIO reads, to `url` as the normalized PNG.
    public static func write(_ data: Data, to url: URL, side: Int = TileShape.renderSide) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw ImageFailure.noImage("the image API returned a file that isn't a readable image") }
        let (w, h) = (image.width, image.height)
        guard Double(abs(w - h)) <= Double(max(w, h)) * squareTolerance else {
            throw ImageFailure.noImage("the image API returned a \(w)x\(h) image, not a square one")
        }
        // Already the frame Rimlight works in: keep the provider's bytes as they are.
        if w == side, h == side, CGImageSourceGetType(source) as String? == UTType.png.identifier {
            try data.write(to: url, options: .atomic)
            return
        }
        let crop = min(w, h)
        guard let square = image.cropping(to: CGRect(x: (w - crop) / 2, y: (h - crop) / 2, width: crop, height: crop))
        else { throw ImageFailure.noImage("cannot crop the \(w)x\(h) render") }
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? TileShape.sRGB()
        let context: CGContext
        do { context = try TileShape.rgbaContext(side: side, space: space) } catch {
            throw ImageFailure.noImage("cannot resize the render: \(error)")
        }
        context.interpolationQuality = .high
        context.draw(square, in: CGRect(x: 0, y: 0, width: side, height: side))
        do { try TileShape.writePNG(context, to: url) } catch {
            throw ImageFailure.noImage("cannot write the render: \(error)")
        }
    }
}
