import Foundation
import RimlightCore

/// `rimlight fit <set>/<slug>` or `rimlight fit --all --set <id>`: fits stored renders to the
/// tile shape again, from the generator's own image, without a render.
enum Fit {
    static let usage = """
        rimlight fit <set-id>/<slug> | rimlight fit --all --set <set-id>
        """

    static let help = """
        usage: \(usage)

        Fits a stored render to Apple's tile shape again, as `generate` does, from the image
        before the fit: raw.png when the icon has one, else icon.png, which then becomes raw.png.
        original.png stays as it is. No render is spent. Prints SHAPE and SAVED lines per icon, or SHAPE <set>/<slug> kept as
        rendered: <reason> when its tile cannot be found. An opaque icon is skipped with an OPAQUE
        line; `rimlight fix` makes it transparent first. --all fits every icon of the set that is
        not archived.
        """

    private struct Row: Encodable {
        var set, slug, image: String
        var shape: ShapeRow
    }

    static func run(_ raw: ArraySlice<String>) throws -> Int32 {
        let args = try Arguments(raw, flags: ["--all", "--help", "-h"], options: ["--set"])
        if args.flag("--help") || args.flag("-h") {
            Output.out(help)
            return 0
        }
        let store = try CLI.store(args)
        let json = args.flag("--json")

        let icons: [IconSnapshot]
        if args.flag("--all") {
            try args.expectPositionals(0, usage)
            let setID = try args.required("--set")
            _ = try store.readSet(setID)
            icons = try store.readIcons(in: setID).filter { !$0.icon.archived }
        } else {
            try args.expectPositionals(1, usage)
            guard args.value("--set") == nil else { throw UsageError("--set goes with --all; name one icon as <set-id>/<slug>") }
            let parts = args.positionals[0].split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2 else { throw UsageError("fit takes <set-id>/<slug>, not \"\(args.positionals[0])\"") }
            icons = [try store.readIcon(set: parts[0], slug: parts[1])]
        }

        let temp = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: store.stateRoot, create: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        // About 0.1 s of CPU an icon, so --all fits them on every core.
        let rows = parallelMap(icons.count) { index -> Row? in
            fit(icons[index], store: store, temp: temp, tag: "\(index)", json: json)
        }
        if json {
            struct Reply: Encodable { var fitted: [Row] }
            try Output.json(Reply(fitted: rows.compactMap { $0 }))
        }
        return rows.contains(where: { $0 == nil }) ? 1 : 0
    }

    /// One icon, fitted and stored in place. nil when it could not be read or written.
    private static func fit(_ snapshot: IconSnapshot, store: ProjectStore, temp: URL, tag: String, json: Bool) -> Row? {
        let id = snapshot.id
        let rawURL = store.iconRawImageURL(set: snapshot.setID, slug: snapshot.icon.slug)
        let source = FileStamp.of(rawURL) != nil ? rawURL : snapshot.imageURL
        // A copy, because the store moves it back in as raw.png.
        let copy = temp.appending(path: "raw-\(tag).png", directoryHint: .notDirectory)
        do { try FileManager.default.copyItem(at: source, to: copy) } catch {
            Output.err("ERROR: \(id): cannot copy \(source.path): \(error.localizedDescription)")
            return nil
        }
        guard let probe = ImageProbe.read(copy) else {
            Output.err("ERROR: \(id) has no readable PNG at \(source.path)")
            return nil
        }
        var row = Row(set: snapshot.setID, slug: snapshot.icon.slug, image: snapshot.imageURL.path, shape: ShapeRow(fitted: false))
        guard probe.isTransparent else {
            row.shape.note = "opaque"
            if !json { Output.out("OPAQUE \(snapshot.imageURL.path): nothing to fit; run `rimlight fix \(id)` first") }
            return row
        }
        let shaped = Shaper.run(copy, probe: probe, id: id, workDir: temp, tag: tag, json: json)
        row.shape = shaped.row
        guard let raw = shaped.raw else { return row }
        do {
            let saved = try store.replaceImage(
                set: snapshot.setID, slug: snapshot.icon.slug, image: shaped.image, raw: raw,
                imageInfo: shaped.probe.imageInfo, stamp: snapshot.stamp)
            let info = saved.icon.image
            if !json { Output.out("SAVED \(saved.imageURL.path) \(info.width)x\(info.height) alpha=\(info.alpha ? "yes" : "no")") }
            return row
        } catch {
            Output.err("ERROR: \(id): \(error)")
            return nil
        }
    }
}
