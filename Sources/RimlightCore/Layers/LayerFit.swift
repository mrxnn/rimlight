import Accelerate
import Dispatch
import Foundation

/// Lays a layer the image model drew back onto the picked tile.
///
/// The model edits the whole frame, but Codex does not always keep a part's size and place, so each
/// layer is fitted: a scale about the tile's centre plus a shift, p → s·(p − c) + c + t. The
/// score is the whole picture's error, the layer laid over what lies under it (the ground and
/// the layers already placed) against the concept. A mean over the layer alone let a shrunken
/// keycap sit inside the real one's blue; the whole picture's error pays for the blue it
/// leaves uncovered. Only the layer's footprint changes the sum, so only it is summed, less
/// what lies under it scored alone.
///
/// The search runs coarse at a quarter of the tile, then twice finer at half, as the Python
/// prototype (`layer-trial/lt.py`) did. Per scale the layer is warped once; each integer
/// shift is then a dot product of the layer's per-pixel terms with the ground's, row run by
/// row run, so a shift costs no warp.
public enum LayerFit {
    /// How the layer was drawn, which sets where the search starts.
    public enum Mode: Hashable, Sendable {
        /// On a magenta or black key: Codex edited the whole frame and kept the layer's place
        /// (five layers came back at 0.994 to 1.003, unshifted), so the search stays near
        /// identity, scale 0.97 to 1.03 and 8 px either way at a quarter size.
        case keyed
        /// On real transparency: Codex centres and enlarges a lone part, so the plan's box (tile
        /// px) seeds the scale and shift by fitting the layer's solid bounds into it, then the
        /// search looks 6% and 12 px (at a quarter size) around that.
        case boxed(LayerBox)
    }

    /// Where a layer landed: its scale about the tile's centre, its shift in tile pixels, and
    /// for a soft layer the opacity that fits best (1 otherwise).
    public struct Fit: Hashable, Sendable, Codable {
        public var scale: Double
        public var dx: Double
        public var dy: Double
        public var opacity: Double

        public init(scale: Double, dx: Double, dy: Double, opacity: Double = 1) {
            self.scale = scale
            self.dx = dx
            self.dy = dy
            self.opacity = opacity
        }

        public static let identity = Fit(scale: 1, dx: 0, dy: 0)
    }

    /// A placed layer at the tile's size, clear outside what was drawn, and its fit.
    public struct Placement: Sendable {
        public var layer: LayerImage
        public var fit: Fit
    }

    /// The opacities a soft layer (a glow, drawn at the image model's own strength) is tried at.
    static let opacities = (0...16).map { 0.2 + 0.05 * Double($0) }

    /// Fits `layer` onto `concept` over `under` and returns it placed.
    ///
    /// - `concept`: the picked tile, square, side divisible by 4 (1024); its alpha is ignored.
    /// - `layer`: the drawing, already unkeyed; resized to the concept's side if it is not.
    /// - `under`: what lies under the layer, same side as the concept, taken as opaque.
    /// - `soft`: also fit the layer's opacity, 0.2 to 1 by 0.05, and scale its alpha by it.
    ///   Each place the search tries is scored at its own best opacity: a glow drawn at full
    ///   strength fitted at full strength first came back shrunk, a smaller glow being the
    ///   closest a full-strength one gets to a faint one.
    public static func fit(
        _ layer: LayerImage, concept: LayerImage, under: LayerImage, mode: Mode, soft: Bool = false
    ) throws -> Placement {
        let n = concept.width
        guard concept.isSquare, n % 4 == 0, n >= 64 else {
            throw LayerImage.Failure(description: "the concept is \(concept.width)x\(concept.height), not a square tile")
        }
        guard under.width == n, under.height == n else {
            throw LayerImage.Failure(description: "what lies under the layer is \(under.width)x\(under.height), not \(n) px")
        }
        let drawn = layer.width == n && layer.height == n ? layer : layer.resized(to: n)
        guard let solid = drawn.alphaBounds(above: 0.5) else {
            throw LayerImage.Failure(description: "the layer has no solid pixel to fit")
        }
        let L = drawn.premultiplied()
        let B = under.premultiplied()
        let C = concept.pixels  // straight colour, alpha ignored: the tile's clear corners keep what they store

        let quarter = n / 4, half = n / 2
        var s0 = 1.0
        var g = (x: 0.0, y: 0.0)
        var passes: [(size: Int, scales: [Double]?, radius: Int)] = [(half, nil, 8), (half, nil, 2)]
        switch mode {
        case .keyed:
            passes.insert((quarter, steps(around: 1, by: 0.01, count: 3), 8), at: 0)
        case .boxed(let box):
            let seed = boxed(solid, into: box, side: n)
            s0 = seed.scale
            g = (seed.dx / 4, seed.dy / 4)
            passes.insert((quarter, steps(around: seed.scale, by: 0.01, count: 6).filter { $0 > 0.01 }, 12), at: 0)
        }

        var levels: [Int: (C: [Float], B: [Float], L: [Float])] = [:]
        var previous = quarter
        for pass in passes {
            let size = pass.size
            g = (g.x * Double(size) / Double(previous), g.y * Double(size) / Double(previous))
            previous = size
            if levels[size] == nil {
                let f = n / size
                levels[size] = (boxDown(C, side: n, factor: f), boxDown(B, side: n, factor: f), boxDown(L, side: n, factor: f))
            }
            let level = levels[size]!
            let scales = pass.scales ?? steps(around: s0, by: pass.radius > 2 ? 0.0025 : 0.001, count: pass.radius > 2 ? 4 : 10)
            let best = search(
                concept: level.C, under: level.B, layer: level.L, side: size, scales: scales, radius: pass.radius, guess: g,
                soft: soft)
            s0 = best.scale
            g = (best.x, best.y)
        }
        let k = Double(n) / Double(previous)
        var fit = Fit(scale: s0, dx: g.x * k, dy: g.y * k)
        var placed = warp(L, side: n, scale: s0, dx: fit.dx, dy: fit.dy)
        if soft {
            fit.opacity = bestOpacity(placed, under: B, concept: C)
            let o = Float(fit.opacity)
            vDSP.multiply(o, placed, result: &placed)
        }
        return Placement(layer: LayerImage(width: n, height: n, premultiplied: placed), fit: fit)
    }

    /// The fit that lays `solid`, a drawing's solid bounds, into `box`: one scale for both sides, its top left on the
    /// box's. What the boxed search starts from, and all a layer only in Dark gets, since the pick has nothing to
    /// search against.
    public static func boxed(_ solid: LayerBox, into box: LayerBox, side n: Int) -> Fit {
        let s = (Double(box.width) / Double(solid.width) + Double(box.height) / Double(solid.height)) / 2
        let tx = Double(box.x0) - s * Double(solid.x0)
        let ty = Double(box.y0) - s * Double(solid.y0)
        return Fit(scale: s, dx: tx - (1 - s) * Double(n) / 2, dy: ty - (1 - s) * Double(n) / 2)
    }

    /// `layer` placed by a known fit (Dark's copy of a ground shares the ground's), at its own
    /// side, with its alpha scaled by the fit's opacity.
    public static func place(_ layer: LayerImage, with fit: Fit) -> LayerImage {
        precondition(layer.isSquare, "a layer is square")
        var placed = warp(layer.premultiplied(), side: layer.width, scale: fit.scale, dx: fit.dx, dy: fit.dy)
        if fit.opacity != 1 { vDSP.multiply(Float(fit.opacity), placed, result: &placed) }
        return LayerImage(width: layer.width, height: layer.width, premultiplied: placed)
    }

    // MARK: The search

    /// `centre ± k·step` for k up to `count`, in order.
    static func steps(around centre: Double, by step: Double, count: Int) -> [Double] {
        (-count...count).map { centre + Double($0) * step }
    }

    /// The scale and shift (in this level's pixels) with the least error, every scale in
    /// `scales` and every whole-pixel shift within `radius` of `guess`. Ties go to the first
    /// scale, then the first shift row by row, as the prototype's loops did.
    static func search(
        concept C: [Float], under B: [Float], layer L: [Float], side n: Int, scales: [Double], radius R: Int,
        guess: (x: Double, y: Double), soft: Bool = false
    ) -> (scale: Double, x: Double, y: Double) {
        let ground = groundTerms(concept: C, under: B, side: n, pad: 2 * R)
        var results = [(error: Double, dx: Int, dy: Int)](repeating: (.infinity, 0, 0), count: scales.count)
        results.withUnsafeMutableBufferPointer { results in
            let out = Disjoint(results)
            DispatchQueue.concurrentPerform(iterations: scales.count) { i in
                let terms = L.withUnsafeBufferPointer { layerTerms($0, side: n, scale: scales[i], guess: guess, radius: R) }
                out[i] = bestShift(terms, ground: ground, radius: R, soft: soft)
            }
        }
        var best = 0
        for i in results.indices where results[i].error < results[best].error { best = i }
        return (scales[best], guess.x + Double(results[best].dx), guess.y + Double(results[best].dy))
    }

    /// The error as dot products. With D = B − C, laying a premultiplied pixel (l, a) over B
    /// changes the squared error by Q + 2L, where Q = |l − aB|² = |l|² + a²|B|² − 2a l·B and
    /// L = l·D − a B·D; at opacity o it is o²Q + 2oL. So each side keeps two sets of terms per
    /// pixel, one for Q and one for 2L, and a run of layer pixels over the ground is two dot
    /// products. The ground's (`Ground`): [1, |B|², B] and [D, B·D]; the layer's
    /// (`LayerTerms`): [|l|², a², −2a l] and [2 l, −2a].
    static let quadraticCount = 5
    static let linearCount = 4

    /// The ground's terms, zero in the `pad` around the tile, so a layer pixel pushed off the
    /// tile counts nothing, as it is clipped there.
    struct Ground {
        var quadratic: [Float]
        var linear: [Float]
        /// The side of the padded planes.
        var width: Int
    }

    static func groundTerms(concept C: [Float], under B: [Float], side n: Int, pad P: Int) -> Ground {
        let w = n + 2 * P
        var q = [Float](repeating: 0, count: w * w * quadraticCount)
        var l = [Float](repeating: 0, count: w * w * linearCount)
        for y in 0..<n {
            for x in 0..<n {
                let i = (y * n + x) * 4
                let br = B[i], bg = B[i + 1], bb = B[i + 2]
                let dr = br - C[i], dg = bg - C[i + 1], db = bb - C[i + 2]
                let at = (y + P) * w + x + P
                let o = at * quadraticCount
                q[o] = 1
                q[o + 1] = br * br + bg * bg + bb * bb
                q[o + 2] = br
                q[o + 3] = bg
                q[o + 4] = bb
                let k = at * linearCount
                l[k] = dr
                l[k + 1] = dg
                l[k + 2] = db
                l[k + 3] = br * dr + bg * dg + bb * db
            }
        }
        return Ground(quadratic: q, linear: l, width: w)
    }

    /// A layer warped at one scale: its terms for every drawn pixel, kept as runs along rows
    /// (canvas coordinates, the tile plus `radius` on every side).
    struct LayerTerms {
        var quadratic: [Float] = []
        var linear: [Float] = []
        /// (canvas row, first canvas column, length, offset into the terms in pixels).
        var runs: [(y: Int, x: Int, count: Int, offset: Int)] = []
    }

    static func layerTerms(_ L: UnsafeBufferPointer<Float>, side n: Int, scale s: Double, guess: (x: Double, y: Double), radius R: Int)
        -> LayerTerms
    {
        let w = n + 2 * R
        let tx = Float((1 - s) * Double(n) / 2 + guess.x)
        let ty = Float((1 - s) * Double(n) / 2 + guess.y)
        let inv = Float(1 / s)
        var terms = LayerTerms()
        var row = [(r: Float, g: Float, b: Float, a: Float)](repeating: (0, 0, 0, 0), count: w)
        var drawn = [Bool](repeating: false, count: w)
        // Only rows and columns the scaled layer can reach.
        let first = -Float(s) - 1, last = Float(s) * Float(n + 1) + 1
        let lo = max(0, Int((tx + first).rounded(.down)) + R), hi = min(w, Int((tx + last).rounded(.up)) + R + 1)
        let top = max(0, Int((ty + first).rounded(.down)) + R), bottom = min(w, Int((ty + last).rounded(.up)) + R + 1)
        guard lo < hi, top < bottom else { return terms }
        for cy in top..<bottom {
            let v = (Float(cy - R) - ty) * inv
            var any = false
            for cx in lo..<hi {
                let p = bilinear(L, side: n, (Float(cx - R) - tx) * inv, v)
                row[cx] = p
                drawn[cx] = p.a > 0 || p.r > 0 || p.g > 0 || p.b > 0
                any = any || drawn[cx]
            }
            guard any else { continue }
            // Runs of drawn pixels; a gap of up to 8 px is bridged with zeros, fewer calls for
            // the same sum.
            var x = lo
            while x < hi {
                guard drawn[x] else {
                    x += 1
                    continue
                }
                var end = x + 1, gap = 0, last = x
                while end < hi && gap <= 8 {
                    if drawn[end] {
                        last = end
                        gap = 0
                    } else {
                        gap += 1
                    }
                    end += 1
                }
                terms.runs.append((cy, x, last - x + 1, terms.linear.count / linearCount))
                for cx in x...last {
                    let p = row[cx]
                    terms.quadratic.append(p.r * p.r + p.g * p.g + p.b * p.b)
                    terms.quadratic.append(p.a * p.a)
                    terms.quadratic.append(-2 * p.a * p.r)
                    terms.quadratic.append(-2 * p.a * p.g)
                    terms.quadratic.append(-2 * p.a * p.b)
                    terms.linear.append(2 * p.r)
                    terms.linear.append(2 * p.g)
                    terms.linear.append(2 * p.b)
                    terms.linear.append(-2 * p.a)
                }
                x = last + 1
            }
        }
        return terms
    }

    /// The whole-pixel shift within `radius` with the least error, and that error. A soft
    /// layer's error is at the shift's own best opacity.
    static func bestShift(_ terms: LayerTerms, ground: Ground, radius R: Int, soft: Bool = false) -> (error: Double, dx: Int, dy: Int) {
        guard !terms.runs.isEmpty else { return (0, 0, 0) }
        let w = ground.width
        var best = (error: Double.infinity, dx: 0, dy: 0)
        terms.quadratic.withUnsafeBufferPointer { FQ in
            terms.linear.withUnsafeBufferPointer { FL in
                ground.quadratic.withUnsafeBufferPointer { GQ in
                    ground.linear.withUnsafeBufferPointer { GL in
                        let fq = FQ.baseAddress!, fl = FL.baseAddress!, gq = GQ.baseAddress!, gl = GL.baseAddress!
                        for dy in -R...R {
                            for dx in -R...R {
                                var quadratic = 0.0, linear = 0.0
                                for run in terms.runs {
                                    // Canvas (x, y) is tile (x − R, y − R); shifted and padded by
                                    // 2R it is (x + R + dx, y + R + dy) on the ground.
                                    let at = (run.y + R + dy) * w + run.x + R + dx
                                    var sum: Float = 0
                                    vDSP_dotpr(
                                        fq + run.offset * quadraticCount, 1, gq + at * quadraticCount, 1, &sum,
                                        vDSP_Length(run.count * quadraticCount))
                                    quadratic += Double(sum)
                                    vDSP_dotpr(
                                        fl + run.offset * linearCount, 1, gl + at * linearCount, 1, &sum,
                                        vDSP_Length(run.count * linearCount))
                                    linear += Double(sum)
                                }
                                var error = quadratic + linear
                                if soft {
                                    let o = bestOpacity(quadratic: quadratic, linear: linear / 2)
                                    error = o * o * quadratic + o * linear
                                }
                                if error < best.error { best = (error, dx, dy) }
                            }
                        }
                    }
                }
            }
        }
        return best
    }

    // MARK: Pixels

    /// A buffer the concurrent loops each write their own part of.
    struct Disjoint<T>: @unchecked Sendable {
        let buffer: UnsafeMutableBufferPointer<T>

        init(_ buffer: UnsafeMutableBufferPointer<T>) { self.buffer = buffer }

        subscript(i: Int) -> T {
            get { buffer[i] }
            nonmutating set { buffer[i] = newValue }
        }
    }

    /// A premultiplied RGBA value read between pixels, clear outside the image. Pixel i's
    /// centre is at i, as OpenCV's warpAffine takes it.
    @inline(__always)
    static func bilinear(_ p: UnsafeBufferPointer<Float>, side n: Int, _ u: Float, _ v: Float) -> (r: Float, g: Float, b: Float, a: Float) {
        let x0f = u.rounded(.down), y0f = v.rounded(.down)
        guard x0f >= -1, y0f >= -1, x0f < Float(n), y0f < Float(n) else { return (0, 0, 0, 0) }
        let x0 = Int(x0f), y0 = Int(y0f)
        let fx = u - x0f, fy = v - y0f
        var r: Float = 0, g: Float = 0, b: Float = 0, a: Float = 0
        @inline(__always) func add(_ x: Int, _ y: Int, _ weight: Float) {
            guard x >= 0, y >= 0, x < n, y < n, weight > 0 else { return }
            let i = (y * n + x) * 4
            r += p[i] * weight
            g += p[i + 1] * weight
            b += p[i + 2] * weight
            a += p[i + 3] * weight
        }
        add(x0, y0, (1 - fx) * (1 - fy))
        add(x0 + 1, y0, fx * (1 - fy))
        add(x0, y0 + 1, (1 - fx) * fy)
        add(x0 + 1, y0 + 1, fx * fy)
        return (r, g, b, a)
    }

    /// A premultiplied layer scaled about the centre and shifted, bilinear, clear outside. A
    /// layer scaled under 0.8 is first resampled to about its new size (Lanczos), so the small
    /// copy is not aliased.
    static func warp(_ L: [Float], side n: Int, scale s: Double, dx: Double, dy: Double) -> [Float] {
        var source = L
        var m = n
        if s < 0.8 {
            m = max(1, Int((Double(n) * s).rounded()))
            source = LayerImage.lanczos(L, width: n, height: n, to: m, m)
        }
        // Output x maps to u = (x − t)/s on the full-size layer, and to k(u + ½) − ½ on the
        // copy resampled by k = m/n.
        let k = Double(m) / Double(n)
        let tx = (1 - s) * Double(n) / 2 + dx, ty = (1 - s) * Double(n) / 2 + dy
        let a = Float(k / s)
        let bx = Float(k * (0.5 - tx / s) - 0.5), by = Float(k * (0.5 - ty / s) - 0.5)
        var out = [Float](repeating: 0, count: n * n * 4)
        let small = source, side = m
        out.withUnsafeMutableBufferPointer { out in
            let o = Disjoint(out)
            DispatchQueue.concurrentPerform(iterations: n) { y in
                let v = a * Float(y) + by
                small.withUnsafeBufferPointer { src in
                    for x in 0..<n {
                        let p = bilinear(src, side: side, a * Float(x) + bx, v)
                        let i = (y * n + x) * 4
                        o[i] = p.r
                        o[i + 1] = p.g
                        o[i + 2] = p.b
                        o[i + 3] = p.a
                    }
                }
            }
        }
        return out
    }

    /// The opacity of `opacities` with the least whole-picture error. The error is a parabola
    /// in the opacity o: |o(l − aB) + D|² summed, so two sums give every candidate.
    static func bestOpacity(_ placed: [Float], under B: [Float], concept C: [Float]) -> Double {
        var quadratic = 0.0, linear = 0.0
        for i in stride(from: 0, to: placed.count, by: 4) {
            let a = placed[i + 3]
            guard a > 0 else { continue }
            for c in 0..<3 {
                let e = Double(placed[i + c] - a * B[i + c])
                quadratic += e * e
                linear += e * Double(B[i + c] - C[i + c])
            }
        }
        return bestOpacity(quadratic: quadratic, linear: linear)
    }

    /// The opacity o of `opacities` with the least o²·quadratic + 2o·linear.
    static func bestOpacity(quadratic: Double, linear: Double) -> Double {
        var best = opacities[0]
        var least = Double.infinity
        for o in opacities {
            let error = o * o * quadratic + 2 * o * linear
            if error < least {
                least = error
                best = o
            }
        }
        return best
    }

    /// An RGBA plane averaged over `factor` × `factor` blocks (OpenCV's area resize at a whole
    /// factor).
    static func boxDown(_ p: [Float], side n: Int, factor f: Int) -> [Float] {
        let m = n / f
        var out = [Float](repeating: 0, count: m * m * 4)
        let weight = 1 / Float(f * f)
        p.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for y in 0..<m {
                    for x in 0..<m {
                        var r: Float = 0, g: Float = 0, b: Float = 0, a: Float = 0
                        for yy in (y * f)..<(y * f + f) {
                            var i = (yy * n + x * f) * 4
                            for _ in 0..<f {
                                r += src[i]
                                g += src[i + 1]
                                b += src[i + 2]
                                a += src[i + 3]
                                i += 4
                            }
                        }
                        let o = (y * m + x) * 4
                        dst[o] = r * weight
                        dst[o + 1] = g * weight
                        dst[o + 2] = b * weight
                        dst[o + 3] = a * weight
                    }
                }
            }
        }
        return out
    }
}
