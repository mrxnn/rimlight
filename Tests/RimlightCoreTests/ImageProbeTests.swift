import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import RimlightCore

/// RGBA PNGs drawn with CoreGraphics and encoded by ImageIO, like a real render.
enum DrawnPNG {
    /// A `size` px RGBA PNG; `draw` paints into a cleared context.
    static func rgba(size: Int, _ draw: (CGContext, CGRect) -> Void) throws -> Data {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        draw(context, CGRect(x: 0, y: 0, width: size, height: size))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    /// The icon: a rounded tile filling 92% of the frame, as the prompts ask.
    static func tile(_ context: CGContext, _ frame: CGRect) {
        let rect = frame.insetBy(dx: frame.width * 0.04, dy: frame.height * 0.04)
        let radius = rect.width * 0.22
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.setFillColor(CGColor(srgbRed: 0.94, green: 0.91, blue: 0.85, alpha: 1))
        context.fillPath()
    }

    /// A transparent background with the tile on it.
    static func transparent(size: Int = 1254) throws -> Data { try rgba(size: size, tile) }

    /// The tile on a painted grey checkerboard: an RGBA file whose alpha is 255 everywhere.
    static func checkerboard(size: Int = 256) throws -> Data {
        try rgba(size: size) { context, frame in
            let cell = 16
            for y in stride(from: 0, to: size, by: cell) {
                for x in stride(from: 0, to: size, by: cell) {
                    let light = (x / cell + y / cell).isMultiple(of: 2)
                    context.setFillColor(gray: light ? 0.93 : 0.8, alpha: 1)
                    context.fill(CGRect(x: x, y: y, width: cell, height: cell))
                }
            }
            tile(context, frame)
        }
    }
}

@Suite struct ImageProbeTests {
    private func probe(_ data: Data) throws -> ImageProbe {
        try withTempDir { dir in
            let url = dir.appending(path: "icon.png")
            try data.write(to: url)
            return try #require(ImageProbe.read(url))
        }
    }

    @Test func transparentCornersAreTransparent() throws {
        let p = try probe(DrawnPNG.transparent())
        #expect(p.header.colorType == 6)
        #expect(p.header.width == 1254 && p.header.height == 1254)
        #expect(p.cornerAlpha < 1)
        #expect(p.clearShare > 0.1)
        #expect(p.isTransparent)
        #expect(p.imageInfo == ImageInfo(width: 1254, height: 1254, alpha: true))
    }

    /// A tile that fills the whole frame, like a render whose tile covers about 97% of it: only
    /// the rounded corners are clear, about 3% of the pixels, under the old 5% floor.
    @Test func aFullBleedRoundedTileIsTransparent() throws {
        let p = try probe(DrawnPNG.rgba(size: 1254) { context, frame in
            let radius = frame.width * 0.21
            context.addPath(CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.setFillColor(CGColor(srgbRed: 0.45, green: 0.08, blue: 0.14, alpha: 1))
            context.fillPath()
        })
        #expect(p.header.colorType == 6)
        #expect(p.cornerAlpha < Double(ImageProbe.clearAlpha))
        #expect(p.clearShare > 0.02 && p.clearShare < 0.05)
        #expect(p.isTransparent)
    }

    /// The case a header check passes: RGBA, but every pixel opaque.
    @Test func aPaintedCheckerboardIsOpaque() throws {
        let p = try probe(DrawnPNG.checkerboard())
        #expect(p.header.hasAlpha, "the fixture must carry an alpha channel")
        #expect(p.cornerAlpha == 255)
        #expect(p.clearShare == 0)
        #expect(!p.isTransparent)
        #expect(p.imageInfo.alpha == false)
    }

    @Test func rgbIsOpaqueWithoutDecoding() throws {
        let p = try probe(TinyPNG.make(.rgb, width: 64, height: 64))
        #expect(p.header.colorType == 2)
        #expect(!p.isTransparent)
        #expect(p.cornerAlpha == 255 && p.clearShare == 0)
    }

    /// A 1 px clear border is not a transparent background: in the sample the corners are opaque.
    @Test func aOnePixelClearBorderIsOpaque() throws {
        let p = try probe(DrawnPNG.rgba(size: 1254) { context, frame in
            context.setFillColor(gray: 0.5, alpha: 1)
            context.fill(frame)
            for edge in [
                CGRect(x: 0, y: 0, width: 1254, height: 1), CGRect(x: 0, y: 1253, width: 1254, height: 1),
                CGRect(x: 0, y: 0, width: 1, height: 1254), CGRect(x: 1253, y: 0, width: 1, height: 1254),
            ] { context.clear(edge) }
        })
        #expect(p.header.hasAlpha)
        #expect(p.cornerAlpha >= Double(ImageProbe.clearAlpha))
        #expect(!p.isTransparent)
    }

    @Test func oneOpaqueCornerIsOpaque() throws {
        let p = try probe(DrawnPNG.rgba(size: 256) { context, frame in
            DrawnPNG.tile(context, frame)
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 236, y: 0, width: 20, height: 20))
        })
        #expect(p.clearShare > 0.05)
        #expect(!p.isTransparent)
    }

    @Test func notAPNGIsNil() throws {
        try withTempDir { dir in
            let text = dir.appending(path: "x.png")
            try Data("not a png".utf8).write(to: text)
            #expect(ImageProbe.read(text) == nil)
            #expect(ImageProbe.read(dir.appending(path: "missing.png")) == nil)
        }
    }
}

@Suite struct TransparencyFixTests {
    private struct Fixture {
        let dir: URL
        let opaque: URL
        let transparent: URL
        /// The request that made `opaque`: a refine with its parent as Image 1.
        let original: ImageRequest

        init(_ dir: URL) throws {
            self.dir = dir
            opaque = dir.appending(path: "opaque.png")
            transparent = dir.appending(path: "transparent.png")
            try DrawnPNG.checkerboard().write(to: opaque)
            try DrawnPNG.transparent(size: 256).write(to: transparent)
            original = ImageRequest(
                prompt: "Edit Image 1. Change only the date.", refs: [dir.appending(path: "parent.png")], count: 3,
                model: "gpt-6-luna", effort: "low", timeout: 300, outputDir: dir.appending(path: "render"))
        }

        func probe(_ url: URL) throws -> ImageProbe { try #require(ImageProbe.read(url)) }

        /// A new opaque file, as a failed attempt returns.
        func opaqueCopy(_ name: String) throws -> URL {
            let url = dir.appending(path: name)
            try DrawnPNG.checkerboard().write(to: url)
            return url
        }
    }

    private struct Boom: Error {}

    @Test func thePromptIsTheOneInTheSpec() {
        #expect(
            TransparencyFix.prompt
                == "Edit Image 1. Remove the backdrop, the checkerboard and any cast shadow so that everything outside the icon tile is fully transparent: a real alpha channel, no painted background of any kind. Keep the icon tile itself and everything on it identical: its shape, size, position, materials, colours, lighting, camera angle, framing and the image size. Output a PNG with transparency.")
        #expect(TransparencyFix.defaultAttempts == 3)
    }

    @Test func aTransparentRenderOrZeroAttemptsRendersNothing() throws {
        try withTempDir { dir in
            let f = try Fixture(dir)
            var calls = 0
            let render: (ImageRequest, Int) throws -> TransparencyFix.Render = { _, _ in
                calls += 1
                return .init(image: f.transparent, model: "m")
            }
            let clear = TransparencyFix.run(
                f.transparent, probe: try f.probe(f.transparent), original: f.original, attempts: 3, render: render)
            #expect(clear.image == f.transparent && !clear.isFixed && clear.attempts.isEmpty && clear.records.isEmpty)
            let off = TransparencyFix.run(
                f.opaque, probe: try f.probe(f.opaque), original: f.original, attempts: 0, render: render)
            #expect(off.image == f.opaque && !off.isFixed && !off.probe.isTransparent)
            #expect(calls == 0)
        }
    }

    /// Attempt 1 is the transparency edit of the opaque render, with the original's settings.
    @Test func stopsAtTheFirstTransparentFix() throws {
        try withTempDir { dir in
            let f = try Fixture(dir)
            var seen: [Int] = []
            let outcome = TransparencyFix.run(
                f.opaque, probe: try f.probe(f.opaque), original: f.original, attempts: 3,
                render: { request, attempt in
                    #expect(request.prompt == TransparencyFix.prompt)
                    #expect(request.refs == [f.opaque])
                    #expect(request.count == 1)
                    #expect(request.model == "gpt-6-luna" && request.effort == "low" && request.timeout == 300)
                    return .init(image: f.transparent, model: "gpt-6-luna")
                },
                onAttempt: { seen.append($0.number) })
            #expect(seen == [1])
            #expect(outcome.image == f.transparent)
            #expect(outcome.probe.isTransparent)
            #expect(outcome.fixModel == "gpt-6-luna")
            #expect(!outcome.rerolled)
            #expect(outcome.source == f.opaque)
            #expect(outcome.fixes == [TransparencyFix.prompt])
            #expect(outcome.records.map(\.kind) == [.transparencyEdit])
            #expect(outcome.records.map(\.transparent) == [true])
        }
    }

    /// Attempt 2 renders the original request again: its prompt and refs, one image.
    @Test func theSecondAttemptRerollsTheOriginalRequest() throws {
        try withTempDir { dir in
            let f = try Fixture(dir)
            var requests: [ImageRequest] = []
            let outcome = TransparencyFix.run(
                f.opaque, probe: try f.probe(f.opaque), original: f.original, attempts: 3
            ) { request, attempt in
                requests.append(request)
                let image = attempt == 2 ? f.transparent : try f.opaqueCopy("edit-\(attempt).png")
                return .init(image: image, model: "m\(attempt)")
            }
            #expect(requests.count == 2)
            #expect(requests[0].prompt == TransparencyFix.prompt && requests[0].refs == [f.opaque])
            #expect(requests[1].prompt == f.original.prompt && requests[1].refs == f.original.refs)
            #expect(requests[1].count == 1 && requests[1].outputDir == nil)
            #expect(outcome.image == f.transparent && outcome.fixModel == "m2")
            #expect(outcome.rerolled)
            #expect(outcome.source == nil)
            #expect(outcome.fixes.isEmpty)
            #expect(outcome.records.map(\.kind) == [.transparencyEdit, .reroll])
            #expect(outcome.records.map(\.transparent) == [false, true])
        }
    }

    /// Attempt 3 edits attempt 2's opaque render, not the original.
    @Test func theThirdAttemptEditsTheReroll() throws {
        try withTempDir { dir in
            let f = try Fixture(dir)
            let reroll = try f.opaqueCopy("reroll.png")
            var requests: [ImageRequest] = []
            let outcome = TransparencyFix.run(
                f.opaque, probe: try f.probe(f.opaque), original: f.original, attempts: 3
            ) { request, attempt in
                requests.append(request)
                switch attempt {
                case 1: return .init(image: try f.opaqueCopy("edit-1.png"), model: "m")
                case 2: return .init(image: reroll, model: "m")
                default: return .init(image: f.transparent, model: "m3")
                }
            }
            #expect(requests.map(\.prompt) == [TransparencyFix.prompt, f.original.prompt, TransparencyFix.prompt])
            #expect(requests.map(\.refs) == [[f.opaque], f.original.refs, [reroll]])
            #expect(outcome.image == f.transparent && outcome.fixModel == "m3")
            #expect(outcome.rerolled)
            #expect(outcome.source == reroll)
            #expect(outcome.fixes == [TransparencyFix.prompt])
            #expect(outcome.records.map(\.kind) == [.transparencyEdit, .reroll, .transparencyEdit])
            #expect(outcome.records.map(\.transparent) == [false, false, true])
        }
    }

    /// A failure counts as an attempt; a failed re-roll leaves attempt 3 to edit the original;
    /// after the last one the original is kept.
    @Test func givesUpAfterTheAttemptsAndKeepsTheOriginal() throws {
        try withTempDir { dir in
            let f = try Fixture(dir)
            var inputs: [[URL]] = []
            var seen: [FixAttempt.Kind] = []
            let outcome = TransparencyFix.run(
                f.opaque, probe: try f.probe(f.opaque), original: f.original, attempts: 3,
                render: { request, attempt in
                    inputs.append(request.refs)
                    if attempt == 2 { throw Boom() }
                    return .init(image: try f.opaqueCopy("fix-\(attempt).png"), model: "m")
                },
                onAttempt: { seen.append($0.kind) })
            #expect(inputs == [[f.opaque], f.original.refs, [f.opaque]])
            #expect(seen == [.transparencyEdit, .reroll, .transparencyEdit])
            #expect(outcome.image == f.opaque)
            #expect(!outcome.isFixed && !outcome.probe.isTransparent && !outcome.rerolled && outcome.fixes.isEmpty)
            #expect(outcome.source == nil)
            #expect(outcome.attempts.map(\.number) == [1, 2, 3])
            #expect(outcome.attempts[1].error != nil && outcome.attempts[1].probe == nil)
            #expect(outcome.attempts[0].probe?.isTransparent == false)
            #expect(outcome.records.map(\.transparent) == [false, false, false])
        }
    }

    /// Without the original request the re-roll is skipped, and attempt 3 edits the original.
    @Test func withoutTheOriginalTheRerollIsSkipped() throws {
        try withTempDir { dir in
            let f = try Fixture(dir)
            var calls: [(Int, ImageRequest)] = []
            let outcome = TransparencyFix.run(
                f.opaque, probe: try f.probe(f.opaque), original: nil, attempts: 3
            ) { request, attempt in
                calls.append((attempt, request))
                return .init(image: try f.opaqueCopy("fix-\(attempt).png"), model: "m")
            }
            #expect(calls.map(\.0) == [1, 3])
            #expect(calls.allSatisfy { $0.1.prompt == TransparencyFix.prompt && $0.1.refs == [f.opaque] })
            #expect(outcome.attempts.map(\.number) == [1, 3])
            #expect(outcome.records.map(\.kind) == [.transparencyEdit, .transparencyEdit])
            #expect(outcome.image == f.opaque && !outcome.isFixed)
        }
    }

    @Test func aRecordRoundsSecondsToATenth() {
        let attempt = TransparencyFix.Attempt(number: 2, kind: .reroll, seconds: 51.26, probe: nil, error: "boom")
        #expect(attempt.record == FixAttempt(kind: .reroll, transparent: false, seconds: 51.3))
    }
}
