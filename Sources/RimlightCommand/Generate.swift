import Foundation
import RimlightCore
import Synchronization

/// `rimlight generate`: checks everything it can before spending a generation, runs one render
/// through the image model, fixes any image whose pixels are opaque, then stores each through `ProjectStore.addIcon`.
enum Generate {
    static let usage = """
        rimlight generate --set <set-id> --slug <slug> --title "..." (--prompt-file FILE | --prompt-file - | --prompt "...") \
        [--ref IMAGE]... [--parent <set-id>/<slug>] [--count N] [--force] [--fix-attempts N] [--by NAME] [--provider P] [--model M] [--dry-run]
        """

    static let help = """
        usage: \(usage)

        --prompt-file - reads the prompt from stdin, e.g. a quoted heredoc:
          rimlight generate --set set-001 --slug olive-device --title "Olive device" --prompt-file - <<'PROMPT'
          Square image. One macOS app icon ...
          PROMPT
        --dry-run checks every argument and reads the prompt, prints its length and exits 0
        without rendering.
        Every image is checked by its pixels. An opaque one is fixed, unless --fix-attempts is 0,
        stopping at the first transparent result: up to --fix-attempts N renders (default 3), an
        edit of it with the transparency fix prompt, a fresh render of the same prompt and refs,
        and an edit of that render, then, when it is still opaque, a free cutout of its painted
        ground on this Mac. A model that can't draw on transparency gets only the cutout. Each
        prints FIX <n> edit|reroll|cutout <seconds>s <set>/<slug> alpha=yes|no, and a cutout that
        worked a CUTOUT line saying why it was needed.
        One still opaque after that is stored with alpha=no and an OPAQUE line. When the image
        model refuses every render, for a plan's image limit or an account out of credit, nothing
        more is tried: a LIMIT line says why and, when the provider says, when it lifts, and the
        exit status is 3.
        Without --parent the render also gets Apple's tile shape as a grey template image after
        the --ref images, and the prompt gets a line saying which image it is. Every transparent
        image is then fitted to that shape: its drawn tile is scaled to 1024 px, centred in the
        1254 px frame and cut with the exact mask, and the image before the fit is kept as
        raw.png beside icon.png. When a fix made the image, the model's opaque render is kept as
        original.png too. Each prints SHAPE <set>/<slug> drawn=<w>x<h> tile=1024
        overscan=<px>, or SHAPE <set>/<slug> kept as rendered: <reason>.
        \(Renderer.help)
        """

    static func run(_ raw: ArraySlice<String>) throws -> Int32 {
        let args = try Arguments(
            raw, flags: ["--force", "--dry-run", "--help", "-h"],
            options: Set([
                "--set", "--slug", "--title", "--prompt", "--prompt-file", "--ref", "--parent", "--count", "--by",
                "--effort", "--timeout", "--fix-attempts",
            ]).union(Renderer.options))
        if args.flag("--help") || args.flag("-h") {
            Output.out(help)
            return 0
        }
        try args.expectPositionals(0, usage)
        let store = try CLI.store(args)
        let force = args.flag("--force")

        // The set and the slugs.
        let setID = try args.required("--set")
        _ = try store.readSet(setID)
        let baseSlug = try args.required("--slug")
        let title = try args.required("--title").trimmingCharacters(in: .whitespacesAndNewlines)
        let count = try args.int("--count") ?? 1
        guard count >= 1 else { throw UsageError("--count must be at least 1") }
        let fixAttempts = try Fixer.attempts(args, "--fix-attempts")
        let slugs = (0..<count).map { ImageNames.variantSlug(baseSlug, index: $0, count: count) }
        for slug in slugs { try Slug.validate(slug) }
        let clashes = slugs.filter {
            FileManager.default.fileExists(atPath: store.iconRecordURL(set: setID, slug: $0).path)
        }
        if !clashes.isEmpty, !force {
            throw StoreError.alreadyExists(
                "icon exists, pick a new slug or pass --force:\n  " + clashes.map { "\(setID)/\($0)" }.joined(separator: "\n  "))
        }

        // The prompt.
        let prompt: String
        switch (args.value("--prompt"), args.value("--prompt-file")) {
        case (let text?, nil):
            prompt = text
        case (nil, "-"):
            prompt = try readStdin()
        case (nil, let file?):
            let url = CLI.absolute(file)
            do { prompt = try String(contentsOf: url, encoding: .utf8) } catch {
                throw StoreError.notFound("Cannot read the prompt file \(url.path): \(error.localizedDescription)")
            }
        case (nil, nil): throw UsageError("give the prompt with --prompt-file FILE, --prompt-file - (stdin) or --prompt \"...\"")
        case (_?, _?): throw UsageError("give --prompt or --prompt-file, not both")
        }
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UsageError("the prompt is empty")
        }

        // The parent and the refs.
        var parent: IconParent?
        if let raw = args.value("--parent") {
            let parts = raw.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2 else { throw UsageError("--parent takes <set-id>/<slug>, not \"\(raw)\"") }
            _ = try store.readIcon(set: parts[0], slug: parts[1])
            parent = IconParent(set: parts[0], icon: parts[1])
        }
        let refs = try args.values("--ref").map { try resolveRef($0, store: store) }
        guard refs.count <= ImageRequest.maxRefs else {
            throw StoreError.invalidArgument("a render takes at most \(ImageRequest.maxRefs) reference images")
        }

        if args.flag("--dry-run") {
            if args.flag("--json") {
                struct Reply: Encodable { var set: String; var slugs: [String]; var promptLength: Int; var refs: Int }
                try Output.json(Reply(set: setID, slugs: slugs, promptLength: prompt.count, refs: refs.count))
            } else {
                Output.out("DRY RUN \(slugs.map { "\(setID)/\($0)" }.joined(separator: " ")) prompt=\(prompt.count) characters refs=\(refs.count)")
            }
            return 0
        }

        // A job marker per image until it lands, so the app shows the render and keeps alive
        // the agent process it runs under.
        let renders = slugs.indices.map { (setID, slugs[$0], ImageNames.variantTitle(title, index: $0, count: count)) }
        let jobs = Jobs.begin(store, images: renders, mode: .generate)
        defer { jobs.forEach(Jobs.end) }

        // The render, into a temp folder on the project's volume so the store's move is a rename.
        let temp = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: store.stateRoot, create: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let timeout = try args.int("--timeout").map(TimeInterval.init)
        let renderer = try Renderer.make(args)
        var request = ImageRequest(
            prompt: prompt, refs: refs.map(\.url), count: count, model: renderer.model,
            effort: args.value("--effort"), outputDir: temp.appending(path: "render", directoryHint: .isDirectory))
        if let timeout { request.timeout = timeout }
        // An edit's parent already carries the shape; a fresh render gets the template.
        if parent == nil {
            request = Shaper.attach(Shaper.template(in: temp), to: request, id: "\(setID)/\(baseSlug)")
        }
        let generator = renderer.generator
        let result: ImageResult
        do { result = try generator.run(request) } catch ImageFailure.limit(let limit) {
            if args.flag("--json") {
                struct Reply: Encodable { var saved: [Saved]; var limit: RenderLimit }
                try Output.json(Reply(saved: [], limit: limit))
            } else {
                Output.out(Fixer.limitLine(limit))
            }
            return Fixer.limitStatus
        } catch {
            Output.err("ERROR: \(error)")
            return 1
        }

        // Fix what came back opaque, every image at once, then store each as it is ready.
        if result.images.count > count {
            Output.err("WARNING: the image model made \(result.images.count) images for \(count) asked; kept the first \(count)")
        }
        let json = args.flag("--json")
        // The fixes use the model that just worked, so a rejected one is not retried again.
        let fixer = Fixer(
            generator: generator, model: result.model, effort: args.value("--effort"), timeout: timeout,
            attempts: fixAttempts, workDir: temp, json: json)
        if fixAttempts > 0, let note = fixer.paidFixNote(),
            result.images.prefix(count).contains(where: { ImageProbe.read($0)?.isTransparent == false })
        {
            Output.err(note)
        }
        // A re-roll is one more image of the same request.
        var original = request
        original.count = 1
        original.model = result.model
        original.outputDir = nil
        let reroll = original
        let images = Array(result.images.prefix(count))
        let refRecords = refs.map(\.ref)
        let lineage = parent
        let by = args.value("--by") ?? Jobs.host?.agent.by ?? ProcessTree.Agent.claude.by
        let limited = Mutex<RenderLimit?>(nil)
        let saved = parallelMap(images.count) { index -> Saved? in
            defer { Jobs.end(jobs[index]) }
            let slug = slugs[index]
            let id = "\(setID)/\(slug)"
            guard let probe = ImageProbe.read(images[index]) else {
                Output.err("ERROR: the image model returned a file that is not a readable PNG for \(id): \(images[index].lastPathComponent)")
                return nil
            }
            let outcome = fixer.run(images[index], probe: probe, original: reroll, id: id, tag: "\(index)")
            if let limit = outcome.limit { limited.withLock { $0 = $0 ?? limit } }
            // A refusal is not a failed try at the icon; only real attempts are recorded.
            let records = outcome.limit == nil ? outcome.records : outcome.attempts.filter { $0.error == nil }.map(\.record)
            let shaped = Shaper.run(outcome.image, probe: outcome.probe, id: id, workDir: temp, tag: "\(index)", json: json)
            let original = fixer.keepOriginal(outcome, id: id, tag: "\(index)")
            let snapshot: IconSnapshot
            do {
                snapshot = try store.addIcon(
                    set: setID, slug: slug, title: ImageNames.variantTitle(title, index: index, count: count),
                    prompt: prompt, parent: lineage, refs: refRecords,
                    generator: GeneratorInfo(tool: generator.tool, model: outcome.fixModel ?? result.model),
                    by: by, image: shaped.image, raw: shaped.raw, original: original, imageInfo: shaped.probe.imageInfo,
                    fixes: outcome.fixes, fixAttempts: records, replace: force)
            } catch {
                Output.err("ERROR: \(error)")
                return nil
            }
            let path = snapshot.imageURL.path
            let info = snapshot.icon.image
            if !json {
                Output.out("SAVED \(path) \(info.width)x\(info.height) alpha=\(info.alpha ? "yes" : "no")")
                if !info.alpha {
                    Output.out(
                        outcome.limit == nil
                            ? Fixer.opaqueLine(path: path, id: id, tried: outcome.attempts.count) : Fixer.limitedLine(path: path))
                }
            }
            return Saved(
                set: setID, slug: slug, title: snapshot.icon.title, image: path, width: info.width,
                height: info.height, alpha: info.alpha, fixes: outcome.attempts.map(FixRow.init), shape: shaped.row)
        }.compactMap { $0 }
        if result.images.count < count {
            Output.err("WARNING: asked for \(count) images, the image model made \(result.images.count)")
        }

        if args.flag("--json") {
            struct Codex: Encodable {
                var seconds: Double
                var input, cached, output: Int?
                var model: String
                var thread: String?
            }
            struct Render: Encodable {
                var tool, model: String
                var seconds: Double
                var input, cached, output: Int?
                var cost: Double?
            }
            struct Reply: Encodable { var saved: [Saved]; var render: Render; var codex: Codex?; var limit: RenderLimit? }
            let u = result.usage
            let tenths = (result.seconds * 10).rounded() / 10
            // `codex` stays for the skills and scripts that read it before providers.
            let codex = generator is CodexImageGen
                ? Codex(seconds: tenths, input: u?.input, cached: u?.cached, output: u?.output, model: result.model, thread: result.threadID)
                : nil
            try Output.json(Reply(
                saved: saved,
                render: Render(
                    tool: generator.tool, model: result.model, seconds: tenths, input: u?.input, cached: u?.cached,
                    output: u?.output, cost: result.cost),
                codex: codex, limit: limited.withLock { $0 }))
        } else {
            Output.out(Self.renderLine(result, tool: generator.tool, codex: generator is CodexImageGen))
            if let limit = limited.withLock({ $0 }) { Output.out(Fixer.limitLine(limit)) }
        }
        if limited.withLock({ $0 }) != nil { return Fixer.limitStatus }
        return saved.isEmpty ? 1 : 0
    }

    /// `CODEX <s>s input=… cached=… output=…` for Codex, as before providers;
    /// `RENDER <tool> <model> <s>s …` with any usage and cost for the others.
    static func renderLine(_ result: ImageResult, tool: String, codex: Bool) -> String {
        var line = codex ? "CODEX " : "RENDER \(tool) \(result.model) "
        line += String(format: "%.0fs", result.seconds)
        if let u = result.usage { line += " input=\(u.input) cached=\(u.cached) output=\(u.output)" }
        if let cost = result.cost { line += String(format: " cost=$%.4f", cost) }
        return line
    }

    struct Saved: Encodable {
        var set, slug, title, image: String
        var width, height: Int
        var alpha: Bool
        /// The transparency fix attempts, none when the render came back transparent.
        var fixes: [FixRow]
        var shape: ShapeRow
    }

    /// All of stdin as UTF-8, for `--prompt-file -`. A terminal is refused rather than waited on.
    static func readStdin() throws -> String {
        guard isatty(STDIN_FILENO) == 0 else {
            throw UsageError("--prompt-file - reads the prompt from stdin; pass it with a quoted heredoc (<<'PROMPT')")
        }
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else {
            throw StoreError.invalidArgument("the prompt on stdin is not UTF-8")
        }
        return text
    }

    /// A ref as a real file path, and how `icon.json` records it: `{set, icon}` when it is a
    /// render in this project's `.rimlight/sets/<set>/<slug>/icon.png`, else `{path}`.
    static func resolveRef(_ raw: String, store: ProjectStore) throws -> (url: URL, ref: IconReference) {
        let given = CLI.absolute(raw)
        guard let real = realPath(given.path) else {
            throw StoreError.notFound("reference image not found: \(given.path)")
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: real, isDirectory: &isDir), !isDir.boolValue else {
            throw StoreError.notFound("reference image is not a file: \(real)")
        }
        let url = URL(filePath: real, directoryHint: .notDirectory)
        if let sets = realPath(store.setsDir.path), real.hasPrefix(sets + "/") {
            let parts = real.dropFirst(sets.count + 1).split(separator: "/").map(String.init)
            if parts.count == 3, parts[2] == ProjectStore.imageName, SetID.isValid(parts[0]), Slug.isValid(parts[1]) {
                return (url, .icon(set: parts[0], icon: parts[1]))
            }
        }
        return (url, .file(real))
    }

    private static func realPath(_ path: String) -> String? {
        guard let p = realpath(path, nil) else { return nil }
        defer { free(p) }
        return String(cString: p)
    }
}
