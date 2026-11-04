import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import RimlightCore

@Suite struct TileShapeTests {
    /// A decoded PNG: its side and premultiplied RGBA8 pixels, rows top first.
    private func pixels(_ url: URL) throws -> (side: Int, rgba: [UInt8]) {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let context = try TileShape.rgbaContext(side: image.width, space: TileShape.sRGB())
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = TileShape.bytes(context)
        return (image.width, Array(UnsafeBufferPointer(start: bytes, count: image.width * image.width * 4)))
    }

    /// A render whose tile is `rect` (in CoreGraphics' bottom-left coordinates) with circular
    /// corners, squarer than Apple's, as a generator draws it.
    private func render(_ dir: URL, size: Int = 1254, tile rect: CGRect, radius: Double) throws -> URL {
        let url = dir.appending(path: "render-\(UUID().uuidString).png")
        try DrawnPNG.rgba(size: size) { context, _ in
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.setFillColor(CGColor(srgbRed: 0.8, green: 0.2, blue: 0.4, alpha: 1))
            context.fillPath()
        }.write(to: url)
        return url
    }

    @Test func theMaskIsA1024PxTileCentredIn1254() throws {
        #expect(TileShape.tileSide(for: 1254) == 1024)
        let mask = try TileShape.maskPlane(side: 1254)
        func at(_ x: Int, _ y: Int) -> UInt8 { mask[y * 1254 + x] }
        #expect(at(627, 627) == 255)
        // The straight sides run from 115 to 1138 on both axes.
        #expect(at(115, 627) == 255 && at(1138, 627) == 255 && at(627, 115) == 255 && at(627, 1138) == 255)
        #expect(at(114, 627) == 0 && at(1139, 627) == 0 && at(627, 114) == 0 && at(627, 1139) == 0)
        // The corners are rounded: the square's corner pixel is outside.
        #expect(at(115, 115) == 0 && at(1138, 1138) == 0)
    }

    @Test func theTemplateIsAGreyTileOnClear() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "template.png")
            try TileShape.writeTemplate(to: url)
            #expect(try #require(ImageProbe.read(url)).isTransparent)
            let (side, rgba) = try pixels(url)
            #expect(side == 1254)
            let centre = (627 * side + 627) * 4
            #expect(Array(rgba[centre..<centre + 4]) == [128, 128, 128, 255])
            #expect(rgba[3] == 0)
        }
    }

    @Test func theTemplateGoesLastAndThePromptNamesIt() throws {
        let template = URL(filePath: "/tmp/tile-template.png")
        let fresh = try #require(TileShape.withTemplate(ImageRequest(prompt: "Square image.\n\n"), template: template))
        #expect(fresh.refs == [template])
        #expect(fresh.prompt == "Square image.\n\n" + TileShape.templateNote(image: 1))
        #expect(fresh.prompt.contains("Image 1 is the tile template"))

        let refs = [URL(filePath: "/tmp/a.png"), URL(filePath: "/tmp/b.png")]
        let withRefs = try #require(TileShape.withTemplate(ImageRequest(prompt: "p", refs: refs), template: template))
        #expect(withRefs.refs == refs + [template])
        #expect(withRefs.prompt.hasSuffix(TileShape.templateNote(image: 3)))

        let full = ImageRequest(prompt: "p", refs: Array(repeating: refs[0], count: ImageRequest.maxRefs))
        #expect(TileShape.withTemplate(full, template: template) == nil)
    }

    /// An off-centre, slightly wide tile with square-ish corners comes out with exactly the
    /// mask's alpha, its colour kept.
    @Test func conformFitsTheDrawnTileToTheMask() throws {
        try withTempDir { dir in
            let source = try render(dir, tile: CGRect(x: 40, y: 70, width: 1150, height: 1120), radius: 170)
            let output = dir.appending(path: "fitted.png")
            let fit = try TileShape.conform(source, to: output)
            #expect(fit.side == 1254 && fit.tile == 1024)
            #expect(fit.drawnWidth == 1150 && fit.drawnHeight == 1120)

            let (side, rgba) = try pixels(output)
            #expect(side == 1254)
            let mask = try TileShape.maskPlane(side: side)
            var worst = 0
            for i in 0..<(side * side) { worst = max(worst, abs(Int(rgba[i * 4 + 3]) - Int(mask[i]))) }
            #expect(worst <= 1)
            let centre = (627 * side + 627) * 4
            #expect(Array(rgba[centre..<centre + 4]) == [204, 51, 102, 255])
        }
    }

    /// A tile drawn with corners rounder than Apple's falls short of the mask at the 3 px
    /// overscan, so the fit scales it further until it covers the whole mask.
    @Test func conformScalesRounderCornersUntilTheyCoverTheMask() throws {
        try withTempDir { dir in
            let source = try render(dir, tile: CGRect(x: 115, y: 115, width: 1024, height: 1024), radius: 300)
            let output = dir.appending(path: "fitted.png")
            let fit = try TileShape.conform(source, to: output)
            #expect(fit.overscan > 3)

            let (side, rgba) = try pixels(output)
            let mask = try TileShape.maskPlane(side: side)
            var worst = 0
            for i in 0..<(side * side) { worst = max(worst, abs(Int(rgba[i * 4 + 3]) - Int(mask[i]))) }
            #expect(worst <= 1)
        }
    }

    @Test func conformRefusesRendersWithoutATileToFind() throws {
        try withTempDir { dir in
            let output = dir.appending(path: "fitted.png")
            let cases: [(String, URL)] = [
                ("opaque", try render(dir, tile: CGRect(x: 0, y: 0, width: 1254, height: 1254), radius: 0)),
                ("small", try render(dir, tile: CGRect(x: 400, y: 400, width: 454, height: 454), radius: 80)),
                ("wide", try render(dir, tile: CGRect(x: 20, y: 250, width: 1214, height: 754), radius: 120)),
                ("clear", try render(dir, tile: .zero, radius: 0)),
            ]
            for (name, source) in cases {
                #expect(throws: TileShape.Unfit.self, "\(name)") { try TileShape.conform(source, to: output) }
            }
            #expect(!FileManager.default.fileExists(atPath: output.path))
        }
    }
}
