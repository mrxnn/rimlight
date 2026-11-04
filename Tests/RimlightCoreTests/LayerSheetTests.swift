import Foundation
import Testing

@testable import RimlightCore

@Suite struct LayerSheetTests {
    private func near(_ p: SIMD4<Float>, _ q: SIMD4<Float>, _ tolerance: Float = 1.5 / 255) -> Bool {
        let d = p - q
        return (0..<4).allSatisfy { Swift.abs(d[$0]) <= tolerance }
    }

    @Test func aSheetLaysOutLabelledCells() throws {
        let red = LayerImage(side: 64, fill: SIMD4(1, 0, 0, 1))
        let blue = LayerImage(width: 64, height: 32, fill: SIMD4(0, 0, 1, 1))
        let clear = LayerImage(side: 64)
        let sheet = try LayerImage.sheet(rows: [[("red", red), ("blue", blue), ("layer", clear.onCheckerboard())], [("red", red)]], cell: 100)
        #expect(sheet.width == 300 && sheet.height == 200)
        #expect(near(sheet[50, 60], SIMD4(1, 0, 0, 1)))
        // The wide image is centred in its cell, grey above and below it.
        #expect(near(sheet[150, 50], SIMD4(0, 0, 1, 1)))
        #expect(near(sheet[150, 90], SIMD4(128 / 255, 128 / 255, 128 / 255, 1)))
        // The second row's missing cells are mid grey; every pixel is opaque.
        #expect(near(sheet[250, 150], SIMD4(128 / 255, 128 / 255, 128 / 255, 1)))
        #expect(!sheet.hasAlpha)
        // The label's tab darkens the cell's top-left corner.
        #expect(sheet[2, 2].x < 0.5)
    }

    @Test func theGridMarksTilePixels() throws {
        let tile = LayerImage(side: 1024, fill: SIMD4(0.2, 0.4, 0.6, 1))
        let grid = try tile.gridOverlay()
        #expect(grid.width == 1024 && grid.height == 1024)
        #expect(near(grid[40, 600], tile[40, 600]))
        #expect(!near(grid[32, 600], tile[32, 600]))
        // A labelled line is yellow; a plain one is a faint white.
        #expect(grid[256, 600].x > grid[256, 600].z + 0.3)
        #expect(grid[288, 600].x < 0.6 && grid[288, 600].x > tile[288, 600].x)

        // A 128 px box is blown up 8 times: tile x 128 lands at (128 − 100) · 8.
        let zoomed = try tile.gridOverlay(step: 16, labelEvery: 64, box: LayerBox(x0: 100, y0: 100, x1: 228, y1: 228))
        #expect(zoomed.width == 1024 && zoomed.height == 1024)
        #expect(zoomed[224, 600].x > zoomed[224, 600].z + 0.3)
        #expect(near(zoomed[230, 600], tile[0, 0]))
    }

    @Test func aZoomLaysOneBoxSideBySide() throws {
        var a = LayerImage(side: 100, fill: SIMD4(0, 1, 0, 1))
        a[50, 50] = SIMD4(1, 1, 1, 1)
        let b = LayerImage(side: 200, fill: SIMD4(1, 0, 1, 1))
        let zoom = try LayerImage.zoom([("a", a), ("b", b)], box: LayerBox(x0: 40, y0: 40, x1: 80, y1: 60))
        // 40 x 20 px at 9x is 360 x 180, two of them 8 px apart.
        #expect(zoom.width == 728 && zoom.height == 180)
        // Pixel (50, 50) is the block from (10 · 9, 10 · 9): nearest, so its edge stays sharp.
        #expect(near(zoom[90, 90], SIMD4(1, 1, 1, 1)) && near(zoom[98, 98], SIMD4(1, 1, 1, 1)))
        #expect(near(zoom[99, 99], SIMD4(0, 1, 0, 1)))
        #expect(near(zoom[368 + 200, 100], SIMD4(1, 0, 1, 1)))
        #expect(near(zoom[362, 100], SIMD4(128 / 255, 128 / 255, 128 / 255, 1)))
        // A 100 px box needing 150 is doubled.
        #expect(try LayerImage.zoom([("a", a)], box: LayerBox(x0: 0, y0: 0, x1: 100, y1: 50), minSide: 150).width == 200)
    }

    /// The crops cover the whole outline, none where it is hidden, and each sheet holds them 1:1.
    @Test func outlineCropsCoverTheOutline() throws {
        let n = LayerEdgeTests.side
        let mask = LayerEdgeTests.layer().mask
        let boxes = LayerImage.outlineBoxes(mask, hidden: [Bool](repeating: false, count: n * n), side: n, cell: 64)
        for y in 0..<n {
            for x in 0..<n where mask[y * n + x] && !mask[y * n + x - 1] {
                #expect(boxes.contains { $0.x0 <= x && x < $0.x1 && $0.y0 <= y && y < $0.y1 }, "\(x), \(y)")
            }
        }
        // the middle, far from the outline, is in no crop
        #expect(!boxes.contains { $0.x0 <= 128 && 128 < $0.x1 && $0.y0 <= 128 && 128 < $0.y1 })
        // the lower half hidden by a layer above: no crop holds only it
        let hidden = (0..<(n * n)).map { $0 / n >= 140 }
        #expect(LayerImage.outlineBoxes(mask, hidden: hidden, side: n, cell: 64).allSatisfy { $0.y0 < 140 })

        let pick = LayerEdgeTests.picture(cover: LayerEdgeTests.smooth)
        let sheets = try LayerImage.cropSheets([("pick", pick), ("Default", pick)], boxes: boxes, columns: 2, rows: 2)
        #expect(sheets.count == (boxes.count + 3) / 4)
        // a crop is drawn pixel for pixel: the first box's top left is the pick's, under its 20 px strip
        let first = boxes[0]
        let p = sheets[0][0, 20], q = pick[first.x0, first.y0]
        #expect(abs(p.x - q.x) < 0.01 && abs(p.y - q.y) < 0.01)
    }
}
