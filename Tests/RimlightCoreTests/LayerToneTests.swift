import Foundation
import Testing

@testable import RimlightCore

@Suite struct LayerToneTests {
    /// A layer laid over a flat key colour, as Codex hands it back: opaque.
    private func onKey(_ layer: LayerImage, key: SIMD3<Float>) -> LayerImage {
        layer.over(LayerImage(width: layer.width, height: layer.height, fill: SIMD4(key, 1)))
    }

    /// A disc of one colour with a soft rim: solid inside radius 20, clear past 26.
    private func disc(_ colour: SIMD3<Float>) -> LayerImage {
        var image = LayerImage(side: 64)
        for y in 0..<64 {
            for x in 0..<64 {
                let r = ((Float(x) - 32) * (Float(x) - 32) + (Float(y) - 32) * (Float(y) - 32)).squareRoot()
                image[x, y] = SIMD4(colour, min(max((26 - r) / 6, 0), 1))
            }
        }
        return image
    }

    @Test func theMagentaKeyGivesBackTheSolidPartAndClearsTheKey() {
        let colour: SIMD3<Float> = [0.2, 0.6, 0.3]
        let layer = disc(colour)
        let drawn = onKey(layer, key: [1, 0, 1])
        #expect(!drawn.hasAlpha && drawn.isOnMagenta)
        let back = drawn.unkeyedMagenta()
        for y in 0..<64 {
            for x in 0..<64 {
                let truth = layer[x, y], p = back[x, y]
                if truth.w == 1 {
                    #expect(p.w == 1 && abs(p.x - colour.x) < 1e-5 && abs(p.y - colour.y) < 1e-5 && abs(p.z - colour.z) < 1e-5)
                }
                if truth.w == 0 { #expect(p.w == 0) }
                // The rim keeps its order: more of the layer, more alpha.
                if truth.w > 0.5 { #expect(p.w > 0.5) }
            }
        }
        #expect(back.hasAlpha && !back.isOnMagenta)
    }

    /// Light on black: brightness is alpha, so a glow comes back with its own alpha and colour.
    @Test func theBlackKeyGivesBackAGlow() {
        let colour: SIMD3<Float> = [1, 0.7, 0.2]
        let layer = disc(colour)
        let back = onKey(layer, key: [0, 0, 0]).unkeyedBlack()
        for y in 0..<64 {
            for x in 0..<64 {
                let truth = layer[x, y], p = back[x, y]
                #expect(abs(p.w - truth.w) < 0.021)
                if truth.w > 0.1 {
                    #expect(abs(p.x - colour.x) < 1e-4 && abs(p.y - colour.y) < 1e-4 && abs(p.z - colour.z) < 1e-4)
                }
            }
        }
    }

    @Test func alphaAndMagentaChecksUseThePrototypesBytes() {
        var image = LayerImage(side: 10, fill: SIMD4(0.5, 0.5, 0.5, 1))
        image[0, 0] = SIMD4(0.5, 0.5, 0.5, 251 / 255)
        #expect(!image.hasAlpha)
        image[0, 0] = SIMD4(0.5, 0.5, 0.5, 249 / 255)
        #expect(image.hasAlpha)
        // A fifth of the pixels is not enough; one more is.
        var keyed = LayerImage(side: 10, fill: SIMD4(0.5, 0.5, 0.5, 1))
        for i in 0..<20 { keyed[i % 10, i / 10] = SIMD4(1, 0, 1, 1) }
        #expect(!keyed.isOnMagenta)
        keyed[0, 2] = SIMD4(225 / 255, 35 / 255, 225 / 255, 1)
        #expect(keyed.isOnMagenta)
    }

    @Test func greyKeepsLuminanceAndAlpha() {
        let image = LayerImage(side: 2, fill: SIMD4(0.8, 0.4, 0.2, 0.7))
        let grey = image.greyed()[1, 1]
        let y: Float = 0.2126 * 0.8 + 0.7152 * 0.4 + 0.0722 * 0.2
        #expect(abs(grey.x - y) < 1e-6 && grey.x == grey.y && grey.y == grey.z && grey.w == 0.7)
    }

    @Test func dimmingIsOpaqueAtFourFifths() {
        let dim = LayerImage(side: 2, fill: SIMD4(0.5, 0.25, 1, 1)).dimmed()[0, 1]
        #expect(dim == SIMD4(0.4, 0.2, 0.8, 1))
    }

    /// Dark's copy of a layer loses the ground's hue (the caliper's black button had an orange ring in its socket)
    /// and keeps every other; a part that is itself the ground's colour is left alone.
    @Test func darksCopyLosesTheGroundsColourOnly() throws {
        let orange = SIMD3<Float>(0.96, 0.43, 0.05)
        var button = LayerImage(width: 10, height: 1, fill: SIMD4(0.2, 0.2, 0.2, 1))
        button[0, 0] = SIMD4(0.3, 0.15, 0.03, 1)  // the socket's orange reflection
        button[1, 0] = SIMD4(0.1, 0.3, 0.6, 1)  // a blue detail
        let dark = try #require(button.withoutCast(of: orange))
        let ring = dark[0, 0]
        // 1.7° off the ground's hue, it keeps a trace: under a twentieth of its saturation
        #expect((max(ring.x, ring.y, ring.z) - min(ring.x, ring.y, ring.z)) / max(ring.x, ring.y, ring.z) < 0.05)
        #expect(dark[1, 0] == button[1, 0])
        #expect(dark[5, 0] == button[5, 0])
        // an orange part on an orange ground is orange, and a grey ground has no hue to take out
        #expect(LayerImage(width: 4, height: 1, fill: SIMD4(0.9, 0.45, 0.1, 1)).withoutCast(of: orange) == nil)
        #expect(button.withoutCast(of: SIMD3(0.5, 0.5, 0.52)) == nil)
    }

    /// A part on magenta whose right side starts at x = 10, every row alike, as Codex draws an edge: `edge` lists the
    /// pixels from the key into the part, then the part's colour runs on. As wide as Codex draws, so the outline's
    /// ring is its real 2 px.
    private func edgeRow(_ edge: [SIMD3<Float>], part: SIMD3<Float>, width: Int = LayerImage.referenceSide) -> LayerImage {
        var image = LayerImage(width: width, height: 12, fill: SIMD4(1, 0, 1, 1))
        for y in 0..<12 {
            for x in 10..<width { image[x, y] = SIMD4(x - 10 < edge.count ? edge[x - 10] : part, 1) }
        }
        return image
    }

    /// quiet-pick's grey tile on magenta, with the edge Codex drew: a pixel two thirds magenta, then one of purple and
    /// one of green where its channels change a pixel apart. The key gives back the tile's own grey along the whole
    /// edge, and the partial pixel's alpha is how far it lies from the key towards the grey.
    @Test func aDarkPartsFringeBecomesItsOwnColour() {
        let grey = SIMD3<Float>(61, 66, 60) / 255
        let keyed = edgeRow([SIMD3(188, 29, 188) / 255, SIMD3(54, 49, 54) / 255, SIMD3(62, 71, 60) / 255], part: grey).unkeyedMagenta()
        let partial = keyed[10, 6]
        #expect(abs(partial.w - 0.35) < 0.03)
        for x in 10..<14 {
            let p = keyed[x, 6]
            #expect(abs(p.x - grey.x) < 1e-3 && abs(p.y - grey.y) < 1e-3 && abs(p.z - grey.z) < 1e-3, "x \(x): \(p)")
        }
        #expect(keyed[11, 6].w == 1 && keyed[9, 6].w == 0)
    }

    /// The magenta key's spill goes from a pixel along the outline that is not the part's colour, even where the
    /// alpha reads solid (sleep-dial's pointer had a purple line along its shaded edge); a purple part stays purple
    /// to its edge.
    @Test func theMagentaKeysSpillLeavesTheOutline() {
        let orange = SIMD3<Float>(0.95, 0.6, 0.2)
        let shaded = edgeRow([SIMD3(0.25, 0.05, 0.25), SIMD3(0.25, 0.05, 0.25)], part: orange).unkeyedMagenta()
        let line = shaded[10, 6]
        #expect(line.w == 1 && line.x <= line.y + 1e-5 && line.z <= line.y + 1e-5)
        #expect(shaded[30, 6] == SIMD4(orange, 1))

        let purple = SIMD3<Float>(0.35, 0.1, 0.45)
        let part = edgeRow([SIMD3(0.4, 0.15, 0.4)], part: purple).unkeyedMagenta()
        let edge = part[10, 6]
        #expect(edge.w == 1 && edge.x > edge.y + 0.2 && edge.z > edge.y + 0.2)
        #expect(part[30, 6] == SIMD4(purple, 1))
    }

    /// A tone takes the hue away and keeps the shading: a pixel at the ground's mean brightness becomes the colour,
    /// a darker one darker in the same proportion.
    @Test func aToneKeepsTheGroundsShading() {
        var orange = LayerImage(width: 2, height: 1, fill: SIMD4(1, 0.5, 0, 1))
        orange[1, 0] = SIMD4(0.5, 0.25, 0, 1)
        let black = SIMD3<Float>(0.1, 0.1, 0.12)
        let toned = orange.toned(black)
        let a = toned[0, 0], b = toned[1, 0]
        #expect(a.w == 1 && b.w == 1)
        // the two pixels' luminance is 2:1 and their mean is 0.75 of the first
        #expect(abs(a.x - 0.1 * 4 / 3) < 1e-5 && abs(a.z - 0.12 * 4 / 3) < 1e-5)
        #expect(abs(b.x - 0.1 * 2 / 3) < 1e-5)
    }

    /// The lift stretches the solid part's shading onto 0.62...1: its darkest 2% at 0.62,
    /// brightest 2% at 1, and a clear pixel does not count.
    @Test func theHeroLiftSpansFromLightGreyToWhite() {
        var image = LayerImage(width: 100, height: 2)
        for x in 0..<100 {
            image[x, 0] = SIMD4(repeating: Float(x) / 99) * SIMD4(1, 1, 1, 0) + SIMD4(0, 0, 0, 1)
            image[x, 1] = SIMD4(1, 1, 1, 0)  // clear and white: ignored by the percentiles
        }
        let lifted = image.lifted()
        #expect(abs(lifted[0, 0].x - 0.62) < 1e-5 && abs(lifted[1, 0].x - 0.62) < 1e-5)
        #expect(abs(lifted[99, 0].x - 1) < 1e-5)
        #expect(abs(lifted[50, 0].x - (0.62 + 0.38 * (50 - 1.98) / (97.02 - 1.98))) < 1e-4)
        #expect(lifted[5, 1].w == 0 && lifted[5, 0].w == 1)
    }

    /// A flat layer's spread is its dither; stretched onto the whole range it came out as grain in Clear and Tinted.
    /// It lifts to a flat light grey, and a shaded layer keeps its shading as before.
    @Test func aFlatHeroLiftsWithoutGrain() {
        var flat = LayerImage(width: 64, height: 64)
        for y in 0..<64 {
            for x in 0..<64 {
                // a near-black tile with a one-step dither, as a PNG of a flat colour carries
                let v = Float(28 + (x + y) % 2) / 255
                flat[x, y] = SIMD4(v, v, v, 1)
            }
        }
        let lifted = flat.lifted()
        var lo: Float = 1, hi: Float = 0
        for y in 0..<64 { for x in 0..<64 { lo = min(lo, lifted[x, y].x); hi = max(hi, lifted[x, y].x) } }
        // a dither of 1/255 stays under 2/255 after the lift, about the middle of the range; it was stretched 95 times
        #expect(hi - lo < 2 / 255)
        #expect(abs((lo + hi) / 2 - 0.81) < 0.01)

        // shading wider than the floor is stretched exactly as before
        var shaded = LayerImage(width: 100, height: 1)
        for x in 0..<100 { shaded[x, 0] = SIMD4(SIMD3(repeating: 0.2 + 0.3 * Float(x) / 99), 1) }
        let s = shaded.lifted()
        #expect(abs(s[0, 0].x - 0.62) < 1e-5 && abs(s[99, 0].x - 1) < 1e-5)
    }

    /// Invert flips lightness and keeps hue: a warm near-black becomes a warm near-white, where a plain RGB invert
    /// turns warm into cool. Alpha stays, and inverting twice gives the colour back.
    @Test func invertMakesAWarmBlackAWarmWhite() {
        var image = LayerImage(width: 3, height: 1)
        image[0, 0] = SIMD4(0x1c, 0x1b, 0x19, 255) / 255  // the eclipse's warm black
        image[1, 0] = SIMD4(0x1c, 0x1b, 0x19, 128) / 255
        image[2, 0] = SIMD4(0.85, 0.3, 0.2, 1)
        let inverted = image.inverted()
        let white = inverted[0, 0]
        // near-white
        #expect(white.x > 0.85 && white.y > 0.85 && white.z > 0.85)
        // still warm: red over blue, as the black had, where 1 - rgb would put blue over red
        #expect(white.x > white.z)
        #expect(LayerImage.hsv(SIMD3(white.x, white.y, white.z)).h < 60)
        #expect(inverted[1, 0].w == image[1, 0].w && inverted[0, 0].w == 1)
        // a red stays red
        #expect(LayerImage.hueDistance(LayerImage.hsv(SIMD3(inverted[2, 0].x, inverted[2, 0].y, inverted[2, 0].z)).h, 10) < 15)
        let back = inverted.inverted()
        for x in 0..<2 {
            #expect(abs(back[x, 0].x - image[x, 0].x) < 2e-3 && abs(back[x, 0].z - image[x, 0].z) < 2e-3)
        }
    }
}
