import CoreGraphics
import Foundation

/// The build's own review, measured rather than judged by eye. The first build of the user's eclipse turned its
/// tapering crescent into an even band, and its black tile vanished on a near-black Dark, and the agent's review
/// called both fine. `LayerCompare` measures how far the Default render moved from the pick, `LayerContrast` how
/// far each layer stands off what is behind it in each appearance.
public enum LayerCompare {
    /// The side both images are compared at, a quarter of the tile: the resample averages away antialiasing and a
    /// texture's grain, while a part that moved is still a few pixels wide.
    static let side = 256
    /// How far, in compare pixels (8 tile px), a pixel may look for its match: a redraw's outlines wander that much.
    static let reach = 2
    /// The tile's rim, where the renderer lights the edge of the glass, in compare pixels.
    static let rim = 6
    /// The OKLab distance past which a pixel has no match within `reach`: a redraw's drift in shade stays under it.
    public static let threshold: Float = 0.12
    /// The distance of one part's colour standing where another's was, such as black where the pick is white or
    /// grey: a part moved or changed shape, not its shading.
    public static let strong: Float = 0.25
    /// The fewest strong compare pixels (16 tile px each) that make a region. Nine of the trial's eleven good builds
    /// have no patch past it (the keycap's lost cast shadow and the caliper's redrawn knurl do); the eclipse's black
    /// tile, drawn wider on its right, has 64.
    public static let minRegion = 40

    public struct Region: Sendable, Equatable {
        /// In tile pixels, end exclusive, ready for `--stage zoom --box`.
        public var box: LayerBox
        /// Strongly differing tile pixels.
        public var area: Int
    }

    public struct Result: Sendable {
        /// The share of the tile whose colour has a match within `reach` in the other image, 0...1.
        public var score: Double
        /// The regions where a part moved or changed shape, the largest first, at most three.
        public var regions: [Region]
    }

    /// The pick against a render of the package. A pixel differs when nothing within `reach` of it in the other
    /// image comes within `threshold` of its colour, either way round, so an outline a few pixels off does not count
    /// and a part that moved shows on both of its sides. A region is a patch of differing pixels with at least
    /// `minRegion` past `strong`: where a soft shadow or a glow redrawn wider only drifts in shade, a moved part puts
    /// one colour where another was.
    public static func compare(pick: LayerImage, render: LayerImage) -> Result {
        let n = side
        let a = pick.resized(to: n), b = render.resized(width: pick.width, height: pick.height).resized(to: n)
        var inside = [Bool](repeating: false, count: n * n)
        for i in 0..<(n * n) { inside[i] = a.pixels[i * 4 + 3] > 0.99 && b.pixels[i * 4 + 3] > 0.99 }
        // the image's own border counts as outside: the tile's flat sides run to it
        for i in 0..<n { inside[i] = false; inside[(n - 1) * n + i] = false; inside[i * n] = false; inside[i * n + n - 1] = false }
        inside = LayerImage.dilated(inside.map { !$0 }, width: n, height: n, radius: rim).map { !$0 }
        let labA = a.oklabPlane(), labB = b.oklabPlane()

        func nearest(_ c: SIMD3<Float>, in lab: [SIMD3<Float>], x: Int, y: Int) -> Float {
            var best = Float.infinity
            for v in max(0, y - reach)...min(n - 1, y + reach) {
                for u in max(0, x - reach)...min(n - 1, x + reach) {
                    let d = c - lab[v * n + u]
                    best = min(best, (d * d).sum())
                }
            }
            return best.squareRoot()
        }
        var distance = [Float](repeating: 0, count: n * n)
        var differs = [Bool](repeating: false, count: n * n)
        for y in 0..<n {
            for x in 0..<n where inside[y * n + x] {
                let i = y * n + x
                distance[i] = max(nearest(labA[i], in: labB, x: x, y: y), nearest(labB[i], in: labA, x: x, y: y))
                differs[i] = distance[i] > threshold
            }
        }

        // regions: differing pixels joined across small gaps, so both sides of a moved part are one region
        let joined = LayerImage.dilated(differs, width: n, height: n, radius: 2)
        var seen = [Bool](repeating: false, count: n * n)
        var found: [(box: LayerBox, strong: Int)] = []
        for start in 0..<(n * n) where joined[start] && !seen[start] {
            var stack = [start], strongCount = 0
            var x0 = n, y0 = n, x1 = 0, y1 = 0
            seen[start] = true
            while let i = stack.popLast() {
                let x = i % n, y = i / n
                if differs[i] {
                    x0 = min(x0, x); x1 = max(x1, x + 1); y0 = min(y0, y); y1 = max(y1, y + 1)
                    if distance[i] > strong { strongCount += 1 }
                }
                for (u, v) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] where u >= 0 && u < n && v >= 0 && v < n {
                    let j = v * n + u
                    if joined[j] && !seen[j] {
                        seen[j] = true
                        stack.append(j)
                    }
                }
            }
            if strongCount >= minRegion { found.append((LayerBox(x0: x0, y0: y0, x1: x1, y1: y1), strongCount)) }
        }
        let k = pick.width / n
        let regions = found.sorted { $0.strong > $1.strong }.prefix(3).map { r in
            // a margin of one reach, so a zoom shows both outlines
            let pad = reach * k
            return Region(
                box: LayerBox(
                    x0: max(0, r.box.x0 * k - pad), y0: max(0, r.box.y0 * k - pad),
                    x1: min(pick.width, r.box.x1 * k + pad), y1: min(pick.height, r.box.y1 * k + pad)),
                area: r.strong * k * k)
        }
        let tile = max(inside.filter { $0 }.count, 1)
        return Result(score: 1 - Double(differs.filter { $0 }.count) / Double(tile), regions: Array(regions))
    }

    /// The comparison at `panel` px, an anaglyph: the pick's lightness in red, the render's in green and blue, their
    /// difference doubled. Where they agree it is grey; where the pick is lighter it is red, where the render is
    /// lighter cyan, so a part that moved shows as a red sliver on one side and a cyan one on the other. Each region
    /// is boxed in yellow.
    public static func overlay(pick: LayerImage, render: LayerImage, result: Result, panel: Int = 600) throws -> LayerImage {
        let a = pick.resized(to: panel), b = render.resized(width: pick.width, height: pick.height).resized(to: panel)
        var out = LayerImage(side: panel)
        for i in 0..<(panel * panel) {
            func light(_ image: LayerImage) -> Float {
                let p = image.pixels, j = i * 4
                // over the sheet's mid grey, so the corners outside the tile stay grey
                return LayerImage.toe(LayerImage.oklab(SIMD3(p[j], p[j + 1], p[j + 2])).x) * p[j + 3] + 0.5 * (1 - p[j + 3])
            }
            // the difference doubled about the mean, so a sliver a few pixels wide still shows
            let r = light(a), c = light(b), m = (r + c) / 2
            out.pixels[i * 4] = min(max(m + (r - c), 0), 1)
            out.pixels[i * 4 + 1] = min(max(m - (r - c), 0), 1)
            out.pixels[i * 4 + 2] = out.pixels[i * 4 + 1]
            out.pixels[i * 4 + 3] = 1
        }
        let canvas = try Canvas(width: panel, height: panel, grey: 128)
        try canvas.draw(out, in: CGRect(x: 0, y: 0, width: panel, height: panel))
        let yellow = CGColor(srgbRed: 1, green: 0.85, blue: 0, alpha: 1)
        let k = Double(panel) / Double(pick.width)
        for (number, region) in result.regions.enumerated() {
            let r = CGRect(
                x: Double(region.box.x0) * k, y: Double(region.box.y0) * k,
                width: Double(region.box.width) * k, height: Double(region.box.height) * k)
            for side in [CGRect(x: r.minX, y: r.minY, width: r.width, height: 2), CGRect(x: r.minX, y: r.maxY - 2, width: r.width, height: 2),
                         CGRect(x: r.minX, y: r.minY, width: 2, height: r.height), CGRect(x: r.maxX - 2, y: r.minY, width: 2, height: r.height)] {
                canvas.fill(side, yellow)
            }
            canvas.label("\(number + 1)", x: r.minX + 2, y: r.minY + 2, colour: yellow)
        }
        return try canvas.image()
    }

    /// `compare.png`: the pick, the render and the overlay side by side, labelled.
    public static func picture(pick: LayerImage, render: LayerImage, renderLabel: String, result: Result) throws -> LayerImage {
        let panel = 600, gap = 8
        let canvas = try Canvas(width: panel * 3 + gap * 2, height: panel, grey: 128)
        try canvas.draw(pick, in: CGRect(x: 0, y: 0, width: panel, height: panel))
        canvas.label("pick", x: 0, y: 0)
        try canvas.draw(render, in: CGRect(x: panel + gap, y: 0, width: panel, height: panel))
        canvas.label(renderLabel, x: Double(panel + gap), y: 0)
        let x = Double(2 * (panel + gap))
        try canvas.draw(try overlay(pick: pick, render: render, result: result, panel: panel), in: CGRect(x: x, y: 0, width: Double(panel), height: Double(panel)))
        canvas.label("red: pick lighter, cyan: \(renderLabel) lighter", x: x, y: 0)
        return try canvas.image()
    }
}

/// How far each layer stands off what is behind it in a render: the ground, or the layers below it. Measured
/// along its outline, where the eye tells a part from its surroundings: just inside the layer's mask (where no
/// layer above covers it) against just outside it (where none above covers that either).
public enum LayerContrast {
    /// An OKLab distance (times 100) under which a part's outline stops reading against what is behind it. The
    /// eclipse's black tile on its near-black Dark measured 7; the trial's good builds keep most outlines above 10.
    public static let threshold: Double = 8
    /// The share of a layer's outline under `threshold` that makes the layer fade. A part may meet a colour like its
    /// own along some of its outline, as the trial's slim lamp pole does against the hills along 39% of it.
    public static let fadeShare = 0.45
    /// The outline is compared in blocks this many tile pixels square, so a part shaded light on one side and dark
    /// on the other is judged side by side, not by its average.
    static let block = 32
    /// Pixels 2 to 6 from the outline: past the antialiased edge, near enough to be what the eye compares.
    static let band = (from: 2, to: 6)

    /// One layer's outline, found once and measured in every render.
    public struct Outline: Sendable {
        public var name: String
        var inner: [Int]
        var outer: [Int]
        let width: Int
    }

    public struct Measure: Sendable, Equatable {
        public var name: String
        /// The median contrast along the outline, OKLab distance times 100; nil when the layer is hidden.
        public var contrast: Double?
        /// The share of the outline under `threshold`.
        public var weak: Double
        /// Where the weak part of the outline is, in tile pixels.
        public var weakBox: LayerBox?

        public var fades: Bool { contrast != nil && weak >= LayerContrast.fadeShare }
    }

    /// The outlines of layers given bottom to top by their masks (alpha over 0.5), `width` square.
    public static func outlines(_ layers: [(name: String, mask: [Bool])], width: Int) -> [Outline] {
        let count = width * width
        var above = [Bool](repeating: false, count: count)
        var result: [Outline] = []
        for layer in layers.reversed() {
            let m = layer.mask
            let outside = m.map { !$0 }
            let nearOut = LayerImage.dilated(outside, width: width, height: width, radius: band.to)
            let edgeOut = LayerImage.dilated(outside, width: width, height: width, radius: band.from - 1)
            let nearIn = LayerImage.dilated(m, width: width, height: width, radius: band.to)
            let edgeIn = LayerImage.dilated(m, width: width, height: width, radius: band.from - 1)
            var inner: [Int] = [], outer: [Int] = []
            for i in 0..<count where !above[i] {
                if m[i] {
                    if nearOut[i] && !edgeOut[i] { inner.append(i) }
                } else if nearIn[i] && !edgeIn[i] {
                    outer.append(i)
                }
            }
            result.append(Outline(name: layer.name, inner: inner, outer: outer, width: width))
            for i in 0..<count where m[i] { above[i] = true }
        }
        return result.reversed()
    }

    /// Each outline's contrast in `render`, the same size as the masks. Pixels outside the render's tile do not
    /// count.
    public static func measure(_ render: LayerImage, _ outlines: [Outline]) -> [Measure] {
        guard let width = outlines.first?.width else { return [] }
        let image = render.width == width && render.height == width ? render : render.resized(to: width)
        let blocks = (width + block - 1) / block
        return outlines.map { outline in
            var sumIn = [SIMD3<Float>](repeating: .zero, count: blocks * blocks), nIn = [Int](repeating: 0, count: blocks * blocks)
            var sumOut = sumIn, nOut = nIn
            func add(_ i: Int, _ sum: inout [SIMD3<Float>], _ n: inout [Int]) {
                guard image.pixels[i * 4 + 3] > 0.5 else { return }
                let b = (i / width / block) * blocks + (i % width) / block
                sum[b] += LayerImage.oklab(SIMD3(image.pixels[i * 4], image.pixels[i * 4 + 1], image.pixels[i * 4 + 2]))
                n[b] += 1
            }
            for i in outline.inner { add(i, &sumIn, &nIn) }
            for i in outline.outer { add(i, &sumOut, &nOut) }
            var measured: [(contrast: Double, weight: Int, block: Int)] = []
            for b in 0..<(blocks * blocks) where nIn[b] >= 8 && nOut[b] >= 8 {
                let d = sumIn[b] / Float(nIn[b]) - sumOut[b] / Float(nOut[b])
                measured.append((Double((d * d).sum().squareRoot()) * 100, min(nIn[b], nOut[b]), b))
            }
            guard !measured.isEmpty else { return Measure(name: outline.name, contrast: nil, weak: 0, weakBox: nil) }
            measured.sort { $0.contrast < $1.contrast }
            let total = measured.reduce(0) { $0 + $1.weight }
            var running = 0
            let median = measured.first { running += $0.weight; return running * 2 >= total }!.contrast
            let weakBlocks = measured.filter { $0.contrast < threshold }
            var box: LayerBox?
            for w in weakBlocks {
                let x = (w.block % blocks) * block, y = (w.block / blocks) * block
                let b = LayerBox(x0: x, y0: y, x1: min(x + block, width), y1: min(y + block, width))
                box = box.map { LayerBox(x0: min($0.x0, b.x0), y0: min($0.y0, b.y0), x1: max($0.x1, b.x1), y1: max($0.y1, b.y1)) } ?? b
            }
            let weak = Double(weakBlocks.reduce(0) { $0 + $1.weight }) / Double(total)
            return Measure(name: outline.name, contrast: median, weak: weak, weakBox: box)
        }
    }
}

extension LayerImage {
    /// `mask` grown by `radius` pixels in every direction (a square), in two passes.
    static func dilated(_ mask: [Bool], width: Int, height: Int, radius: Int) -> [Bool] {
        guard radius > 0 else { return mask }
        var rows = [Bool](repeating: false, count: mask.count)
        for y in 0..<height {
            var last = -radius - 1
            // forward then backward, so each pixel knows the nearest set one on its row
            for x in 0..<width {
                if mask[y * width + x] { last = x }
                if x - last <= radius { rows[y * width + x] = true }
            }
            last = width + radius + 1
            for x in stride(from: width - 1, through: 0, by: -1) {
                if mask[y * width + x] { last = x }
                if last - x <= radius { rows[y * width + x] = true }
            }
        }
        var out = [Bool](repeating: false, count: mask.count)
        for x in 0..<width {
            var last = -radius - 1
            for y in 0..<height {
                if rows[y * width + x] { last = y }
                if y - last <= radius { out[y * width + x] = true }
            }
            last = height + radius + 1
            for y in stride(from: height - 1, through: 0, by: -1) {
                if rows[y * width + x] { last = y }
                if last - y <= radius { out[y * width + x] = true }
            }
        }
        return out
    }

    /// Each pixel's OKLab colour, alpha ignored.
    func oklabPlane() -> [SIMD3<Float>] {
        (0..<(width * height)).map { Self.oklab(SIMD3(pixels[$0 * 4], pixels[$0 * 4 + 1], pixels[$0 * 4 + 2])) }
    }

    /// Whether each pixel's alpha is over one half: a layer's mask.
    public var mask: [Bool] { (0..<(width * height)).map { pixels[$0 * 4 + 3] > 0.5 } }
}
