import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import RimlightCore

@Suite struct BackgroundCutoutTests {
    /// A tile on a flat ground, at Apple's place in the frame unless `fullBleed`.
    static func painted(
        ground: CGColor, tile: CGColor = CGColor(srgbRed: 0.2, green: 0.3, blue: 0.6, alpha: 1), fullBleed: Bool = false,
        size: Int = 256
    ) throws -> Data {
        try DrawnPNG.rgba(size: size) { context, frame in
            context.setFillColor(ground)
            context.fill(frame)
            let rect = fullBleed ? frame : frame.insetBy(dx: frame.width * 0.092, dy: frame.height * 0.092)
            let radius = rect.width * 0.22
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.setFillColor(tile)
            context.fillPath()
            // Something on the tile in the ground's own colour, which must survive.
            context.setFillColor(ground)
            context.fillEllipse(in: CGRect(x: frame.midX - 20, y: frame.midY - 20, width: 40, height: 40))
        }
    }

    func cut(_ data: Data) throws -> (BackgroundCutout.Method?, ImageProbe?, Pixels?) {
        try withTempDir { dir in
            let input = dir.appending(path: "in.png")
            let output = dir.appending(path: "out.png")
            try data.write(to: input)
            let method = BackgroundCutout.cut(input, to: output)
            guard method != nil else { return (nil, nil, nil) }
            let image = try #require(CGImageSourceCreateWithURL(output as CFURL, nil).flatMap {
                CGImageSourceCreateImageAtIndex($0, 0, nil)
            })
            return (method, ImageProbe.read(output), Pixels(image))
        }
    }

    /// Grok's case: the tile in its place on black. The black dot on the tile stays.
    @Test func aFlatGroundIsClearedAroundTheTile() throws {
        let (method, probe, pixels) = try cut(try Self.painted(ground: CGColor(gray: 0, alpha: 1)))
        #expect(method == .ground)
        #expect(probe?.isTransparent == true)
        let p = try #require(pixels)
        let centre = (p.side / 2) * p.side + p.side / 2
        #expect(p.alpha(centre) == 255, "the dot inside the tile is not ground")
        #expect(p.alpha(0) == 0)
    }

    /// A tile drawn edge to edge on white loses only its corners, and the fit takes it.
    @Test func aFullBleedTileLosesOnlyItsCorners() throws {
        let data = try Self.painted(ground: CGColor(gray: 1, alpha: 1), fullBleed: true)
        let (method, probe, pixels) = try cut(data)
        #expect(method == .ground)
        #expect(probe?.isTransparent == true)
        let p = try #require(pixels)
        #expect(p.alpha(p.side / 2) == 255, "the middle of the top edge is tile")
        try withTempDir { dir in
            let input = dir.appending(path: "in.png")
            let cut = dir.appending(path: "cut.png")
            try data.write(to: input)
            #expect(BackgroundCutout.cut(input, to: cut) == .ground)
            let fit = try TileShape.conform(cut, to: dir.appending(path: "fit.png"))
            #expect(fit.drawnWidth == p.side)
        }
    }

    /// Codex's painted checkerboard, two greys.
    @Test func aCheckerboardIsCleared() throws {
        let data = try DrawnPNG.rgba(size: 256) { context, frame in
            for y in stride(from: 0, to: 256, by: 16) {
                for x in stride(from: 0, to: 256, by: 16) {
                    context.setFillColor(gray: (x / 16 + y / 16).isMultiple(of: 2) ? 0.93 : 0.8, alpha: 1)
                    context.fill(CGRect(x: x, y: y, width: 16, height: 16))
                }
            }
            let rect = frame.insetBy(dx: 24, dy: 24)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 46, cornerHeight: 46, transform: nil))
            context.setFillColor(CGColor(srgbRed: 0.85, green: 0.35, blue: 0.2, alpha: 1))
            context.fillPath()
        }
        let (method, probe, _) = try cut(data)
        #expect(method == .ground)
        #expect(probe?.isTransparent == true)
    }

    /// Codex's painted checkerboard as it really comes: squares with soft seams between them
    /// and noise everywhere, which leave specks the flood can't reach.
    @Test func aNoisyCheckerboardWithSoftSeamsIsCleared() throws {
        var rng = SystemRandomNumberGenerator()
        let data = try DrawnPNG.rgba(size: 256) { context, frame in
            for y in 0..<256 {
                for x in 0..<256 {
                    let cellX = x % 12, cellY = y % 12
                    let light = ((x / 12) + (y / 12)).isMultiple(of: 2)
                    // A one-pixel seam halfway between the greys, then noise.
                    let seam = cellX == 0 || cellY == 0
                    var grey = seam ? 0.62 : (light ? 0.73 : 0.5)
                    grey += Double.random(in: -0.05...0.05, using: &rng)
                    context.setFillColor(gray: grey, alpha: 1)
                    context.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
            let rect = frame.insetBy(dx: 24, dy: 24)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 46, cornerHeight: 46, transform: nil))
            context.setFillColor(CGColor(srgbRed: 0.96, green: 0.93, blue: 0.88, alpha: 1))
            context.fillPath()
        }
        let (method, probe, _) = try cut(data)
        #expect(method == .ground)
        #expect(probe?.isTransparent == true)
    }

    /// Corners that aren't a ground, a drawing running off the frame, are left alone.
    @Test func busyCornersAreNotAGround() throws {
        let data = try DrawnPNG.rgba(size: 128) { context, frame in
            for y in 0..<128 {
                for x in 0..<128 {
                    context.setFillColor(
                        CGColor(srgbRed: CGFloat(x) / 128, green: CGFloat(y) / 128, blue: CGFloat((x * y) % 97) / 97, alpha: 1))
                    context.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        let (method, _, _) = try cut(data)
        #expect(method == nil)
    }

    /// A model that draws transparency gets its paid fixes first; the cutout comes only after
    /// they all fail, and not at all when one works.
    @Test func paidFixesComeFirstAndTheCutoutLast() throws {
        try withTempDir { dir in
            let opaque = dir.appending(path: "opaque.png")
            try Self.painted(ground: CGColor(gray: 0, alpha: 1)).write(to: opaque)
            let probe = try #require(ImageProbe.read(opaque))
            var renders = 0
            let failed = TransparencyFix.run(
                opaque, probe: probe, original: ImageRequest(prompt: "A dial."), attempts: 3,
                cutout: dir.appending(path: "cut.png"),
                render: { _, n in
                    renders += 1
                    let painted = dir.appending(path: "painted-\(n).png")
                    try FileManager.default.copyItem(at: opaque, to: painted)
                    return .init(image: painted, model: "m")
                })
            #expect(renders == 3)
            #expect(failed.attempts.map(\.kind) == [.transparencyEdit, .reroll, .transparencyEdit, .cutout])
            #expect(failed.cutout && failed.isFixed && failed.paidAttempts == 3 && failed.fixModel == nil)
            #expect(failed.source == opaque)

            let clear = dir.appending(path: "clear.png")
            try DrawnPNG.transparent(size: 256).write(to: clear)
            let fixed = TransparencyFix.run(
                opaque, probe: probe, original: nil, attempts: 3, cutout: dir.appending(path: "cut2.png"),
                render: { _, _ in .init(image: clear, model: "m") })
            #expect(fixed.attempts.map(\.kind) == [.transparencyEdit])
            #expect(!fixed.cutout && fixed.fixModel == "m")
        }
    }

    /// A model that can't draw transparency gets the cutout alone, no paid render.
    @Test func aModelWithoutTransparencyGetsOnlyTheCutout() throws {
        try withTempDir { dir in
            let opaque = dir.appending(path: "opaque.png")
            try Self.painted(ground: CGColor(gray: 0, alpha: 1)).write(to: opaque)
            var renders = 0
            let outcome = TransparencyFix.run(
                opaque, probe: try #require(ImageProbe.read(opaque)), original: ImageRequest(prompt: "A dial."),
                attempts: 3, cutout: dir.appending(path: "cut.png"), paid: false,
                render: { _, _ in
                    renders += 1
                    throw ImageFailure.noImage("no render expected")
                })
            #expect(renders == 0)
            #expect(outcome.cutout && outcome.paidAttempts == 0)
            #expect(outcome.source == opaque)
            #expect(outcome.attempts.map(\.kind) == [.cutout])
        }
    }
}
