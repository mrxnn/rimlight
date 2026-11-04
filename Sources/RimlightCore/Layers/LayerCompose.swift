import Foundation

/// Plain compositing: the assembly of fitted layers with no renderer in between, and the
/// checkerboard a layer is shown on.
extension LayerImage {
    /// This image laid over `base` (Porter-Duff "over"). Both must be the same size.
    public func over(_ base: LayerImage) -> LayerImage {
        precondition(width == base.width && height == base.height, "over needs two images of one size")
        let top = premultiplied()
        var out = base.premultiplied()
        out.withUnsafeMutableBufferPointer { d in
            top.withUnsafeBufferPointer { s in
                for i in stride(from: 0, to: d.count, by: 4) {
                    let keep = 1 - s[i + 3]
                    for c in i..<(i + 4) { d[c] = s[c] + d[c] * keep }
                }
            }
        }
        return LayerImage(width: width, height: height, premultiplied: out)
    }

    /// Light and lighter grey squares (200 and 235 of 255), opaque: what a layer with alpha is
    /// shown on, so its clear parts read as clear.
    public static func checkerboard(width: Int, height: Int, square: Int = 32) -> LayerImage {
        var image = LayerImage(width: width, height: height)
        let dark: Float = 200 / 255, light: Float = 235 / 255
        for y in 0..<height {
            for x in 0..<width {
                let v = (x / square + y / square) % 2 == 1 ? dark : light
                image[x, y] = SIMD4(v, v, v, 1)
            }
        }
        return image
    }

    /// The image over a checkerboard of its own size.
    public func onCheckerboard(square: Int = 32) -> LayerImage {
        over(.checkerboard(width: width, height: height, square: square))
    }
}
