import Foundation

/// Each layer's outline and fill in a render against the pick's, at full resolution. quiet-pick's grey tile came
/// out of the magenta key with a stepped, wavy outline and a light band just inside it; MATCH, at a quarter of the
/// tile, could not see it, and the agent saw it at zoom and still accepted it. Three measures, each in the render and
/// in the pick along the same outline, so a soft or textured pick sets its own bar:
///
/// - `outline`: how far the edge wobbles about its own smooth course, in tile pixels, from where it crosses halfway
///   between the levels either side of it, read along the outline's normal.
/// - `band`: how much lighter (+) or darker (−) the pixels 1 to 2.5 px inside the edge are than those 4 to 6 px in,
///   OKLab lightness times 100: a rim a few pixels wide, not the part's broad shading.
/// - `fill`: the grain of the layer's inside, its lightness against its own 5 px mean, times 100.
/// - `colour`: the median colour of the layer's solid inside, its lightness as OKLab L times 100 in each, and how far apart
///   the two are, OKLab ΔE times 100. quiet-pick's grey tile came back 5 L lighter than the pick, which no outline
///   measure sees.
///
/// A defect along the outline or in the grain is local, a corner or one side, so each is measured per block of 64 px,
/// and a layer reports the block where the render is furthest from the pick. The colour is the whole inside's.
public enum LayerEdge {
    /// How far each side of the outline the profile is read, tile px: the edge is found within 5 px of the outline,
    /// between the levels 5 to 6 px either side of it, and the band read up to 6 px inside it.
    static let reach = 10
    /// The least difference in lightness between the two sides for an edge to be found, OKLab L.
    static let leastStep: Float = 0.04
    /// The neighbourhood an outline point's course is taken over, tile px.
    static let course = 5
    /// The tile's rim, where the renderer shades the glass, tile px.
    static let rim = 12
    /// Blocks the warnings are placed by, tile px.
    static let block = 64

    // Calibrated on quiet-pick's two magenta drawings of its grey tile, its `key: clear` redraw and the trial's
    // eleven builds, per block of 64 px. The stepped tile's worst block wobbled 0.13 and 0.16 px against the pick's
    // 0.03 and 0.02; its clear redraw 0.04 against 0.01. The trial's builds differ from their picks by far more in
    // places, a knurl, a felt edge, a tick, but those are shapes the redraw changed, which MATCH covers, and their
    // picks' own outlines there are rarely plain.

    /// An outline is rougher where the pick's is plain (median wobble at most `plainOutline`), the render's
    /// wobbles at least `roughOutline` and three times the pick's, but under `shapeOutline`, past which it is a shape.
    public static let plainOutline = 0.05
    public static let roughOutline = 0.12
    public static let roughRatio = 3.0
    public static let shapeOutline = 0.5
    /// A band warns where the pick's outline has none (under `plainBand`) and the render's differs from it by this:
    /// a rim the eye takes for an edge, not a redraw's shading. The trial's redraws differ by up to 10 in places.
    public static let bandMargin = 12.0
    public static let plainBand = 2.0
    /// A fill is mottled at this many times the pick's grain and this much more. Only the trial's rough road came near.
    public static let fillRatio = 3.0
    public static let fillMargin = 2.0
    /// A colour is off the pick's at this OKLab ΔE times 100.
    public static let colourMargin = 3.0

    /// One image's measures of a layer at the block where the render is furthest from the pick; nil where the layer
    /// shows too little of it to measure.
    public struct Side: Sendable, Equatable {
        public var outline: Double?
        public var band: Double?
        public var fill: Double?
        /// The inside's median lightness, OKLab L times 100.
        public var lightness: Double?
    }

    public struct Measure: Sendable {
        public var name: String
        public var render: Side
        public var pick: Side
        /// Where each defect is, in tile pixels; nil when there is none.
        public var rough: LayerBox?
        public var banded: LayerBox?
        public var mottled: LayerBox?
        /// How far the inside's colour is from the pick's, OKLab ΔE times 100.
        public var colourShift: Double?

        public var offColour: Bool { (colourShift ?? 0) >= colourMargin }
        public var warns: Bool { rough != nil || banded != nil || mottled != nil || offColour }
    }

    static func rougher(_ render: Double, _ pick: Double) -> Bool {
        pick <= plainOutline && render >= roughOutline && render >= pick * roughRatio && render < shapeOutline
    }

    static func bandDiffers(_ render: Double, _ pick: Double) -> Bool { abs(render - pick) >= bandMargin }

    static func mottled(_ render: Double, _ pick: Double) -> Bool {
        render >= pick + fillMargin && render >= pick * fillRatio
    }

    /// Each layer, given bottom to top at the tile's size, measured in `render` and in `pick` where no layer above
    /// covers it.
    public static func measure(pick: LayerImage, render: LayerImage, layers: [(name: String, image: LayerImage)]) -> [Measure] {
        guard let n = layers.first?.image.width else { return [] }
        let p = pick.width == n ? pick : pick.resized(to: n)
        let r = render.width == n ? render : render.resized(to: n)
        let lp = p.lightness(), lr = r.lightness()
        // inside both tiles and clear of the rim, so every read along a normal lands on the picture
        let opaque = (0..<(n * n)).map { p.pixels[$0 * 4 + 3] > 0.99 && r.pixels[$0 * 4 + 3] > 0.99 }
        let tile = LayerImage.dilated(opaque.map { !$0 }, width: n, height: n, radius: rim).map { !$0 }
        var above = [Bool](repeating: false, count: n * n)
        var result: [Measure] = []
        for layer in layers.reversed() {
            let alpha = (0..<(n * n)).map { layer.image.pixels[$0 * 4 + 3] }
            let mask = alpha.map { $0 > 0.5 }
            let covered = LayerImage.dilated(above, width: n, height: n, radius: reach)
            let points = outline(mask, alpha: alpha, side: n) { tile[$0] && !covered[$0] }
            let near = LayerImage.dilated(mask.map { !$0 }, width: n, height: n, radius: 6)
            let inside = (0..<(n * n)).filter { mask[$0] && !near[$0] && !covered[$0] && tile[$0] }
            let a = read(lr, points, inside, n), b = read(lp, points, inside, n)
            let blocks = blockMeasures(a, b)
            let outline = worst(blocks.outline, by: { $0 - $1 }, flags: rougher, side: n)
            // a band the pick has too is the picture's, so only blocks where the pick's outline is plain count
            let band = worst(blocks.band.filter { abs($0.value.1) < plainBand }, by: { abs($0 - $1) }, flags: bandDiffers, side: n)
            let fill = worst(blocks.fill, by: { $0 - $1 }, flags: mottled, side: n)
            // only where the layer is solid, as `match` measures it: a glow's colour in the render is mostly what is behind
            let solid = inside.filter { alpha[$0] > 0.99 }
            let colours = (LayerImage.medianColour(r, at: solid), LayerImage.medianColour(p, at: solid))
            var shift: Double?
            if let u = colours.0, let v = colours.1 { shift = Double(((u - v) * (u - v)).sum().squareRoot()) * 100 }
            result.append(Measure(
                name: layer.name,
                render: Side(outline: outline.values?.0, band: band.values?.0, fill: fill.values?.0,
                    lightness: colours.0.map { Double($0.x) * 100 }),
                pick: Side(outline: outline.values?.1, band: band.values?.1, fill: fill.values?.1,
                    lightness: colours.1.map { Double($0.x) * 100 }),
                rough: outline.box, banded: band.box, mottled: fill.box, colourShift: shift))
            for i in 0..<(n * n) where mask[i] { above[i] = true }
        }
        return result.reversed()
    }

    // MARK: The outline

    /// A point on a layer's outline: a pixel of its mask beside one outside it, and the outward normal there.
    struct Point {
        var x: Int
        var y: Int
        var nx: Float
        var ny: Float
    }

    /// The outline of `mask` where `keep` holds and the layer is solid 3 px inside it, its normals from the alpha
    /// smoothed over 5 px.
    static func outline(_ mask: [Bool], alpha: [Float], side n: Int, keep: (Int) -> Bool) -> [Point] {
        let smooth = LayerImage.boxSums(alpha, channels: 1, width: n, height: n, radius: 2)
        var points: [Point] = []
        for y in 1..<(n - 1) {
            for x in 1..<(n - 1) {
                let i = y * n + x
                guard mask[i], !mask[i - 1] || !mask[i + 1] || !mask[i - n] || !mask[i + n], keep(i) else { continue }
                let gx = smooth[i + 1] - smooth[i - 1], gy = smooth[i + n] - smooth[i - n]
                let length = (gx * gx + gy * gy).squareRoot()
                guard length > 1e-3 else { continue }
                let nx = -gx / length, ny = -gy / length
                // a glow or a translucent edge has no outline to be rough or banded: only a part solid 3 px in counts
                let solid = alpha.withUnsafeBufferPointer { bilinear($0, n, Float(x) - 3 * nx, Float(y) - 3 * ny) }
                guard solid >= 0.9 else { continue }
                points.append(Point(x: x, y: y, nx: nx, ny: ny))
            }
        }
        return points
    }

    /// One image's reads of a layer: per outline point, the edge's offset along the normal and the band; the fill.
    struct Reads {
        var points: [Point]
        /// The edge's offset from the point along its normal, nil where no edge is found.
        var offset: [Float?]
        var band: [Float?]
        /// The inside's pixels and each one's grain.
        var inside: [Int]
        var grain: [Float]
        /// Each point's edge against its neighbours' course, nil where it has no edge or too few neighbours.
        var wobble: [Float?] = []
        let width: Int
    }

    static func read(_ light: [Float], _ points: [Point], _ inside: [Int], _ n: Int) -> Reads {
        let steps = 4 * reach + 1  // every half pixel from -reach to +reach
        var offset = [Float?](repeating: nil, count: points.count)
        var band = [Float?](repeating: nil, count: points.count)
        var profile = [Float](repeating: 0, count: steps)
        light.withUnsafeBufferPointer { l in
            for (k, pt) in points.enumerated() {
                for s in 0..<steps {
                    let d = Float(s - 2 * reach) / 2
                    profile[s] = bilinear(l, n, Float(pt.x) + d * pt.nx, Float(pt.y) + d * pt.ny)
                }
                func at(_ d: Float) -> Float {
                    let f = min(max((d + Float(reach)) * 2, 0), Float(steps - 1))
                    let i = min(Int(f), steps - 2), t = f - Float(i)
                    return profile[i] * (1 - t) + profile[i + 1] * t
                }
                let inner = [-6, -5.5, -5].map { at(Float($0)) }.reduce(0, +) / 3
                let outer = [5, 5.5, 6].map { at(Float($0)) }.reduce(0, +) / 3
                guard abs(inner - outer) >= leastStep else { continue }
                let mid = (inner + outer) / 2
                // the crossing nearest the point, within 5 px of it. Placing the edge by the area under the profile
                // instead was steadier on texture but no longer told quiet-pick's stepped tile from its clean one
                var best: Float?
                for s in (2 * reach - 10)..<(2 * reach + 10) {
                    let u = profile[s] - mid, v = profile[s + 1] - mid
                    guard (u <= 0) != (v <= 0) else { continue }
                    let t = (Float(s - 2 * reach) + u / (u - v)) / 2
                    if best == nil || abs(t) < abs(best!) { best = t }
                }
                guard let t = best else { continue }
                offset[k] = t
                let nearIn = [1, 1.5, 2, 2.5].map { at(t - Float($0)) }.reduce(0, +) / 4
                let further = [4, 5, 6].map { at(t - Float($0)) }.reduce(0, +) / 3
                band[k] = (nearIn - further) * 100
            }
        }
        // the grain: lightness against its 5 px mean
        let mean = LayerImage.boxSums(light, channels: 1, width: n, height: n, radius: 2)
        let count = LayerImage.boxSums([Float](repeating: 1, count: n * n), channels: 1, width: n, height: n, radius: 2)
        let grain = inside.map { (light[$0] - mean[$0] / count[$0]) * 100 }

        var reads = Reads(points: points, offset: offset, band: band, inside: inside, grain: grain, width: n)
        reads.wobble = wobbles(reads)
        return reads
    }

    /// Each point's edge against its neighbours' course: the edge point's distance along the normal from the mean of
    /// the edge points within `course`, less the same for its neighbours, so a smooth curve reads about 0 and a step
    /// or a scallop does not.
    static func wobbles(_ reads: Reads) -> [Float?] {
        let n = reads.width
        // the edge points, then their distance from their neighbours' mean, each summed over the neighbourhood
        var plane = [Float](repeating: 0, count: n * n * 3)
        for (k, pt) in reads.points.enumerated() {
            guard let t = reads.offset[k] else { continue }
            let i = (pt.y * n + pt.x) * 3
            plane[i] = Float(pt.x) + t * pt.nx
            plane[i + 1] = Float(pt.y) + t * pt.ny
            plane[i + 2] = 1
        }
        let sums = LayerImage.boxSums(plane, channels: 3, width: n, height: n, radius: course)
        var first = [Float?](repeating: nil, count: reads.points.count)
        var second = [Float](repeating: 0, count: n * n * 2)
        for (k, pt) in reads.points.enumerated() {
            guard let t = reads.offset[k] else { continue }
            let i = pt.y * n + pt.x
            let count = sums[i * 3 + 2]
            guard count >= 5 else { continue }
            let mx = sums[i * 3] / count, my = sums[i * 3 + 1] / count
            let d = (Float(pt.x) + t * pt.nx - mx) * pt.nx + (Float(pt.y) + t * pt.ny - my) * pt.ny
            first[k] = d
            second[i * 2] = d
            second[i * 2 + 1] = 1
        }
        let local = LayerImage.boxSums(second, channels: 2, width: n, height: n, radius: course)
        return reads.points.indices.map { k in
            guard let d = first[k] else { return nil }
            let i = reads.points[k].y * n + reads.points[k].x
            return d - local[i * 2] / local[i * 2 + 1]
        }
    }

    /// The block where `by` is largest, the render's and the pick's values there, and the box around every block
    /// `flags` holds for. Ties go to the larger render value, then the earlier block, so a run reports the same block
    /// whatever order the dictionary keeps.
    static func worst(
        _ blocks: [Int: (Double, Double)], by excess: (Double, Double) -> Double, flags: (Double, Double) -> Bool, side n: Int
    ) -> (values: (Double, Double)?, box: LayerBox?) {
        let top = blocks.max { a, b in
            let ea = excess(a.value.0, a.value.1), eb = excess(b.value.0, b.value.1)
            if ea != eb { return ea < eb }
            if a.value.0 != b.value.0 { return a.value.0 < b.value.0 }
            return a.key > b.key
        }
        return (top?.value, union(blocks.filter { flags($0.value.0, $0.value.1) }.keys, side: n))
    }

    // MARK: Where

    /// Per block: the render's and the pick's outline, band and fill, for blocks with enough of each. Medians, so a
    /// few points where the redraw's shape differs (a tick, a seam, a junction) do not count, while a stepped or
    /// banded outline, which runs all along, does: the median wobble's size, the median band, the median grain's size.
    static func blockMeasures(_ a: Reads, _ b: Reads) -> (outline: [Int: (Double, Double)], band: [Int: (Double, Double)], fill: [Int: (Double, Double)]) {
        let n = a.width, per = (n + block - 1) / block
        func gather(_ values: [Float?], at points: [(x: Int, y: Int)], size: Bool) -> [Int: [Float]] {
            var out: [Int: [Float]] = [:]
            for (k, v) in values.enumerated() {
                guard let v else { continue }
                out[(points[k].y / block) * per + points[k].x / block, default: []].append(size ? abs(v) : v)
            }
            return out
        }
        func median(_ v: [Float]) -> Double { Double(v.sorted()[v.count / 2]) }
        func pair(_ x: [Int: [Float]], _ y: [Int: [Float]], least: Int) -> [Int: (Double, Double)] {
            var out: [Int: (Double, Double)] = [:]
            for (b, u) in x where u.count >= least {
                guard let v = y[b], v.count >= least else { continue }
                out[b] = (median(u), median(v))
            }
            return out
        }
        let outline = a.points.map { (x: $0.x, y: $0.y) }
        let inside = a.inside.map { (x: $0 % n, y: $0 / n) }
        return (
            pair(gather(a.wobble, at: outline, size: true), gather(b.wobble, at: outline, size: true), least: 12),
            pair(gather(a.band, at: outline, size: false), gather(b.band, at: outline, size: false), least: 12),
            pair(gather(a.grain.map { $0 }, at: inside, size: true), gather(b.grain.map { $0 }, at: inside, size: true), least: 100))
    }

    /// The box around the given blocks, in tile pixels.
    static func union(_ blocks: some Collection<Int>, side n: Int) -> LayerBox? {
        let per = (n + block - 1) / block
        var box: LayerBox?
        for b in blocks {
            let x = (b % per) * block, y = (b / per) * block
            let next = LayerBox(x0: x, y0: y, x1: min(x + block, n), y1: min(y + block, n))
            box = box.map { LayerBox(x0: min($0.x0, next.x0), y0: min($0.y0, next.y0), x1: max($0.x1, next.x1), y1: max($0.y1, next.y1)) }
                ?? next
        }
        return box
    }

    @inline(__always)
    static func bilinear(_ l: UnsafeBufferPointer<Float>, _ n: Int, _ x: Float, _ y: Float) -> Float {
        let x = min(max(x, 0), Float(n - 1)), y = min(max(y, 0), Float(n - 1))
        let x0 = min(Int(x), n - 2), y0 = min(Int(y), n - 2)
        let fx = x - Float(x0), fy = y - Float(y0)
        let i = y0 * n + x0
        return (l[i] * (1 - fx) + l[i + 1] * fx) * (1 - fy) + (l[i + n] * (1 - fx) + l[i + n + 1] * fx) * fy
    }
}

extension LayerImage {
    /// Each pixel's lightness, OKLab L through Ottosson's toe (close to CIELAB's L* / 100), alpha ignored.
    func lightness() -> [Float] {
        (0..<(width * height)).map { Self.toe(Self.oklab(SIMD3(pixels[$0 * 4], pixels[$0 * 4 + 1], pixels[$0 * 4 + 2])).x) }
    }
}
