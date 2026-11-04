import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import RimlightCore

@Suite struct LayerImageTests {
    /// A PNG drawn with CoreGraphics in `space`, opaque or not.
    private func png(_ url: URL, side: Int, space: CGColorSpace, alpha: Bool = true, bits: Int = 8, draw: (CGContext) -> Void) throws {
        let info = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        let bitmap = bits == 16 ? info | CGBitmapInfo.byteOrder16Little.rawValue : info
        let context = try #require(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: bits, bytesPerRow: 0, space: space, bitmapInfo: bitmap))
        draw(context)
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    /// Straight RGBA with every byte value somewhere, alpha from clear to solid.
    private func sample(side: Int = 64) -> LayerImage {
        var image = LayerImage(side: side)
        for y in 0..<side {
            for x in 0..<side {
                let a: Float = y < 4 ? 0 : Float((x * 4 + y) % 256) / 255
                image[x, y] = SIMD4(Float((x * 37 + y * 11) % 256) / 255, Float((x * 3 + y * 101) % 256) / 255, Float((x + y) % 256) / 255, a)
            }
        }
        return image
    }

    @Test func aWriteReadsBackByteForByte() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "round.png")
            let image = sample()
            try image.write(to: url)
            let back = try LayerImage.read(url)
            #expect(back.width == 64 && back.height == 64)
            var worst: Float = 0
            for i in stride(from: 0, to: image.pixels.count, by: 4) where image.pixels[i + 3] > 0 {
                for c in i..<(i + 4) { worst = max(worst, abs(back.pixels[c] - image.pixels[c])) }
            }
            // Straight alpha all the way: even a pixel at alpha 1/255 keeps its colour.
            #expect(worst < 0.5 / 255)
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            let written = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(written.colorSpace?.name == CGColorSpace.sRGB)
        }
    }

    @Test func aDisplayP3PNGReadsAsSRGB() throws {
        try withTempDir { dir in
            let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
            let srgb = try #require(CGColorSpace(name: CGColorSpace.sRGB))
            let colour = try #require(CGColor(colorSpace: p3, components: [0.55, 0.42, 0.18, 1]))
            let url = dir.appending(path: "p3.png")
            try png(url, side: 16, space: p3, bits: 16) { context in
                context.setFillColor(colour)
                context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            }
            let expected = try #require(colour.converted(to: srgb, intent: .defaultIntent, options: nil)?.components)
            let image = try LayerImage.read(url)
            let pixel = image[8, 8]
            #expect(abs(pixel.x - Float(expected[0])) < 1.5 / 255)
            #expect(abs(pixel.y - Float(expected[1])) < 1.5 / 255)
            #expect(abs(pixel.z - Float(expected[2])) < 1.5 / 255)
            #expect(pixel.w == 1)
            // Read raw, the P3 values would be visibly off: the conversion did something.
            #expect(abs(pixel.x - 0.55) > 3 / 255)
        }
    }

    @Test func anImageWithoutAlphaReadsOpaque() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "rgb.png")
            try png(url, side: 8, space: LayerImage.sRGB, alpha: false) { context in
                context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 1, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            }
            let image = try LayerImage.read(url)
            #expect(image[3, 3] == SIMD4(1, 0, 1, 1))
            #expect(!image.hasAlpha)
            #expect(image.isOnMagenta)
        }
    }

    /// A red square on clear, shrunk: its soft edge stays red, never darkened by the clear
    /// pixels' black.
    @Test func resizingDoesNotFringe() {
        var image = LayerImage(side: 100)
        for y in 30..<70 { for x in 30..<70 { image[x, y] = SIMD4(1, 0.2, 0.1, 1) } }
        let small = image.resized(to: 37)
        #expect(small.width == 37 && small.height == 37)
        var edge = 0
        for y in 0..<37 {
            for x in 0..<37 where small[x, y].w > 0.02 {
                let p = small[x, y]
                #expect(abs(p.x - 1) < 0.02 && abs(p.y - 0.2) < 0.02 && abs(p.z - 0.1) < 0.02)
                if p.w < 0.98 { edge += 1 }
            }
        }
        #expect(edge > 0)
        #expect(small[0, 0].w == 0)
        #expect(small.resized(to: 37) == small)
    }

    /// A dark part keeps its colour where the resample overshoots alpha just inside its edge: dividing by the clamped
    /// alpha lightened a band along quiet-pick's grey tile.
    @Test func resizingKeepsADarkEdgesColour() {
        var image = LayerImage(side: 125)
        for y in 30..<95 { for x in 30..<95 { image[x, y] = SIMD4(0.2, 0.2, 0.2, 1) } }
        let small = image.resized(to: 102)
        for y in 0..<102 {
            for x in 0..<102 where small[x, y].w > 0.5 { #expect(abs(small[x, y].x - 0.2) < 0.004, "\(x), \(y): \(small[x, y])") }
        }
    }

    @Test func croppingAndBounds() throws {
        var image = LayerImage(width: 40, height: 30)
        image[5, 7] = SIMD4(1, 1, 1, 1)
        image[20, 12] = SIMD4(1, 1, 1, 0.6)
        image[30, 25] = SIMD4(1, 1, 1, 0.3)
        #expect(image.alphaBounds(above: 0.5) == LayerBox(x0: 5, y0: 7, x1: 21, y1: 13))
        #expect(LayerImage(side: 4).alphaBounds(above: 0) == nil)
        let crop = try image.cropped(to: LayerBox(x0: 5, y0: 7, x1: 21, y1: 13))
        #expect(crop.width == 16 && crop.height == 6)
        #expect(crop[0, 0] == SIMD4(1, 1, 1, 1) && crop[15, 5].w == 0.6)
        #expect(throws: LayerImage.Failure.self) { try image.cropped(to: LayerBox(x0: 50, y0: 0, x1: 60, y1: 10)) }
    }

    @Test func boxesCodeAsThePlansFourNumbers() throws {
        let box = try #require(LayerBox([190, 0, 1000, 230]))
        #expect(box.width == 810 && box.height == 230)
        let json = try JSONEncoder().encode(box)
        #expect(String(decoding: json, as: UTF8.self) == "[190,0,1000,230]")
        #expect(try JSONDecoder().decode(LayerBox.self, from: json) == box)
        #expect(LayerBox([10, 10, 5, 20]) == nil)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(LayerBox.self, from: Data("[1,2,3]".utf8)) }
    }

    /// The pick's tile is its solid part, at 1024 and 1254 px.
    @Test func theTileIsThePicksSolidPartAtBothSizes() throws {
        var pick = LayerImage(side: 200)
        for y in 20..<180 { for x in 30..<170 { pick[x, y] = SIMD4(0.2, 0.4, 0.6, x == 30 ? 0.4 : 1) } }
        let (tile, reference) = try LayerImage.tile(fromPick: pick)
        #expect(tile.width == 1024 && tile.height == 1024)
        #expect(reference.width == 1254 && reference.height == 1254)
        // The half-clear column at x 30 is cut, so the tile is solid edge to edge.
        #expect(tile[0, 512].w > 0.99 && tile[1023, 0].w > 0.99)
        #expect(abs(tile[512, 512].z - 0.6) < 1e-3)
        #expect(throws: LayerImage.Failure.self) { try LayerImage.tile(fromPick: LayerImage(side: 10)) }
    }

    @Test func overIsPorterDuff() {
        let base = LayerImage(side: 2, fill: SIMD4(0, 0, 1, 1))
        var top = LayerImage(side: 2)
        top[0, 0] = SIMD4(1, 0, 0, 0.25)
        top[1, 1] = SIMD4(1, 1, 1, 1)
        let out = top.over(base)
        #expect(out[0, 0] == SIMD4(0.25, 0, 0.75, 1))
        #expect(out[1, 0] == SIMD4(0, 0, 1, 1))
        #expect(out[1, 1] == SIMD4(1, 1, 1, 1))
        let checker = LayerImage.checkerboard(width: 64, height: 64)
        #expect(checker[0, 0].x == 235 / 255 && checker[32, 0].x == 200 / 255 && checker[32, 32].x == 235 / 255)
        #expect(!LayerImage(side: 8).onCheckerboard().hasAlpha)
    }
}
