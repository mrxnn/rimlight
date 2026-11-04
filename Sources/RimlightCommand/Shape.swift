import Foundation
import RimlightCore

/// The tile shape on a render's way into the store, shared by `generate` and `fix`: the
/// template for a fresh render, and the fit of every transparent result.
enum Shaper {
    /// The template in `dir`, written for this run. nil, with a NOTE, when it cannot be written.
    static func template(in dir: URL) -> URL? {
        let url = dir.appending(path: "tile-template.png", directoryHint: .notDirectory)
        do {
            try TileShape.writeTemplate(to: url)
            return url
        } catch {
            Output.err("NOTE: no tile template for this run (\(error)); renders are still fitted to the shape")
            return nil
        }
    }

    /// `request` with the template attached, or as it was, with a NOTE, when its refs are full.
    static func attach(_ template: URL?, to request: ImageRequest, id: String) -> ImageRequest {
        guard let template else { return request }
        guard let attached = TileShape.withTemplate(request, template: template) else {
            Output.err("NOTE: \(id) has \(ImageRequest.maxRefs) refs, so it renders without the tile template")
            return request
        }
        return attached
    }

    struct Shaped {
        /// What to store: the fitted render, or the render itself when it was not fitted.
        var image: URL
        var probe: ImageProbe
        /// The image before the fit, kept as raw.png; nil when it was not fitted.
        var raw: URL?
        var row: ShapeRow
    }

    /// Fits a transparent render to the tile shape, printing `SHAPE <id> drawn=<w>x<h>
    /// tile=<n> overscan=<px>`, or `SHAPE <id> kept as rendered: <reason>` when it cannot. An
    /// opaque render has no alpha to find its tile by, so it is stored as it is, with no line.
    static func run(_ image: URL, probe: ImageProbe, id: String, workDir: URL, tag: String, json: Bool) -> Shaped {
        guard probe.isTransparent else {
            return Shaped(image: image, probe: probe, raw: nil, row: ShapeRow(fitted: false, note: "opaque"))
        }
        let fitted = workDir.appending(path: "shape-\(tag).png", directoryHint: .notDirectory)
        do {
            let fit = try TileShape.conform(image, to: fitted)
            guard let fittedProbe = ImageProbe.read(fitted), fittedProbe.isTransparent else {
                throw TileShape.Unfit(description: "the fitted render did not read back as transparent")
            }
            let overscan = String(format: "%g", (fit.overscan * 10).rounded() / 10)
            if !json {
                Output.out("SHAPE \(id) drawn=\(fit.drawnWidth)x\(fit.drawnHeight) tile=\(fit.tile) overscan=\(overscan)")
            }
            return Shaped(
                image: fitted, probe: fittedProbe, raw: image,
                row: ShapeRow(
                    fitted: true, drawnWidth: fit.drawnWidth, drawnHeight: fit.drawnHeight, tile: fit.tile,
                    overscan: (fit.overscan * 10).rounded() / 10))
        } catch {
            if !json { Output.out("SHAPE \(id) kept as rendered: \(error)") }
            return Shaped(image: image, probe: probe, raw: nil, row: ShapeRow(fitted: false, note: "\(error)"))
        }
    }
}

/// The fit of one render in --json output.
struct ShapeRow: Encodable {
    var fitted: Bool
    var drawnWidth: Int?
    var drawnHeight: Int?
    var tile: Int?
    /// How far past the mask the drawn tile was scaled on every side, in pixels.
    var overscan: Double?
    /// Why it was not fitted.
    var note: String?
}
