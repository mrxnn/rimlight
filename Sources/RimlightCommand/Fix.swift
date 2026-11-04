import Foundation
import RimlightCore
import Synchronization

/// The automatic transparency fix, shared by `generate` and `fix`.
struct Fixer: Sendable {
    var generator: any ImageGenerator
    /// Overrides for every fix render; nil keeps the request's own.
    var model: String?
    var effort: String?
    var timeout: TimeInterval?
    var attempts: Int
    /// Fix renders land in subfolders of this, on the project's volume.
    var workDir: URL
    /// --json: no FIX lines on stdout.
    var json: Bool

    /// Fixes `image` when its pixels are opaque, printing `FIX <attempt> <kind> <seconds>s <id>
    /// alpha=…` as each attempt ends. `original` is the request that made `image`, for the
    /// re-roll; nil skips it. `tag` keeps parallel fixes' files apart.
    func run(
        _ image: URL, probe: ImageProbe, original: ImageRequest?, id: String, tag: String
    ) -> TransparencyFix.Outcome {
        let outcome = TransparencyFix.run(
            image, probe: probe, original: original, attempts: attempts,
            cutout: workDir.appending(path: "cutout-\(tag).png", directoryHint: .notDirectory),
            paid: drawsTransparency(original),
            render: { request, attempt in
                var request = request
                if let model { request.model = model }
                if let effort { request.effort = effort }
                if let timeout { request.timeout = timeout }
                request.outputDir = workDir.appending(path: "fix-\(tag)-\(attempt)", directoryHint: .isDirectory)
                let result = try generator.run(request)
                return .init(image: result.images[0], model: result.model)
            },
            onAttempt: { attempt in
                let kind = Self.label(attempt.kind)
                if let error = attempt.error { Output.err("ERROR: fix \(attempt.number) (\(kind)) of \(id): \(error)") }
                if !json {
                    let seconds = String(format: "%.0f", attempt.seconds)
                    Output.out("FIX \(attempt.number) \(kind) \(seconds)s \(id) alpha=\(attempt.isTransparent ? "yes" : "no")")
                }
            })
        if outcome.cutout, !json { Output.out(cutoutLine(id: id, paidAttempts: outcome.paidAttempts)) }
        return outcome
    }

    /// A copy of the render the fix started from, for the store to move in as original.png.
    /// A copy, because in `fix` that render is the stored icon.png itself. nil when no fix
    /// changed the render, or, with a NOTE, when it cannot be copied.
    func keepOriginal(_ outcome: TransparencyFix.Outcome, id: String, tag: String) -> URL? {
        guard let source = outcome.source else { return nil }
        let copy = workDir.appending(path: "original-\(tag).png", directoryHint: .notDirectory)
        do {
            try FileManager.default.copyItem(at: source, to: copy)
            return copy
        } catch {
            Output.err("NOTE: \(id) is stored without original.png: \(error.localizedDescription)")
            return nil
        }
    }

    /// `CUTOUT <id>: …`, which the skill has the agent tell the person: the background was cut
    /// out on the Mac, after the paid fixes failed or because the model can't draw transparency.
    func cutoutLine(id: String, paidAttempts: Int) -> String {
        let model = model ?? "the image model"
        guard paidAttempts > 0 else {
            return "CUTOUT \(id): \(model) can't draw on transparency, so Rimlight cut the background out on this Mac"
        }
        let tries = paidAttempts == 1 ? "1 fix render" : "\(paidAttempts) fix renders"
        return "CUTOUT \(id): \(model) still painted a background after \(tries), so Rimlight cut it out on this Mac; "
            + "fine edges may be less clean than the model's own transparency"
    }

    /// Whether the model the fixes would render with can draw on transparency at all; when it
    /// can't, a paid edit or re-roll comes back painted too, so none is tried.
    func drawsTransparency(_ original: ImageRequest?) -> Bool {
        generator.drawsTransparency(model: model ?? original?.model)
    }

    /// The NOTE for a model that can't draw on transparency, printed once per command.
    func paidFixNote() -> String? {
        guard !drawsTransparency(nil) else { return nil }
        return "NOTE: \(model ?? "this model") can't draw on transparency, so an opaque render gets only the free "
            + "cutout on this Mac, no paid fix"
    }

    /// `edit`, `reroll` or `cutout`, as FIX lines and --json name an attempt.
    static func label(_ kind: FixAttempt.Kind) -> String {
        switch kind {
        case .transparencyEdit: "edit"
        case .reroll: "reroll"
        case .cutout: "cutout"
        }
    }

    /// The exit status when the image model refused a render for a limit.
    static let limitStatus: Int32 = 3

    /// `LIMIT <message>`, or the limit as JSON, for the end of a command that met it.
    static func limitLine(_ limit: RenderLimit) -> String { "LIMIT " + limit.message() }

    /// The line under an icon left opaque because the image model refused its fix for a limit.
    static func limitedLine(path: String) -> String {
        "OPAQUE \(path): not fixed, the image model refuses renders; run `rimlight fix` on it once the limit lifts"
    }

    /// The line under an icon that is still opaque after `tried` fix attempts.
    static func opaqueLine(path: String, id: String, tried: Int) -> String {
        guard tried > 0 else { return "OPAQUE \(path): not fixed (no fix attempts); run `rimlight fix \(id)`" }
        let tries = tried == 1 ? "1 fix attempt" : "\(tried) fix attempts"
        return "OPAQUE \(path): still opaque after \(tries); run `rimlight fix \(id)` once more or regenerate with a changed prompt"
    }

    /// `--fix-attempts` / `--attempts`: a whole number from 0, default 3.
    static func attempts(_ args: Arguments, _ name: String) throws -> Int {
        let n = try args.int(name) ?? TransparencyFix.defaultAttempts
        guard n >= 0 else { throw UsageError("\(name) must be 0 or more") }
        return n
    }
}

/// One fix attempt in --json output.
struct FixRow: Encodable {
    var attempt: Int
    var kind: String
    var seconds: Double
    var alpha: Bool
    var error: String?

    init(_ a: TransparencyFix.Attempt) {
        attempt = a.number
        kind = Fixer.label(a.kind)
        seconds = (a.seconds * 10).rounded() / 10
        alpha = a.isTransparent
        error = a.error
    }
}

/// `body` for every index at once, each on its own thread, with the results in index order.
/// A render is a blocking wait, a minute on Codex, so fixes of several renders overlap.
func parallelMap<T: Sendable>(_ count: Int, _ body: @Sendable (Int) -> T) -> [T] {
    guard count > 1 else { return (0..<count).map(body) }
    let results = Mutex<[T?]>(Array(repeating: nil, count: count))
    DispatchQueue.concurrentPerform(iterations: count) { index in
        let value = body(index)
        results.withLock { $0[index] = value }
    }
    return results.withLock { $0.compactMap { $0 } }
}

/// `rimlight fix <set>/<slug>` or `rimlight fix --all --set <id>`: the transparency fix of
/// stored icons, in place. An icon whose pixels are already transparent costs no render.
enum Fix {
    static let usage = """
        rimlight fix <set-id>/<slug> [--attempts N] | rimlight fix --all --set <set-id> [--attempts N]
        """

    static let help = """
        usage: \(usage)

        Judges each icon by its pixels first. A stored alpha that disagrees with them is corrected
        without a render and printed as CORRECTED <set>/<slug> alpha=yes|no. An opaque icon is then
        fixed, stopping at the first transparent result: up to N renders (default 3), an edit of
        its own file with the transparency fix prompt, a fresh render of its own prompt and refs,
        and an edit of that render, then, when it is still opaque, a free cutout of its painted
        ground on this Mac, with a CUTOUT line saying so. A model that can't draw on transparency
        gets only the cutout. A cutout that wins
        keeps the icon as it was, prompt and model; an edit that wins keeps the concept prompt and
        adds the fix prompt to the icon's fixes; a fresh render that wins replaces the render. Every attempt is
        recorded in the icon's fixAttempts, and the opaque render an edit or the cutout started
        from is kept as original.png. An icon that is already transparent costs no render.
        The fresh render of an icon without a parent gets the tile template, and the result that
        wins is fitted to the tile shape as `generate` does, with a SHAPE line.
        --all fixes every opaque icon of the set that is not archived, all at once. Also takes
        --effort and --timeout SECONDS.
        \(Renderer.help)
        When the image model refuses every render, for a plan's image limit or an account out of
        credit, no more attempts are spent: the icons stay as they are, a LIMIT line says why and,
        when the provider says, when it lifts, and the exit status is 3.
        """

    private struct Row: Encodable {
        var set, slug, image: String
        var alpha, fixed: Bool
        var fixes: [FixRow]
        var shape: ShapeRow?
        /// Set when the image model refused this icon's fix for a limit.
        var limit: RenderLimit?
    }

    private struct Corrected: Encodable {
        var set, slug: String
        var alpha: Bool
    }

    private struct Pending: Sendable {
        var snapshot: IconSnapshot
        var probe: ImageProbe
        /// The icon's own request for the re-roll, nil when it cannot be rebuilt.
        var original: ImageRequest?
    }

    static func run(_ raw: ArraySlice<String>) throws -> Int32 {
        let args = try Arguments(
            raw, flags: ["--all", "--help", "-h"],
            options: Set(["--set", "--attempts", "--effort", "--timeout"]).union(Renderer.options))
        if args.flag("--help") || args.flag("-h") {
            Output.out(help)
            return 0
        }
        let store = try CLI.store(args)
        let attempts = try Fixer.attempts(args, "--attempts")
        let timeout = try args.int("--timeout").map(TimeInterval.init)
        let imageSettings = try Renderer.settings(args)
        let json = args.flag("--json")

        // The icons to look at.
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
            guard parts.count == 2 else { throw UsageError("fix takes <set-id>/<slug>, not \"\(args.positionals[0])\"") }
            icons = [try store.readIcon(set: parts[0], slug: parts[1])]
        }

        // Judge every render by its pixels, and correct any record that disagrees: no render.
        var pending: [Pending] = []
        var corrected: [Corrected] = []
        var failed = false
        for var snapshot in icons {
            guard let probe = ImageProbe.read(snapshot.imageURL) else {
                Output.err("ERROR: \(snapshot.id) has no readable PNG at \(snapshot.imageURL.path)")
                failed = true
                continue
            }
            if probe.isTransparent != snapshot.icon.image.alpha {
                do {
                    snapshot = try store.setAlpha(set: snapshot.setID, slug: snapshot.icon.slug, probe.isTransparent)
                } catch {
                    Output.err("ERROR: \(snapshot.id): \(error)")
                    failed = true
                    continue
                }
                corrected.append(Corrected(set: snapshot.setID, slug: snapshot.icon.slug, alpha: probe.isTransparent))
                if !json { Output.out("CORRECTED \(snapshot.id) alpha=\(probe.isTransparent ? "yes" : "no")") }
            }
            if probe.isTransparent {
                if !json, !args.flag("--all") { Output.out("TRANSPARENT \(snapshot.imageURL.path): nothing to fix, no render spent") }
                continue
            }
            var original: ImageRequest?
            if attempts >= 2 {
                switch rerollRequest(snapshot.icon, store: store, model: imageSettings.model(for: imageSettings.provider), effort: args.value("--effort")) {
                case .success(var request):
                    if let timeout { request.timeout = timeout }
                    original = request
                case .failure(let reason):
                    Output.err("NOTE: \(snapshot.id) cannot be re-rolled (\(reason.message)); the re-roll attempt is skipped")
                }
            }
            pending.append(Pending(snapshot: snapshot, probe: probe, original: original))
        }
        guard !pending.isEmpty else {
            if json {
                struct Reply: Encodable { var corrected: [Corrected]; var fixed: [Row] }
                try Output.json(Reply(corrected: corrected, fixed: []))
            } else if args.flag("--all"), !failed {
                let what = icons.count == 1 ? "the 1 icon" : "all \(icons.count) icons"
                Output.out("TRANSPARENT \(what) of \(args.value("--set") ?? ""): nothing to fix, no render spent")
            }
            return failed ? 1 : 0
        }

        let temp = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: store.stateRoot, create: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let renderer = try Renderer.make(imageSettings)
        let fixer = Fixer(
            generator: renderer.generator, model: renderer.model,
            effort: args.value("--effort"), timeout: timeout, attempts: attempts, workDir: temp, json: json)
        if let note = fixer.paidFixNote() { Output.err(note) }

        // A re-roll of a fresh render gets the template, as the render did.
        let template = Shaper.template(in: temp)
        let work = pending.map { item in
            var item = item
            if item.snapshot.icon.parent == nil, let original = item.original {
                item.original = Shaper.attach(template, to: original, id: item.snapshot.id)
            }
            return item
        }
        let jobs = Jobs.begin(
            store, images: work.map { ($0.snapshot.setID, $0.snapshot.icon.slug, $0.snapshot.icon.title) }, mode: .fix)
        defer { jobs.forEach(Jobs.end) }
        let rows = parallelMap(work.count) { index -> Row? in
            defer { Jobs.end(jobs[index]) }
            return fix(work[index], fixer: fixer, store: store, tag: "\(index)")
        }
        if rows.contains(where: { $0 == nil }) { failed = true }
        let limit = rows.lazy.compactMap { $0?.limit }.first

        if json {
            struct Reply: Encodable { var corrected: [Corrected]; var fixed: [Row]; var limit: RenderLimit? }
            try Output.json(Reply(corrected: corrected, fixed: rows.compactMap { $0 }, limit: limit))
        } else {
            if args.flag("--all") {
                let done = rows.filter { $0?.alpha == true }.count
                Output.out("FIXED \(done) of \(work.count) opaque icon\(work.count == 1 ? "" : "s") in \(args.value("--set") ?? "")")
            }
            if let limit { Output.out(Fixer.limitLine(limit)) }
        }
        if limit != nil { return Fixer.limitStatus }
        return failed || rows.contains(where: { $0?.alpha != true }) ? 1 : 0
    }

    struct RerollUnavailable: Error {
        var message: String
    }

    /// The icon's own request, rebuilt for a re-roll: its prompt, and its refs resolved back to
    /// files (`{set, icon}` to that icon's `icon.png`, `{path}` to the path).
    static func rerollRequest(
        _ icon: Icon, store: ProjectStore, model: String?, effort: String?
    ) -> Result<ImageRequest, RerollUnavailable> {
        guard !icon.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.init(message: "the icon has no prompt"))
        }
        // An edit of its own file other than a transparency fix is not in the prompt; a re-roll would drop it.
        if icon.fixes?.contains(where: { $0 != TransparencyFix.prompt }) == true {
            return .failure(.init(message: "the render carries edits of its own file that a re-roll would drop"))
        }
        var files: [URL] = []
        for ref in icon.refs {
            let url: URL
            if let set = ref.set, let slug = ref.icon {
                url = store.iconImageURL(set: set, slug: slug)
            } else if let path = ref.path {
                url = URL(filePath: path, directoryHint: .notDirectory)
            } else {
                return .failure(.init(message: "a reference names no icon and no path"))
            }
            guard FileStamp.of(url) != nil else {
                return .failure(.init(message: "reference image not found: \(url.path)"))
            }
            files.append(url)
        }
        guard files.count <= ImageRequest.maxRefs else {
            return .failure(.init(message: "more than \(ImageRequest.maxRefs) reference images"))
        }
        return .success(ImageRequest(prompt: icon.prompt, refs: files, model: model, effort: effort))
    }

    /// One icon: fix, then replace it in place, or record the failed attempts. An edit that
    /// wins is stored as an edit of the icon's own file (concept prompt kept, fix prompt added
    /// to `fixes`); a re-roll that wins is a redo with the icon's own prompt and refs. nil when
    /// the icon could not be written.
    private static func fix(_ item: Pending, fixer: Fixer, store: ProjectStore, tag: String) -> Row? {
        let snapshot = item.snapshot
        let icon = snapshot.icon
        let id = snapshot.id
        let path = snapshot.imageURL.path
        let outcome = fixer.run(snapshot.imageURL, probe: item.probe, original: item.original, id: id, tag: tag)
        var row = Row(
            set: snapshot.setID, slug: icon.slug, image: path, alpha: false, fixed: false,
            fixes: outcome.attempts.map(FixRow.init))
        do {
            guard outcome.isFixed else {
                row.limit = outcome.limit
                // A refusal is not a failed try at the icon; only real attempts are recorded.
                let records = outcome.limit == nil ? outcome.records : outcome.attempts.filter { $0.error == nil }.map(\.record)
                if !records.isEmpty { try store.addFixAttempts(set: snapshot.setID, slug: icon.slug, records) }
                if !fixer.json {
                    Output.out(
                        outcome.limit == nil
                            ? Fixer.opaqueLine(path: path, id: id, tried: outcome.attempts.count) : Fixer.limitedLine(path: path))
                }
                return row
            }
            // A render replaced while the fix ran is newer than the fix; keep it.
            guard FileStamp.of(snapshot.imageURL) == snapshot.stamp else {
                Output.err("ERROR: \(id) changed while it was being fixed; the fix was not stored")
                return nil
            }
            let shaped = Shaper.run(
                outcome.image, probe: outcome.probe, id: id, workDir: fixer.workDir, tag: tag, json: fixer.json)
            row.shape = shaped.row
            let original = fixer.keepOriginal(outcome, id: id, tag: tag)
            let saved: IconSnapshot
            if outcome.cutout {
                // The same render with its ground cut away: its own prompt, refs and model.
                saved = try store.addIcon(
                    set: snapshot.setID, slug: icon.slug, title: icon.title, prompt: icon.prompt, parent: icon.parent,
                    refs: icon.refs, generator: icon.generator, by: icon.by, image: shaped.image, raw: shaped.raw, original: original,
                    imageInfo: shaped.probe.imageInfo, fixes: icon.fixes ?? [],
                    fixAttempts: (icon.fixAttempts ?? []) + outcome.records, replace: true)
            } else if outcome.rerolled, let model = outcome.fixModel {
                let generator = GeneratorInfo(tool: fixer.generator.tool, model: model)
                saved = try store.addIcon(
                    set: snapshot.setID, slug: icon.slug, title: icon.title, prompt: icon.prompt, parent: icon.parent,
                    refs: icon.refs, generator: generator, by: icon.by, image: shaped.image, raw: shaped.raw, original: original,
                    imageInfo: shaped.probe.imageInfo, fixes: outcome.fixes,
                    fixAttempts: (icon.fixAttempts ?? []) + outcome.records, replace: true)
            } else {
                let generator = GeneratorInfo(tool: fixer.generator.tool, model: outcome.fixModel ?? icon.generator?.model ?? "")
                saved = try store.addIcon(
                    set: snapshot.setID, slug: icon.slug, title: icon.title, prompt: TransparencyFix.prompt,
                    refs: [.icon(set: snapshot.setID, icon: icon.slug)], generator: generator, by: icon.by,
                    image: shaped.image, raw: shaped.raw, original: original, imageInfo: shaped.probe.imageInfo, fixAttempts: outcome.records,
                    replace: true)
            }
            row.alpha = true
            row.fixed = true
            if !fixer.json {
                Output.out("SAVED \(saved.imageURL.path) \(saved.icon.image.width)x\(saved.icon.image.height) alpha=yes")
            }
            return row
        } catch {
            Output.err("ERROR: \(id): \(error)")
            return nil
        }
    }
}
