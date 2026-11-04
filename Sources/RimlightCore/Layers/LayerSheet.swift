import CoreGraphics
import CoreText
import Foundation

/// The pictures the agent and the user read a build by: a sheet of labelled cells, the tile
/// with a grid in tile pixels (what the agent places boxes on), and a zoom of one box across
/// several images.
extension LayerImage {
    /// A grid of cells on mid grey, each image scaled to fit its cell (aspect kept, centred)
    /// with its label on a dark tab at the top left. Rows may differ in length; the sheet is
    /// as wide as the longest. Put a layer with alpha on `onCheckerboard()` first, so its clear
    /// parts read as clear.
    public static func sheet(rows: [[(label: String, image: LayerImage)]], cell: Int = 384) throws -> LayerImage {
        let columns = max(1, rows.map(\.count).max() ?? 1)
        let canvas = try Canvas(width: columns * cell, height: max(1, rows.count) * cell, grey: 128)
        for (r, row) in rows.enumerated() {
            for (c, item) in row.enumerated() {
                let k = Double(cell) / Double(max(item.image.width, item.image.height))
                let w = Double(item.image.width) * k, h = Double(item.image.height) * k
                let x = Double(c * cell) + (Double(cell) - w) / 2, y = Double(r * cell) + (Double(cell) - h) / 2
                try canvas.draw(item.image, in: CGRect(x: x, y: y, width: w, height: h))
                canvas.label(item.label, x: Double(c * cell), y: Double(r * cell))
            }
        }
        return try canvas.image()
    }

    /// The image on dark grey with a thin line every `step` px and a label every
    /// `labelEvery` px, in the image's own (tile) pixels: yellow along x, cyan along y. With
    /// `box`, only that part, scaled up to about 1024 px on its long side, so a finer step
    /// still reads. Every line is labelled once its lines are 50 px apart, room for a
    /// four-digit label; closer, only the `labelEvery` lines are.
    public func gridOverlay(step: Int = 32, labelEvery: Int = 128, box: LayerBox? = nil) throws -> LayerImage {
        precondition(step > 0 && labelEvery > 0, "a grid needs a step")
        let region = box ?? LayerBox(x0: 0, y0: 0, x1: width, y1: height)
        let part = box == nil ? self : try cropped(to: region)
        let x0 = max(0, region.x0), y0 = max(0, region.y0)
        let scale = box == nil ? 1 : max(1, 1024 / Double(max(part.width, part.height)))
        let W = Int((Double(part.width) * scale).rounded()), H = Int((Double(part.height) * scale).rounded())
        let canvas = try Canvas(width: W, height: H, grey: 90)
        try canvas.draw(part, in: CGRect(x: 0, y: 0, width: W, height: H))
        let size = 14.0
        let labelAll = Double(step) * scale >= 50
        let yellow = CGColor(srgbRed: 1, green: 1, blue: 0, alpha: 1), cyan = CGColor(srgbRed: 0, green: 1, blue: 1, alpha: 1)
        func strong(_ v: Int) -> Bool { v % labelEvery == 0 }
        func line(at offset: Double, vertical: Bool, strong: Bool) {
            let shadow = Canvas.grey(0, strong ? 0.45 : 0.25)
            let light = strong ? CGColor(srgbRed: 1, green: 1, blue: 0, alpha: 0.8) : Canvas.grey(1, 0.32)
            if vertical {
                canvas.fill(CGRect(x: offset + 1, y: 0, width: 1, height: Double(H)), shadow)
                canvas.fill(CGRect(x: offset, y: 0, width: 1, height: Double(H)), light)
            } else {
                canvas.fill(CGRect(x: 0, y: offset + 1, width: Double(W), height: 1), shadow)
                canvas.fill(CGRect(x: 0, y: offset, width: Double(W), height: 1), light)
            }
        }
        let firstX = (x0 + step - 1) / step * step, firstY = (y0 + step - 1) / step * step
        let lastX = x0 + part.width, lastY = y0 + part.height
        for gx in stride(from: firstX, through: lastX, by: step) {
            line(at: ((Double(gx - x0)) * scale).rounded(), vertical: true, strong: strong(gx))
        }
        for gy in stride(from: firstY, through: lastY, by: step) {
            line(at: ((Double(gy - y0)) * scale).rounded(), vertical: false, strong: strong(gy))
        }
        // Labels after every line, so no line crosses one.
        for gx in stride(from: firstX, through: lastX, by: step) where strong(gx) || labelAll {
            let X = ((Double(gx - x0)) * scale).rounded()
            for Y in [2, Double(H) / 2, Double(H) - size - 6] {
                canvas.label(String(gx), x: X + 2, y: Y, size: size, colour: yellow)
            }
        }
        for gy in stride(from: firstY, through: lastY, by: step) where strong(gy) || labelAll {
            let Y = ((Double(gy - y0)) * scale).rounded()
            // Clear of the top row of x labels.
            guard Y > size + 8 else { continue }
            for X in [2, Double(W) / 2 + 40, Double(W) - 48] {
                canvas.label(String(gy), x: X, y: Y + 2, size: size, colour: cyan)
            }
        }
        return try canvas.image()
    }

    /// Several images cropped to one box (pixels of the first image; any other size is resized
    /// to it first) and laid side by side 8 px apart, each scaled up by the least whole factor
    /// that makes the box at least `minSide` px, pixel for pixel (nearest), and labelled.
    public static func zoom(_ images: [(label: String, image: LayerImage)], box: LayerBox, minSide: Int = 360) throws -> LayerImage {
        guard let first = images.first?.image else { throw Failure(description: "a zoom needs an image") }
        let long = max(box.width, box.height)
        let k = max(1, (minSide + long - 1) / long)
        let w = box.width * k, h = box.height * k, gap = 8
        let canvas = try Canvas(width: images.count * (w + gap) - gap, height: h, grey: 128)
        for (n, item) in images.enumerated() {
            let same = item.image.width == first.width && item.image.height == first.height
            let part = try (same ? item.image : item.image.resized(width: first.width, height: first.height)).cropped(to: box)
            let x = Double(n * (w + gap))
            // A box past the image's edge keeps its place: the crop sits where it falls in the box.
            let left = Double(max(0, box.x0) - box.x0) * Double(k), top = Double(max(0, box.y0) - box.y0) * Double(k)
            try canvas.draw(part, in: CGRect(x: x + left, y: top, width: Double(part.width * k), height: Double(part.height * k)), smooth: false)
            canvas.label(item.label, x: x, y: 0)
        }
        return try canvas.image()
    }
}

extension LayerImage {
    /// The side of an outline crop, tile px: small enough that a sheet holds several at 1:1, large enough to follow a
    /// curve.
    public static let outlineCell = 160

    /// Boxes that cover the outline of `mask` (pixels beside one outside it) where `hidden` is false, `cell` px apart
    /// on a grid from the outline's top left, each grown by `margin` so an edge on a cell's border shows whole. Rows
    /// top to bottom, left to right; a cell with a few stray pixels of outline is left out.
    public static func outlineBoxes(_ mask: [Bool], hidden: [Bool], side n: Int, cell: Int = outlineCell, margin: Int = 8) -> [LayerBox] {
        var points: [(x: Int, y: Int)] = []
        for y in 0..<n {
            for x in 0..<n {
                let i = y * n + x
                guard mask[i], !hidden[i] else { continue }
                if x == 0 || y == 0 || x == n - 1 || y == n - 1 || !mask[i - 1] || !mask[i + 1] || !mask[i - n] || !mask[i + n] {
                    points.append((x, y))
                }
            }
        }
        guard let x0 = points.map(\.x).min(), let y0 = points.map(\.y).min() else { return [] }
        var counts: [Int: Int] = [:]
        let columns = (n - x0 + cell - 1) / cell
        for p in points { counts[((p.y - y0) / cell) * columns + (p.x - x0) / cell, default: 0] += 1 }
        return counts.filter { $0.value >= 8 }.keys.sorted().map { k in
            let x = x0 + (k % columns) * cell, y = y0 + (k / columns) * cell
            return LayerBox(x0: max(0, x - margin), y0: max(0, y - margin), x1: min(n, x + cell + margin), y1: min(n, y + cell + margin))
        }
    }

    /// Sheets of 1:1 crops, one per box: each box's crop of every image side by side under a strip naming the box,
    /// `columns` boxes across and `rows` down a sheet, as few sheets as hold them all.
    public static func cropSheets(
        _ images: [(label: String, image: LayerImage)], boxes: [LayerBox], columns: Int = 2, rows: Int = 6
    ) throws -> [LayerImage] {
        guard let first = images.first?.image, !boxes.isEmpty else { return [] }
        let images = images.map { ($0.label, $0.image.width == first.width && $0.image.height == first.height ? $0.image
            : $0.image.resized(width: first.width, height: first.height)) }
        let side = boxes.map { max($0.width, $0.height) }.max()!
        let gap = 4, strip = 20, pad = 12
        let groupWidth = images.count * (side + gap) - gap
        var sheets: [LayerImage] = []
        for start in stride(from: 0, to: boxes.count, by: columns * rows) {
            let page = Array(boxes[start..<min(boxes.count, start + columns * rows)])
            let used = (page.count + columns - 1) / columns
            let canvas = try Canvas(
                width: min(columns, page.count) * (groupWidth + pad) - pad, height: used * (side + strip + pad) - pad, grey: 128)
            for (k, box) in page.enumerated() {
                let x = Double((k % columns) * (groupWidth + pad)), y = Double((k / columns) * (side + strip + pad))
                canvas.label(box.values.map(String.init).joined(separator: ",") + "  " + images.map(\.0).joined(separator: " | "),
                    x: x, y: y, size: 12)
                for (j, item) in images.enumerated() {
                    let part = try item.1.cropped(to: box)
                    let left = x + Double(j * (side + gap)) + Double(max(0, box.x0) - box.x0)
                    try canvas.draw(part, in: CGRect(x: left, y: y + Double(strip), width: Double(part.width), height: Double(part.height)),
                        smooth: false)
                }
            }
            sheets.append(try canvas.image())
        }
        return sheets
    }
}

/// An 8-bit sRGB drawing surface measured from the top left, as the images are.
struct Canvas {
    let context: CGContext
    let width: Int
    let height: Int

    init(width: Int, height: Int, grey: Int) throws {
        guard width > 0, height > 0,
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: LayerImage.sRGB,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw LayerImage.Failure(description: "cannot make a \(width)x\(height) sheet") }
        self.context = context
        self.width = width
        self.height = height
        fill(CGRect(x: 0, y: 0, width: width, height: height), Canvas.grey(Double(grey) / 255, 1))
    }

    /// `rect` from the top left in CoreGraphics' bottom-left coordinates.
    /// A grey in sRGB; `CGColor(gray:)` is gamma 2.2 and lands lighter.
    static func grey(_ level: Double, _ alpha: Double = 1) -> CGColor {
        CGColor(srgbRed: level, green: level, blue: level, alpha: alpha)
    }

    func flipped(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: Double(height) - rect.maxY, width: rect.width, height: rect.height)
    }

    func fill(_ rect: CGRect, _ colour: CGColor) {
        context.setFillColor(colour)
        context.fill(flipped(rect))
    }

    func draw(_ image: LayerImage, in rect: CGRect, smooth: Bool = true) throws {
        context.interpolationQuality = smooth ? .high : .none
        context.draw(try image.cgImage(), in: flipped(rect))
    }

    /// `text` on a dark tab whose top left is (x, y).
    func label(_ text: String, x: Double, y: Double, size: Double = 14, colour: CGColor = Canvas.grey(1, 1)) {
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [kCTFontAttributeName as NSAttributedString.Key: font, kCTForegroundColorAttributeName as NSAttributedString.Key: colour]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let textWidth = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        let pad = (size * 0.4).rounded()
        let tab = CGRect(x: x, y: y, width: textWidth + 2 * pad, height: ascent + descent + pad)
        fill(tab, Canvas.grey(0, 170.0 / 255))
        context.textPosition = CGPoint(x: x + pad, y: Double(height) - tab.maxY + descent + pad / 2)
        CTLineDraw(line, context)
    }

    func image() throws -> LayerImage {
        guard let image = context.makeImage() else { throw LayerImage.Failure(description: "cannot finish a sheet") }
        return try LayerImage(cgImage: image)
    }
}
