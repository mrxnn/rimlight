import Foundation
import Testing

@testable import RimlightCore

@Suite struct LayerFitTests {
    static let side = 1024

    /// A ground with gentle shading and a fine weave, so it is not flat anywhere.
    static let ground: LayerImage = {
        var image = LayerImage(side: side)
        for y in 0..<side {
            for x in 0..<side {
                let weave = 0.03 * sin(Float(x) * 0.7) * sin(Float(y) * 0.7)
                image[x, y] = SIMD4(0.85 - Float(y) / 8000 + weave, 0.8 + weave, 0.7 + Float(x) / 9000, 1)
            }
        }
        return image
    }()

    /// A textured disc off the centre: rings and stripes of colour with a 2 px soft rim.
    static let disc: LayerImage = {
        var image = LayerImage(side: side)
        let cx: Float = 600, cy: Float = 430, radius: Float = 170
        for y in 0..<side {
            for x in 0..<side {
                let dx = Float(x) - cx, dy = Float(y) - cy
                let r = (dx * dx + dy * dy).squareRoot()
                let a = min(max((radius - r) / 2, 0), 1)
                guard a > 0 else { continue }
                let rings = 0.5 + 0.4 * sin(r / 9)
                let stripes = 0.5 + 0.4 * sin((dx + 2 * dy) / 14)
                image[x, y] = SIMD4(rings, stripes, 0.3 + 0.4 * (dx + radius) / (2 * radius), a)
            }
        }
        return image
    }()

    /// The concept: `layer` laid over the ground at `fit`.
    private func concept(_ layer: LayerImage, at fit: LayerFit.Fit, under: LayerImage = ground) -> LayerImage {
        LayerFit.place(layer, with: fit).over(under)
    }

    private func expectNear(_ fit: LayerFit.Fit, _ truth: LayerFit.Fit, shift: Double = 1.5, scale: Double = 0.006) {
        #expect(abs(fit.scale - truth.scale) <= scale * truth.scale, "scale \(fit.scale), not \(truth.scale)")
        #expect(abs(fit.dx - truth.dx) <= shift, "dx \(fit.dx), not \(truth.dx)")
        #expect(abs(fit.dy - truth.dy) <= shift, "dy \(fit.dy), not \(truth.dy)")
    }

    @Test func aKeyedLayerIsFoundNearWhereItWasDrawn() throws {
        let truth = LayerFit.Fit(scale: 0.975, dx: 12, dy: -7)
        let placed = try LayerFit.fit(Self.disc, concept: concept(Self.disc, at: truth), under: Self.ground, mode: .keyed)
        expectNear(placed.fit, truth)
        #expect(placed.fit.opacity == 1)
        #expect(placed.layer.width == Self.side && placed.layer[0, 0].w == 0)
    }

    /// A boxed layer starts from the plan's rough box, here 3% too big and 10 px off.
    @Test func aBoxedLayerIsFoundFromARoughBox() throws {
        let truth = LayerFit.Fit(scale: 0.95, dx: 12, dy: -7)
        // Where the disc lands: centre 512 + 0.95 (600 − 512) + 12, radius 0.95 · 170.
        let cx = 512 + 0.95 * 88 + 12, cy = 512 + 0.95 * (430 - 512) - 7, r = 0.95 * 170 * 1.03
        let box = LayerBox(x0: Int(cx - r) + 10, y0: Int(cy - r) - 10, x1: Int(cx + r) + 10, y1: Int(cy + r) - 10)
        let placed = try LayerFit.fit(Self.disc, concept: concept(Self.disc, at: truth), under: Self.ground, mode: .boxed(box))
        expectNear(placed.fit, truth)
    }

    /// The keycap: one flat blue square over the ground. Scored by the error over the layer
    /// alone, any smaller square inside the real one scores perfectly; scored on the whole
    /// picture, only the true size covers all the blue.
    @Test func aFlatLayerIsNotShrunkIntoItsOwnInside() throws {
        var square = LayerImage(side: Self.side)
        for y in 300..<720 { for x in 280..<700 { square[x, y] = SIMD4(0.1, 0.3, 0.8, 1) } }
        let picture = square.over(Self.ground)
        let keyed = try LayerFit.fit(square, concept: picture, under: Self.ground, mode: .keyed)
        expectNear(keyed.fit, .identity, scale: 0.003)
        // A box 4% small seeds the search at 0.96.
        let boxed = try LayerFit.fit(square, concept: picture, under: Self.ground, mode: .boxed(LayerBox(x0: 290, y0: 310, x1: 693, y1: 713)))
        expectNear(boxed.fit, .identity, scale: 0.003)
    }

    /// A glow drawn at full strength sits in the concept at 0.55: the fit finds the opacity.
    @Test func aSoftLayersOpacityIsFitted() throws {
        var glow = LayerImage(side: Self.side)
        for y in 200..<800 {
            for x in 200..<800 {
                let r = ((Float(x) - 500) * (Float(x) - 500) + (Float(y) - 480) * (Float(y) - 480)).squareRoot()
                glow[x, y] = SIMD4(1, 0.85, 0.5, min(max(1 - r / 280, 0), 1))
            }
        }
        let dark = LayerImage(side: Self.side, fill: SIMD4(0.08, 0.1, 0.16, 1))
        let truth = LayerFit.Fit(scale: 1, dx: 0, dy: 0, opacity: 0.55)
        let placed = try LayerFit.fit(glow, concept: concept(glow, at: truth, under: dark), under: dark, mode: .keyed, soft: true)
        #expect(abs(placed.fit.opacity - 0.55) < 0.026)
        expectNear(placed.fit, truth, shift: 2)
        #expect(abs(placed.layer[500, 480].w - 0.55) < 0.03)
    }

    @Test func placingKeepsTheLayerAndClearsOutside() {
        let moved = LayerFit.place(Self.disc, with: LayerFit.Fit(scale: 1, dx: 10, dy: -4))
        let a = moved[610, 426], b = Self.disc[600, 430]
        #expect(b.w > 0.99 && abs(a.x - b.x) < 1e-5 && abs(a.y - b.y) < 1e-5 && abs(a.z - b.z) < 1e-5 && abs(a.w - b.w) < 1e-6)
        let small = LayerFit.place(Self.disc, with: LayerFit.Fit(scale: 0.5, dx: 0, dy: 0))
        // The disc's centre goes to 512 + 0.5 (600 − 512), 512 + 0.5 (430 − 512).
        #expect(small[556, 471].w > 0.99)
        #expect(small[556 + 90, 471].w < 0.001)
        let faded = LayerFit.place(Self.disc, with: LayerFit.Fit(scale: 1, dx: 0, dy: 0, opacity: 0.5))
        #expect(abs(faded[600, 430].w - 0.5) < 1e-6)
    }

    @Test func badInputsThrow() {
        #expect(throws: LayerImage.Failure.self) {
            try LayerFit.fit(LayerImage(side: 64), concept: LayerImage(side: 64), under: LayerImage(side: 64), mode: .keyed)
        }
        #expect(throws: LayerImage.Failure.self) {
            try LayerFit.fit(Self.disc, concept: LayerImage(width: 64, height: 32), under: LayerImage(side: 64), mode: .keyed)
        }
    }
}

/// The prototype's own drawings, when this Mac has them: the fit lands where `lt.py` put them.
@Suite struct LayerFitTrialTests {
    /// Beside the package in the workspace; a clone without it skips these tests.
    static let work = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Rimlight-Research/layer-trial/work")
    static var hasTrial: Bool { FileManager.default.fileExists(atPath: work.appending(path: "notebook-corner/gen/pages.png").path) }

    private func image(_ path: String) throws -> LayerImage { try LayerImage.read(Self.work.appending(path: path)) }

    private func expectNear(_ fit: LayerFit.Fit, _ scale: Double, _ dx: Double, _ dy: Double) {
        #expect(abs(fit.scale - scale) <= 0.01, "scale \(fit.scale), the prototype's \(scale)")
        #expect(abs(fit.dx - dx) <= 3 && abs(fit.dy - dy) <= 3, "shift \(fit.dx), \(fit.dy), the prototype's \(dx), \(dy)")
    }

    @Test(.enabled(if: hasTrial)) func rowsTwentySixsDotsOnBlack() throws {
        let concept = try image("rows-twenty-six/concept.png")
        let drawn = try image("rows-twenty-six/gen/dots.png").resized(to: 1024)
        let started = Date()
        let placed = try LayerFit.fit(drawn.unkeyedBlack(), concept: concept, under: image("rows-twenty-six/layers/slab.png"), mode: .keyed)
        print("rows-twenty-six/dots: \(placed.fit) in \(Date().timeIntervalSince(started)) s")
        expectNear(placed.fit, 1.0015, 0, 0)
    }

    @Test(.enabled(if: hasTrial)) func notebookCornersPagesOnMagentaAndItsBandBoxed() throws {
        let concept = try image("notebook-corner/concept.png")
        let cover = try image("notebook-corner/layers/cover.png")
        let pages = try image("notebook-corner/gen/pages.png").resized(to: 1024)
        #expect(pages.isOnMagenta)
        var started = Date()
        let placedPages = try LayerFit.fit(pages.unkeyedMagenta(), concept: concept, under: cover, mode: .keyed)
        print("notebook-corner/pages: \(placedPages.fit) in \(Date().timeIntervalSince(started)) s")
        expectNear(placedPages.fit, 1.0025, -2, 2)

        // The band over the cover and the prototype's own pages, as it was fitted there.
        let under = try image("notebook-corner/layers/pages.png").over(cover)
        let band = try image("notebook-corner/gen/band.png").resized(to: 1024)
        #expect(band.hasAlpha)
        started = Date()
        let placedBand = try LayerFit.fit(band, concept: concept, under: under, mode: .boxed(LayerBox(x0: 610, y0: 18, x1: 882, y1: 1024)))
        print("notebook-corner/band: \(placedBand.fit) in \(Date().timeIntervalSince(started)) s")
        expectNear(placedBand.fit, 1.0453, -8.9, -23.6)
    }
}

extension LayerFitTrialTests {
    /// sodium-lamp's glow, boxed and soft. Scored at each place's own best opacity it lands 8 px
    /// from where the prototype put it (placed at full strength first, then faded), with a
    /// lower whole-picture error.
    @Test(.enabled(if: hasTrial)) func sodiumLampsGlowIsSoft() throws {
        let concept = try image("sodium-lamp/concept.png")
        var under = try image("sodium-lamp/layers/sky.png")
        for name in ["road", "lamp"] { under = try image("sodium-lamp/layers/\(name).png").over(under) }
        let glow = try image("sodium-lamp/gen/glow.png").resized(to: 1024)
        let box = LayerBox(x0: 430, y0: 70, x1: 850, y1: 520)
        let started = Date()
        let soft = try LayerFit.fit(glow, concept: concept, under: under, mode: .boxed(box), soft: true)
        print("sodium-lamp/glow: \(soft.fit) in \(Date().timeIntervalSince(started)) s")
        #expect(abs(soft.fit.scale - 1.0385) <= 0.01)
        #expect(abs(soft.fit.dx + 57) <= 10 && abs(soft.fit.dy + 67.5) <= 10)
        #expect(soft.fit.opacity > 0.2 && soft.fit.opacity < 0.6)

        let prototype = LayerFit.place(glow, with: LayerFit.Fit(scale: 1.0385, dx: -57, dy: -67.5, opacity: soft.fit.opacity))
        func error(_ placed: LayerImage) -> Double {
            let picture = placed.over(under)
            var sum = 0.0
            for i in stride(from: 0, to: picture.pixels.count, by: 4) {
                for c in i..<(i + 3) { sum += Double((picture.pixels[c] - concept.pixels[c]) * (picture.pixels[c] - concept.pixels[c])) }
            }
            return sum
        }
        #expect(error(soft.layer) < error(prototype))
    }
}
