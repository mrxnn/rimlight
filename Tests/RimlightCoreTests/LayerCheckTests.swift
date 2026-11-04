import Foundation
import Testing

@testable import RimlightCore

/// The build's measured review: the pick against the Default render, and each layer's contrast in a render.
@Suite struct LayerCheckTests {
    /// `image` with `rect` (x0, y0, x1, y1) filled with an opaque colour.
    private func filled(_ image: LayerImage, _ rect: (Int, Int, Int, Int), _ colour: SIMD3<Float>) -> LayerImage {
        var out = image
        for y in rect.1..<rect.3 { for x in rect.0..<rect.2 { out[x, y] = SIMD4(colour, 1) } }
        return out
    }

    /// The eclipse, simplified: a black square in front of a grey one on white, in a 1024 px tile.
    private func eclipse(blackAt x: Int, grey: SIMD3<Float> = [0.81, 0.81, 0.81], shade: Float = 0) -> LayerImage {
        var image = LayerImage(side: 1024, fill: SIMD4(1 - shade, 1 - shade, 1 - shade, 1))
        image = filled(image, (260, 240, 760, 740), grey - shade)
        return filled(image, (x, 280, x + 500, 780), SIMD3(repeating: 0.11))
    }

    /// A redraw lands a few pixels off and a shade lighter: no part moved.
    @Test func aRedrawsDriftIsNoMove() {
        let pick = eclipse(blackAt: 290)
        let result = LayerCompare.compare(pick: pick, render: eclipse(blackAt: 294, shade: 0.02))
        #expect(result.regions.isEmpty)
        #expect(result.score > 0.99)
    }

    /// The tile drawn 40 px further right: black where the pick is white, on its right side, is found and boxed.
    @Test func aPartThatMovedIsBoxed() throws {
        let pick = eclipse(blackAt: 290)
        let result = LayerCompare.compare(pick: pick, render: eclipse(blackAt: 330))
        let first = try #require(result.regions.first)
        // the right side, where the tile now covers the ground, from x 760 to 830
        #expect(first.box.x0 <= 790 && first.box.x1 >= 800 && first.box.x1 <= 860)
        #expect(first.box.y0 <= 300 && first.box.y1 >= 760)
        #expect(result.regions.count <= 3)
        #expect(result.score < 0.99)
        let picture = try LayerCompare.picture(pick: pick, render: eclipse(blackAt: 330), renderLabel: "Default", result: result)
        #expect(picture.width == 600 * 3 + 16 && picture.height == 600)
    }

    /// The masks of the eclipse as two layers, bottom to top, at 256 px.
    private func eclipseMasks() -> [(name: String, mask: [Bool])] {
        func square(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> [Bool] {
            (0..<(256 * 256)).map { i in (x0..<x1).contains(i % 256) && (y0..<y1).contains(i / 256) }
        }
        return [("hidden", square(100, 100, 120, 120)), ("crescent", square(60, 60, 190, 190)), ("tile", square(70, 70, 200, 200))]
    }

    private func render(ground: SIMD3<Float>, crescent: SIMD3<Float>, tile: SIMD3<Float>) -> LayerImage {
        var image = LayerImage(side: 256, fill: SIMD4(ground, 1))
        image = filled(image, (60, 60, 190, 190), crescent)
        return filled(image, (70, 70, 200, 200), tile)
    }

    /// Each layer is measured against what is behind it: the crescent against the ground where the tile does not
    /// cover it, the tile against the crescent and the ground. A black tile on a near-black Dark fades; a layer
    /// under another entirely is hidden.
    @Test func contrastFindsTheTileVanishingInDark() throws {
        let outlines = LayerContrast.outlines(eclipseMasks(), width: 256)
        let all = LayerContrast.measure(render(ground: [1, 1, 1], crescent: [0.81, 0.81, 0.81], tile: [0.11, 0.106, 0.098]), outlines)
        #expect(all.map(\.name) == ["hidden", "crescent", "tile"])
        #expect(all[0].contrast == nil && !all[0].fades)
        let light = Array(all.dropFirst())
        #expect(try #require(light[1].contrast) > 50 && !light[1].fades)
        // pale grey on white is low but reads
        let crescent = try #require(light[0].contrast)
        #expect(crescent > LayerContrast.threshold && crescent < 30)

        let dark = LayerContrast.measure(render(ground: [0.07, 0.07, 0.07], crescent: [0.81, 0.81, 0.81], tile: [0.11, 0.106, 0.098]), outlines).dropFirst().map { $0 }
        #expect(dark[0].fades == false)
        // the tile's bottom and right sides, against the ground, are under the threshold; its top and left, against
        // the crescent, are not
        #expect(dark[1].weak > 0.4 && dark[1].weak < 0.6)
        let box = try #require(dark[1].weakBox)
        #expect(box.x1 >= 200 && box.y1 >= 200)

        // with the crescent gone dark too, the tile fades along its whole outline
        let gone = LayerContrast.measure(render(ground: [0.07, 0.07, 0.07], crescent: [0.08, 0.08, 0.08], tile: [0.11, 0.106, 0.098]), outlines).dropFirst().map { $0 }
        #expect(gone[1].fades && gone[1].weak > 0.9)
    }
}
