import Accelerate
import Foundation

/// The picked tile, the keys the layers are drawn on, and the tone changes the build's
/// appearances need.
extension LayerImage {
    /// The side of the tile every layer is fitted at: Icon Composer's canvas.
    public static let tileSide = 1024
    /// The side of the square the image model edits: every render's normalized size, so a
    /// drawing maps onto the tile by one resize.
    public static let referenceSide = 1254

    /// The pick's tile cropped to its pixels with alpha above 128 of 255, at 1024 px (the
    /// tile) and at 1254 px (the reference the image model edits). Throws for a pick with no such pixel.
    public static func tile(fromPick pick: LayerImage) throws -> (tile: LayerImage, reference: LayerImage) {
        guard let bounds = pick.alphaBounds(above: 128.5 / 255) else {
            throw Failure(description: "the pick has no tile: no pixel is more than half opaque")
        }
        let tile = try pick.cropped(to: bounds)
        return (tile.resized(to: tileSide), tile.resized(to: referenceSide))
    }

    // MARK: Keys

    /// A layer the image model drew on flat magenta, keyed at the size it was drawn. The drawing's own alpha is ignored.
    /// (Codex paints a checkerboard for "transparent" now and then; on magenta it also keeps the layer's size and
    /// place.)
    ///
    /// Along a solid part's outline each pixel is a mix of the part's own colour, taken from the solid pixels
    /// beside it, and the key: its alpha is how far along that line it lies, and its colour is the part's. Codex's
    /// edge has a pixel of purple and one of green where its colour channels change a pixel apart; the outermost
    /// solid pixels within a small step of the part's colour are set to it. A ramp on the distance to the key had
    /// turned quiet-pick's flat grey tile's smooth corner into steps, with a light rim and a green fringe.
    /// Elsewhere, for a glow or a part too thin to have solid pixels, alpha ramps with the distance to the key and
    /// the colour is unmixed from it.
    public func unkeyedMagenta() -> LayerImage {
        let n = width * height
        let key = keyColour(near: SIMD3(1, 0, 1))
        var distance = [Float](repeating: 0, count: n)
        var colour = [Float](repeating: 0, count: n * 4)
        pixels.withUnsafeBufferPointer { p in
            for i in 0..<n {
                let d = SIMD3(p[i * 4], p[i * 4 + 1], p[i * 4 + 2]) - key
                distance[i] = (d * d).sum().squareRoot()
            }
        }
        // solid: as far from the key as any part sits; inside: solid, and clear of the outline's ring
        let solid = distance.map { $0 >= Self.solidDistance }
        let ring = max(1, width / 600)
        let inside = zip(solid, Self.dilated(solid.map { !$0 }, width: width, height: height, radius: ring)).map { $0 && !$1 }
        for i in 0..<n where inside[i] {
            for c in 0..<3 { colour[i * 4 + c] = pixels[i * 4 + c] }
            colour[i * 4 + 3] = 1
        }
        var out = pixels
        var settled = inside
        // the outline's solid ring: within a small step of the part's colour nearby, it is that colour. Further in,
        // within the band the key spills into, a pixel off the part's colour loses red and blue above green:
        // sleep-dial's pointer had a purple line along its shaded edge. The part's own colour, purple or not, stays.
        let insideMean = Self.boxSums(colour, width: width, height: height, radius: ring + 2)
        let spilled = Self.dilated(solid.map { !$0 }, width: width, height: height, radius: max(ring, width / 256))
        for i in 0..<n where solid[i] && spilled[i] {
            out[i * 4 + 3] = 1
            settled[i] = true
            let drawn = SIMD3(pixels[i * 4], pixels[i * 4 + 1], pixels[i * 4 + 2])
            var c = drawn, k: Float = 1
            let count = insideMean[i * 4 + 3]
            if count >= 3 {
                let own = SIMD3(insideMean[i * 4], insideMean[i * 4 + 1], insideMean[i * 4 + 2]) / count
                let off = drawn - own
                k = Self.smoothstep(Self.fringeStep, 2.5 * Self.fringeStep, (off * off).sum().squareRoot())
                if !inside[i] { c = own + off * k }
            }
            let spill = max(0, min(c.x, c.z) - c.y) * k
            out[i * 4] = c.x - spill
            out[i * 4 + 1] = c.y
            out[i * 4 + 2] = c.z - spill
        }
        // the antialiased pixels beyond it: along the line from the key to the solid colour beside them
        for i in 0..<n where solid[i] {
            for c in 0..<3 { colour[i * 4 + c] = out[i * 4 + c] }
            colour[i * 4 + 3] = 1
        }
        let solidMean = Self.boxSums(colour, width: width, height: height, radius: ring)
        for i in 0..<n where !solid[i] {
            let count = solidMean[i * 4 + 3]
            guard count >= 1 else { continue }
            let own = SIMD3(solidMean[i * 4], solidMean[i * 4 + 1], solidMean[i * 4 + 2]) / count
            let span = own - key
            let length = (span * span).sum()
            // a part near the key's own colour has no line to measure along
            guard length > 0.09 else { continue }
            let drawn = SIMD3(pixels[i * 4], pixels[i * 4 + 1], pixels[i * 4 + 2])
            out[i * 4] = own.x
            out[i * 4 + 1] = own.y
            out[i * 4 + 2] = own.z
            out[i * 4 + 3] = min(max(((drawn - key) * span).sum() / length, 0), 1)
            settled[i] = true
        }
        // the rest: alpha from the distance to the key, the colour unmixed from it
        for i in 0..<n where !settled[i] {
            let a = min(max((distance[i] - 0.25) / 0.5, 0), 1)
            let d = max(a, 1e-3)
            for c in 0..<3 { out[i * 4 + c] = min(max((pixels[i * 4 + c] - (1 - a) * key[c]) / d, 0), 1) }
            out[i * 4 + 3] = a
        }
        // Unmixed against a guessed alpha, a faint pixel keeps some key: the caliper's button had a purple rim in
        // Dark. Within a few pixels of the clear area, red and blue above green are spill and go; solid colour
        // further in, which may be purple on purpose, is left.
        let band = Self.near(clear: out, width: width, height: height, radius: max(2, width / 256))
        for (i, isNear) in band.enumerated() where isNear && !settled[i] {
            let spill = max(0, min(out[i * 4], out[i * 4 + 2]) - out[i * 4 + 1])
            out[i * 4] -= spill
            out[i * 4 + 2] -= spill
        }
        return LayerImage(width: width, height: height, pixels: out)
    }

    /// How far from the key, in sRGB, a pixel is surely the part: a dark grey part mixed two thirds with magenta.
    static let solidDistance: Float = 0.75
    /// How far a solid pixel on the outline may be off the part's colour nearby and still be Codex's fringe, not a
    /// drawn line: its purple and green pixels were 0.05 to 0.08 off the grey tile, a drawn rim is far more.
    static let fringeStep: Float = 0.08

    /// The key as Codex painted it, the mean of the pixels near `ideal`: (248, 1, 248) as often as pure magenta.
    func keyColour(near ideal: SIMD3<Float>) -> SIMD3<Float> {
        var sum = SIMD3<Float>(repeating: 0), count: Float = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let c = SIMD3(pixels[i], pixels[i + 1], pixels[i + 2])
            let d = c - ideal
            if (d * d).sum() < 0.04 {
                sum += c
                count += 1
            }
        }
        return count > 0 ? sum / count : ideal
    }

    @inline(__always) static func smoothstep(_ from: Float, _ to: Float, _ x: Float) -> Float {
        let t = min(max((x - from) / (to - from), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Each pixel's sum of `plane`, `channels` values a pixel, over the square of `radius` around it, clipped to
    /// the image: running sums along rows, then columns, so the cost does not grow with the radius.
    static func boxSums(_ plane: [Float], channels k: Int = 4, width: Int, height: Int, radius r: Int) -> [Float] {
        var rows = [Float](repeating: 0, count: plane.count)
        var out = [Float](repeating: 0, count: plane.count)
        var sum = [Float](repeating: 0, count: k)
        plane.withUnsafeBufferPointer { p in
            rows.withUnsafeMutableBufferPointer { q in
                for y in 0..<height {
                    let base = y * width * k
                    for c in 0..<k { sum[c] = 0 }
                    for x in 0..<min(r, width) { for c in 0..<k { sum[c] += p[base + x * k + c] } }
                    for x in 0..<width {
                        if x + r < width { for c in 0..<k { sum[c] += p[base + (x + r) * k + c] } }
                        if x - r - 1 >= 0 { for c in 0..<k { sum[c] -= p[base + (x - r - 1) * k + c] } }
                        for c in 0..<k { q[base + x * k + c] = sum[c] }
                    }
                }
            }
        }
        rows.withUnsafeBufferPointer { p in
            out.withUnsafeMutableBufferPointer { q in
                let stride = width * k
                for x in 0..<width {
                    let base = x * k
                    for c in 0..<k { sum[c] = 0 }
                    for y in 0..<min(r, height) { for c in 0..<k { sum[c] += p[y * stride + base + c] } }
                    for y in 0..<height {
                        if y + r < height { for c in 0..<k { sum[c] += p[(y + r) * stride + base + c] } }
                        if y - r - 1 >= 0 { for c in 0..<k { sum[c] -= p[(y - r - 1) * stride + base + c] } }
                        for c in 0..<k { q[y * stride + base + c] = sum[c] }
                    }
                }
            }
        }
        return out
    }

    /// Pixels within `radius` of one under half alpha, the outline's band.
    static func near(clear pixels: [Float], width: Int, height: Int, radius: Int) -> [Bool] {
        dilated((0..<(width * height)).map { pixels[$0 * 4 + 3] < 0.5 }, width: width, height: height, radius: radius)
    }

    /// Light drawn on black: its brightness is its alpha, the rest its colour. Glows keyed
    /// off magenta came back with red and cyan rings; off black they come clean.
    public func unkeyedBlack() -> LayerImage {
        var out = pixels
        out.withUnsafeMutableBufferPointer { p in
            for i in stride(from: 0, to: p.count, by: 4) {
                let m = max(p[i], p[i + 1], p[i + 2])
                let d = max(m, 1e-3)
                for c in i..<(i + 3) { p[c] = min(max(p[c] / d, 0), 1) }
                p[i + 3] = min(max((m - 0.02) / 0.98, 0), 1)
            }
        }
        return LayerImage(width: width, height: height, pixels: out)
    }

    /// Whether any pixel is clearly see-through (alpha under 250 of 255): a layer that comes
    /// back without is a painted checkerboard or a backdrop, and is drawn again on a key.
    public var hasAlpha: Bool {
        var low: Float = 1
        pixels.withUnsafeBufferPointer { p in
            for i in stride(from: 3, to: p.count, by: 4) where p[i] < low { low = p[i] }
        }
        return byte(low) < 250
    }

    /// Whether the image is opaque and at least a fifth of it is the magenta key: a layer
    /// the image model drew on magenta though the plan did not ask for it.
    public var isOnMagenta: Bool {
        guard !hasAlpha else { return false }
        var keyed = 0
        pixels.withUnsafeBufferPointer { p in
            for i in stride(from: 0, to: p.count, by: 4)
            where byte(p[i]) > 220 && byte(p[i + 1]) < 40 && byte(p[i + 2]) > 220 { keyed += 1 }
        }
        return Double(keyed) > 0.2 * Double(width * height)
    }

    // MARK: Tone

    /// Rec. 709 luminance weights on the sRGB-encoded values, as the prototype took them.
    static let luma: SIMD3<Float> = [0.2126, 0.7152, 0.0722]

    /// The luminance in all three channels, alpha kept: plain metal that Codex keeps giving a
    /// colour cast (the caliper's copper knurl, through two prompts).
    public func greyed() -> LayerImage {
        var out = pixels
        out.withUnsafeMutableBufferPointer { p in
            for i in stride(from: 0, to: p.count, by: 4) {
                let y = min(max(p[i] * Self.luma.x + p[i + 1] * Self.luma.y + p[i + 2] * Self.luma.z, 0), 1)
                p[i] = y
                p[i + 1] = y
                p[i + 2] = y
            }
        }
        return LayerImage(width: width, height: height, pixels: out)
    }

    /// The median colour of the given pixels in OKLab, its lightness on the toe; nil for too few to judge.
    static func medianColour(_ image: LayerImage, at region: [Int]) -> SIMD3<Float>? {
        guard region.count >= 400 else { return nil }
        var l: [Float] = [], a: [Float] = [], b: [Float] = []
        for i in region {
            let lab = oklab(SIMD3(image.pixels[i * 4], image.pixels[i * 4 + 1], image.pixels[i * 4 + 2]))
            l.append(toe(lab.x))
            a.append(lab.y)
            b.append(lab.z)
        }
        func median(_ v: [Float]) -> Float { v.sorted()[v.count / 2] }
        return SIMD3(median(l), median(a), median(b))
    }

    /// The layer's solid pixels 6 px clear of its outline, as the edge check takes them, as pixel indices.
    var solidInside: [Int] {
        let near = Self.dilated(mask.map { !$0 }, width: width, height: height, radius: 6)
        return (0..<(width * height)).filter { pixels[$0 * 4 + 3] > 0.99 && !near[$0] }
    }

    /// `"match": true`: the layer moved onto the pick's colour, every pixel shifted in OKLab by the difference
    /// between the medians of its solid inside and of the pick there, so shading and texture stay. quiet-pick's
    /// grey tile, 49 in the pick, came back between 54 and 63 in each of its three drawings.
    /// nil when the layer has too little solid inside to measure. A part a layer above hides moves the pick's median
    /// only when it covers about half the layer.
    public func matched(to pick: LayerImage) -> (image: LayerImage, shift: SIMD3<Float>)? {
        let inside = solidInside
        guard let own = Self.medianColour(self, at: inside), let theirs = Self.medianColour(pick, at: inside) else { return nil }
        let shift = theirs - own
        var out = pixels
        out.withUnsafeMutableBufferPointer { p in
            for i in stride(from: 0, to: p.count, by: 4) where p[i + 3] > 0 {
                var lab = Self.oklab(SIMD3(p[i], p[i + 1], p[i + 2]))
                lab.x = Self.untoe(max(Self.toe(lab.x) + shift.x, 0))
                lab.y += shift.y
                lab.z += shift.z
                let rgb = Self.srgbInGamut(lab)
                p[i] = rgb.x
                p[i + 1] = rgb.y
                p[i + 2] = rgb.z
            }
        }
        return (LayerImage(width: width, height: height, pixels: out), shift)
    }

    /// A layer's `"dark": "pick"` copy: the layer recoloured to the pick's colour across a change of hue. Lightness
    /// moves as in `matched(to:)`; chroma is scaled by the ratio of the pick's median to the layer's and hue turned by
    /// the angle between them, so no pixel crosses neutral. A flat shift sent the brown eclipse disc's darker rim,
    /// less brown than its median, past grey into blue. nil when the layer has too little solid inside to measure.
    public func recoloured(to pick: LayerImage) -> LayerImage? {
        let inside = solidInside
        guard let own = Self.medianColour(self, at: inside), let theirs = Self.medianColour(pick, at: inside) else { return nil }
        return recoloured(from: own, to: theirs)
    }

    /// A layer's `"dark": {"tone": "#rrggbb"}` copy: recoloured as under `"pick"`, onto `colour` (sRGB 0...1) instead
    /// of the pick's, so the median of its solid inside lands on that colour. nil as under `"pick"`.
    public func recoloured(toColour colour: SIMD3<Float>) -> LayerImage? {
        guard let own = Self.medianColour(self, at: solidInside) else { return nil }
        let lab = Self.oklab(colour)
        return recoloured(from: own, to: SIMD3(Self.toe(lab.x), lab.y, lab.z))
    }

    /// Every pixel moved from the median `own` to `theirs`, both toe-corrected OKLab. A near-neutral layer has no hue
    /// to turn, so it moves flatly, as under match.
    private func recoloured(from own: SIMD3<Float>, to theirs: SIMD3<Float>) -> LayerImage {
        let ownChroma = (own.y * own.y + own.z * own.z).squareRoot()
        let turns = ownChroma > 0.01
        let scale = turns ? (theirs.y * theirs.y + theirs.z * theirs.z).squareRoot() / ownChroma : 1
        let turn = turns ? atan2(theirs.z, theirs.y) - atan2(own.z, own.y) : 0
        let cosine = cos(turn) * scale, sine = sin(turn) * scale
        let shift = turns ? SIMD3(theirs.x - own.x, 0, 0) : theirs - own
        var out = pixels
        out.withUnsafeMutableBufferPointer { p in
            for i in stride(from: 0, to: p.count, by: 4) where p[i + 3] > 0 {
                var lab = Self.oklab(SIMD3(p[i], p[i + 1], p[i + 2]))
                lab.x = Self.untoe(max(Self.toe(lab.x) + shift.x, 0))
                (lab.y, lab.z) = (lab.y * cosine - lab.z * sine + shift.y, lab.y * sine + lab.z * cosine + shift.z)
                let rgb = Self.srgbInGamut(lab)
                p[i] = rgb.x
                p[i + 1] = rgb.y
                p[i + 2] = rgb.z
            }
        }
        return LayerImage(width: width, height: height, pixels: out)
    }

    /// Dark's ground for a ground that is dark already: the same pixels at `factor` of their
    /// level, opaque. Visibly apart from Default, and its texture stays pixel for pixel.
    public func dimmed(_ factor: Float = 0.8) -> LayerImage {
        var out = premultiplied()
        out.withUnsafeMutableBufferPointer { p in
            for i in stride(from: 0, to: p.count, by: 4) {
                for c in i..<(i + 3) { p[c] = min(max(p[c] * factor, 0), 1) }
                p[i + 3] = 1
            }
        }
        return LayerImage(width: width, height: height, pixels: out)
    }

    /// Dark's ground in the user's own colour, `dark: {"tone": "#rrggbb"}`: every pixel is `colour` times its
    /// luminance over the ground's mean, so the grain, the rolled edge and the light's fall-off stay while the hue
    /// goes. Opaque, as a ground is.
    public func toned(_ colour: SIMD3<Float>) -> LayerImage {
        let weights = SIMD3<Float>(0.2126, 0.7152, 0.0722)
        var luma = [Float](repeating: 0, count: width * height)
        var sum: Float = 0
        for i in 0..<luma.count {
            let rgb = SIMD3(pixels[i * 4], pixels[i * 4 + 1], pixels[i * 4 + 2])
            luma[i] = (rgb * weights).sum()
            sum += luma[i]
        }
        let mean = max(sum / Float(max(luma.count, 1)), 1e-4)
        var out = [Float](repeating: 1, count: pixels.count)
        for i in 0..<luma.count {
            let k = min(luma[i] / mean, 2)
            for c in 0..<3 { out[i * 4 + c] = min(max(colour[c] * k, 0), 1) }
        }
        return LayerImage(width: width, height: height, pixels: out)
    }

    /// The layer for a Dark that recolours the ground: the ground's own hue taken out of it. A part drawn on an
    /// orange housing reflects orange (the caliper's black button had an orange ring in its socket), which is right
    /// over the orange of Default and reads as orange light over Dark's black. Pixels near the ground's hue lose
    /// their saturation, fully at the hue and none from 35° away. Nil when there is nothing to take out: a grey
    /// ground has no hue, and a part mostly of the ground's own colour is that colour, not a reflection of it.
    public func withoutCast(of ground: SIMD3<Float>) -> LayerImage? {
        let g = Self.hsv(ground)
        guard g.s > 0.2 else { return nil }
        let reach: Float = 35
        var solid = 0, coloured = 0, ofGround = 0
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] > 0.5 {
            solid += 1
            let c = Self.hsv(SIMD3(pixels[i], pixels[i + 1], pixels[i + 2]))
            guard c.s > 0.25, c.v > 0.04 else { continue }
            coloured += 1
            if Self.hueDistance(c.h, g.h) < reach { ofGround += 1 }
        }
        // the part's own colour is the ground's: an orange part on an orange ground keeps its orange
        if coloured > solid / 3, ofGround * 2 > coloured { return nil }
        var out = pixels
        var changed = 0
        for i in stride(from: 0, to: out.count, by: 4) where out[i + 3] > 0 {
            var c = Self.hsv(SIMD3(out[i], out[i + 1], out[i + 2]))
            let w = max(0, 1 - Self.hueDistance(c.h, g.h) / reach)
            guard w > 0, c.s > 0.05 else { continue }
            c.s *= 1 - w
            let rgb = Self.rgb(c)
            out[i] = rgb.x
            out[i + 1] = rgb.y
            out[i + 2] = rgb.z
            changed += 1
        }
        return changed == 0 ? nil : LayerImage(width: width, height: height, pixels: out)
    }

    static func hueDistance(_ a: Float, _ b: Float) -> Float {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    /// Hue in degrees, saturation and value, 0...1.
    static func hsv(_ c: SIMD3<Float>) -> (h: Float, s: Float, v: Float) {
        let mx = c.max(), mn = c.min(), d = mx - mn
        guard d > 1e-6 else { return (0, 0, mx) }
        var h: Float
        if mx == c.x { h = (c.y - c.z) / d } else if mx == c.y { h = 2 + (c.z - c.x) / d } else { h = 4 + (c.x - c.y) / d }
        h *= 60
        if h < 0 { h += 360 }
        return (h, mx > 0 ? d / mx : 0, mx)
    }

    static func rgb(_ c: (h: Float, s: Float, v: Float)) -> SIMD3<Float> {
        let k = { (n: Float) -> Float in
            let x = (n + c.h / 60).truncatingRemainder(dividingBy: 6)
            return c.v - c.v * c.s * max(0, min(x, 4 - x, 1))
        }
        return SIMD3(k(5), k(3), k(1))
    }

    /// The narrowest spread of luminance `lifted()` stretches onto its whole range. The trial's shaded heroes
    /// spread 0.22 to 0.70; a flat layer spreads only its dither, which stretched over the range came out as grain.
    static let liftMinSpan: Float = 0.2

    /// Mono's hero lift: Clear and Tinted draw a dark layer as clear glass, so the hero becomes
    /// light grey there with its own shading kept. Its luminance, stretched from the 2nd to the
    /// 98th percentile of its solid pixels (alpha over 0.5) onto 0.62...1, alpha kept. A spread
    /// under `liftMinSpan` is stretched as if it were that wide, about its middle, so a flat
    /// layer lifts to a flat 0.81.
    public func lifted() -> LayerImage {
        var y = [Float](repeating: 0, count: width * height)
        var solid: [Float] = []
        pixels.withUnsafeBufferPointer { p in
            for i in 0..<(width * height) {
                let v = p[i * 4] * Self.luma.x + p[i * 4 + 1] * Self.luma.y + p[i * 4 + 2] * Self.luma.z
                y[i] = v
                if p[i * 4 + 3] > 0.5 { solid.append(v) }
            }
        }
        var lo: Float = 0, hi: Float = 1
        if !solid.isEmpty {
            vDSP.sort(&solid, sortOrder: .ascending)
            lo = Self.percentile(solid, 2)
            hi = Self.percentile(solid, 98)
        }
        let span = max(hi - lo, Self.liftMinSpan)
        let from = (lo + hi - span) / 2
        var out = pixels
        for i in 0..<(width * height) {
            let v = 0.62 + 0.38 * min(max((y[i] - from) / span, 0), 1)
            out[i * 4] = v
            out[i * 4 + 1] = v
            out[i * 4 + 2] = v
        }
        return LayerImage(width: width, height: height, pixels: out)
    }

    /// Dark's copy of a layer, or Dark's ground, for `"dark": "invert"`: lightness flipped while hue,
    /// chroma, alpha and shading stay. Flipped in OKLab on its toe-corrected lightness (Ottosson's
    /// Lr, which tracks CIELAB's L*), so a warm near-black becomes a warm near-white; a plain RGB
    /// invert gives a cool white and plain OKLab L only a light grey. A colour the flip takes out
    /// of sRGB loses chroma, not hue, until it fits.
    public func inverted() -> LayerImage {
        var out = pixels
        out.withUnsafeMutableBufferPointer { p in
            for i in stride(from: 0, to: p.count, by: 4) {
                var lab = Self.oklab(SIMD3(p[i], p[i + 1], p[i + 2]))
                lab.x = Self.untoe(1 - Self.toe(lab.x))
                let rgb = Self.srgbInGamut(lab)
                p[i] = rgb.x
                p[i + 1] = rgb.y
                p[i + 2] = rgb.z
            }
        }
        return LayerImage(width: width, height: height, pixels: out)
    }

    // MARK: OKLab

    /// The sRGB transfer, encoded to linear.
    @inline(__always) static func linear(_ c: Float) -> Float { c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4) }
    @inline(__always) static func encoded(_ c: Float) -> Float {
        let c = min(max(c, 0), 1)
        return c <= 0.0031308 ? c * 12.92 : 1.055 * powf(c, 1 / 2.4) - 0.055
    }

    /// OKLab (L, a, b) of an sRGB-encoded colour.
    static func oklab(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let r = linear(c.x), g = linear(c.y), b = linear(c.z)
        let l = cbrtf(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrtf(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrtf(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return SIMD3(
            0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    /// Linear sRGB of an OKLab colour, unclamped.
    static func linearRGB(oklab c: SIMD3<Float>) -> SIMD3<Float> {
        let l = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z
        let m = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z
        let s = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z
        let l3 = l * l * l, m3 = m * m * m, s3 = s * s * s
        return SIMD3(
            4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3,
            -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3,
            -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3)
    }

    /// sRGB-encoded values of an OKLab colour, its chroma reduced at the same hue and lightness until it fits.
    static func srgbInGamut(_ c: SIMD3<Float>) -> SIMD3<Float> {
        func fits(_ v: SIMD3<Float>) -> Bool { v.min() >= -1e-4 && v.max() <= 1 + 1e-4 }
        var rgb = linearRGB(oklab: c)
        if !fits(rgb) {
            var lo: Float = 0, hi: Float = 1
            for _ in 0..<12 {
                let k = (lo + hi) / 2
                if fits(linearRGB(oklab: SIMD3(c.x, c.y * k, c.z * k))) { lo = k } else { hi = k }
            }
            rgb = linearRGB(oklab: SIMD3(c.x, c.y * lo, c.z * lo))
        }
        return SIMD3(encoded(rgb.x), encoded(rgb.y), encoded(rgb.z))
    }

    /// Ottosson's toe: OKLab L onto a lightness scale close to CIELAB's L* / 100, and back.
    static let toeK1: Float = 0.206, toeK2: Float = 0.03, toeK3: Float = (1 + 0.206) / (1 + 0.03)
    static func toe(_ x: Float) -> Float {
        let t = toeK3 * x - toeK1
        return 0.5 * (t + (t * t + 4 * toeK2 * toeK3 * x).squareRoot())
    }
    static func untoe(_ x: Float) -> Float { (x * x + toeK1 * x) / (toeK3 * (x + toeK2)) }

    /// numpy's default percentile of sorted values: linear between the two nearest ranks.
    static func percentile(_ sorted: [Float], _ q: Float) -> Float {
        let rank = q / 100 * Float(sorted.count - 1)
        let below = Int(rank.rounded(.down))
        let above = min(below + 1, sorted.count - 1)
        let t = rank - Float(below)
        return sorted[below] * (1 - t) + sorted[above] * t
    }
}

/// A 0...1 value as the byte a PNG would store.
@inline(__always) func byte(_ v: Float) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
