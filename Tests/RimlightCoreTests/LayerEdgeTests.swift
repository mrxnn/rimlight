import Foundation
import Testing

@testable import RimlightCore

/// Each layer's outline and fill in Default against the pick at full size.
@Suite struct LayerEdgeTests {
    static let side = 256
    static let ground = SIMD3<Float>(repeating: 0.14)
    static let grey = SIMD3<Float>(repeating: 0.24)

    /// How much of the pixel at (x, y) a disc of `radius` about the middle covers, from 4 x 4 samples.
    static func coverage(_ x: Int, _ y: Int, radius: Float) -> Float {
        var inside = 0
        for i in 0..<4 {
            for j in 0..<4 {
                let u = Float(x) + (Float(i) + 0.5) / 4 - 128, v = Float(y) + (Float(j) + 0.5) / 4 - 128
                if u * u + v * v < radius * radius { inside += 1 }
            }
        }
        return Float(inside) / 16
    }

    /// quiet-pick in small: a grey disc on a near-black ground. `cover` says how much of each pixel the disc covers;
    /// `colour` its colour at a pixel.
    static func picture(cover: (Int, Int) -> Float, colour: (Int, Int) -> SIMD3<Float> = { _, _ in grey }) -> LayerImage {
        var image = LayerImage(side: side)
        for y in 0..<side {
            for x in 0..<side {
                let a = cover(x, y)
                image[x, y] = SIMD4(colour(x, y) * a + ground * (1 - a), 1)
            }
        }
        return image
    }

    static func smooth(_ x: Int, _ y: Int) -> Float { coverage(x, y, radius: 80) }

    /// The disc as its layer: its coverage as alpha.
    static func layer() -> LayerImage {
        var image = LayerImage(side: side)
        for y in 0..<side { for x in 0..<side { image[x, y] = SIMD4(grey, smooth(x, y)) } }
        return image
    }

    static func measure(_ render: LayerImage) throws -> LayerEdge.Measure {
        try #require(LayerEdge.measure(pick: picture(cover: smooth), render: render, layers: [("tile", layer())]).first)
    }

    @Test func theSamePictureWarnsOfNothing() throws {
        let m = try Self.measure(Self.picture(cover: Self.smooth))
        #expect(!m.warns)
        let outline = try #require(m.render.outline)
        // its worst block, where a 4 x 4 sampled edge reads about 0.053, well under a rough one
        #expect(outline < LayerEdge.roughOutline / 2 && m.render.outline == m.pick.outline, "outline \(outline)")
    }

    /// The key's steps: each pixel all disc or all ground, its edge wandering by a pixel, as quiet-pick's magenta
    /// drawing came out. Rougher where the pick's outline is plain, and boxed there.
    @Test func aSteppedOutlineIsRougher() throws {
        let stepped = Self.picture { x, y in
            let wander = Float((x * 7 + y * 13) % 5) / 4 - 0.5
            return Self.coverage(x, y, radius: 80 + wander) >= 0.5 ? 1 : 0
        }
        let m = try Self.measure(stepped)
        let box = try #require(m.rough)
        #expect(try #require(m.render.outline) >= LayerEdge.roughOutline)
        #expect(box.x0 >= 0 && box.x1 <= Self.side && box.width >= 64)
        #expect(m.banded == nil && m.mottled == nil)
    }

    /// A lighter rim 2 px wide inside the outline, which the pick does not have.
    @Test func aRimThePickLacksIsABand() throws {
        let rim = Self.picture(cover: Self.smooth) { x, y in
            let r = ((Float(x) + 0.5 - 128) * (Float(x) + 0.5 - 128) + (Float(y) + 0.5 - 128) * (Float(y) + 0.5 - 128)).squareRoot()
            return r > 77 ? Self.grey + 0.25 : Self.grey
        }
        let m = try Self.measure(rim)
        #expect(m.banded != nil)
        #expect(try #require(m.render.band) > LayerEdge.bandMargin)
    }

    @Test func aMottledFillIsFound() throws {
        let mottled = Self.picture(cover: Self.smooth) { x, y in Self.grey + Float((x * 31 + y * 17) % 7) / 60 - 0.05 }
        let m = try Self.measure(mottled)
        let box = try #require(m.mottled)
        #expect(box.width >= 64 && box.height >= 64)
    }

    /// quiet-pick's tile drawn a shade lighter than the pick: off in colour, while its outline is as plain.
    @Test func aLighterFillIsOffColour() throws {
        let m = try Self.measure(Self.picture(cover: Self.smooth) { _, _ in Self.grey + 0.06 })
        #expect(m.offColour && m.warns)
        #expect(m.rough == nil && m.banded == nil && m.mottled == nil)
        #expect(try #require(m.render.lightness) > (try #require(m.pick.lightness)))
        #expect(!(try Self.measure(Self.picture(cover: Self.smooth) { _, _ in Self.grey + 0.005 })).offColour)
    }

    /// `"match": true` moves a lighter, tinted copy onto the pick's colour and keeps its shading.
    @Test func matchTakesThePicksColour() throws {
        let pick = Self.picture(cover: Self.smooth)
        var drawn = Self.layer()
        for y in 0..<Self.side {
            for x in 0..<Self.side {
                let shade = Float(x % 2) * 0.02
                drawn[x, y] = SIMD4(SIMD3(0.31 + shade, 0.33 + shade, 0.30 + shade), drawn[x, y].w)
            }
        }
        let (matched, shift) = try #require(drawn.matched(to: pick))
        #expect(shift.x < 0)
        let middle = matched[128, 128], beside = matched[129, 128]
        for c in 0..<3 { #expect(abs((middle[c] + beside[c]) / 2 - Self.grey[c]) < 0.015) }
        #expect(beside.x - middle.x > 0.01)
        #expect(matched[128, 128].w == drawn[128, 128].w && matched[0, 0].w == 0)
    }

    /// `"dark": "pick"` takes a brown disc back to the pick's grey. Its darker rim, less brown than its middle, goes
    /// grey too: a flat OKLab shift sent it past neutral into blue.
    @Test func recolourTurnsABrownDiscGreyWithoutABlueRim() throws {
        let pick = Self.picture(cover: Self.smooth)
        var drawn = Self.layer()
        for y in 0..<Self.side {
            for x in 0..<Self.side {
                let d = (Float(x - 128) * Float(x - 128) + Float(y - 128) * Float(y - 128)).squareRoot()
                let colour: SIMD3<Float> = d > 72 ? [0.20, 0.17, 0.15] : [0.29, 0.20, 0.12]
                drawn[x, y] = SIMD4(colour, drawn[x, y].w)
            }
        }
        let grey = try #require(drawn.recoloured(to: pick))
        func chroma(_ p: SIMD4<Float>) -> Float { max(p.x, p.y, p.z) - min(p.x, p.y, p.z) }
        #expect(chroma(grey[128, 128]) < 0.01)
        let rim = grey[128 + 76, 128]
        #expect(chroma(rim) < 0.01 && rim.z <= rim.x + 0.005)
        #expect(abs(grey[128, 128].x - Self.grey.x) < 0.015)
        #expect(grey[0, 0].w == 0)
        // the flat shift is what tinted it
        let shifted = try #require(drawn.matched(to: pick)).image[128 + 76, 128]
        #expect(shifted.z > shifted.x + 0.01)
    }

    /// `"dark": {"tone": ...}` lands the grey disc's middle on the plan's colour and keeps its shading: the rim stays
    /// darker than the middle, and alpha is untouched.
    @Test func toneMovesALayerOntoTheGivenColour() throws {
        var drawn = Self.layer()
        for y in 0..<Self.side {
            for x in 0..<Self.side {
                let d = (Float(x - 128) * Float(x - 128) + Float(y - 128) * Float(y - 128)).squareRoot()
                drawn[x, y] = SIMD4(SIMD3(repeating: d > 72 ? 0.18 : 0.24), drawn[x, y].w)
            }
        }
        let blue: SIMD3<Float> = [0.16, 0.22, 0.40]
        let toned = try #require(drawn.recoloured(toColour: blue))
        for c in 0..<3 { #expect(abs(toned[128, 128][c] - blue[c]) < 0.015) }
        let rim = toned[128 + 76, 128]
        #expect(rim.z > rim.x && rim.z < toned[128, 128].z)
        #expect(toned[128, 128].w == drawn[128, 128].w && toned[0, 0].w == 0)
    }
}
