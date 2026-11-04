import Foundation
import RimlightCore

/// `rimlight build`: a picked render into an Icon Composer `.icon`, drawn in layers. The agent writes the plan;
/// the image model draws each layer as an edit of the pick; this command keys, fits and packs them, renders the six
/// appearances and draws the review sheet. The stages' work is in BuildStages.swift.
enum Build {
    /// The stages in order, and the review aids.
    static let stages = ["preview", "draw", "fit", "pack", "sheet"]
    static let aids = ["zoom", "grid"]
    /// What a run with `--plan-file` or `--redraw` runs: the preview is made already, the plan just changed.
    static let fromDraw = ["draw", "fit", "pack", "sheet"]

    static let usage = """
        rimlight build <set-id>/<slug> [--stage STAGE] [--plan-file FILE|-] [--redraw NAME]... [--dry-run] [--json] [--project DIR]
        rimlight build <set-id>/<slug> --restore NAME...
        rimlight build <set-id>/<slug> --stage zoom (--box X0,Y0,X1,Y1 | --quadrants) [--rendition NAME]... [--scale S]
        rimlight build <set-id>/<slug> --stage zoom (--outline LAYER... | --outlines) [--rendition NAME]...
        rimlight build <set-id>/<slug> --stage grid --box X0,Y0,X1,Y1
        rimlight build <set-id>/<slug>... --prune
        rimlight build <set-id>/<slug>... --direction NAME [any of the options above]
        rimlight build --root DIR <id>... [the same options, but not --direction]
        """

    static let help = """
        usage:
        \(usage)

        Turns a picked render into an Icon Composer .icon in layers, with its own Dark ground and a Mono that
        lifts the subject. In a project each build starts from the icon's own icon.png and lives in a direction's
        folder, .rimlight/sets/<set>/<slug>/builds/<direction>/. --direction NAME (1 to 32 of a-z, 0-9 and -)
        builds another way of the same pick, such as a Dark that turns a black mark white; without it the
        direction is main. Every stage, aid and option acts on that direction's folder. main's package is
        out/<Title>.icon, another direction's out/<Title>, <direction>.icon. A build/ from 0.4.2 or earlier moves
        to builds/main/ the first time a build touches the icon. With --root each DIR/<id>/ holds the pick at
        src/render.png, and the package is out/build.icon.

        --plan-file FILE, or - for stdin, checks the layer plan (the ground, Dark's ground and each layer, bottom
        to top), stores it as plan.json, moves the one before into rounds/, and runs draw, fit, pack and sheet,
        or the one --stage names. It takes one icon. With --dry-run it checks the plan and prints what it would
        draw, storing nothing. Before draw spends an image on a layer, it copies the icon's other directions'
        drawing of the same layer drawn from the same words, if one has it, and prints a SHARED line instead.
        --redraw NAME draws that layer again with the same words (ground and ground-dark
        name the ground and Dark's, <layer>-dark a layer's drawn Dark copy), then runs the same stages. --restore NAME swaps a layer's drawing with the
        one it replaced, kept in gen/rounds/, then runs fit, pack and sheet; it costs nothing.

        The stages, in order: preview (the tile, the square the image model edits, and the grid), draw (each layer
        through the image model, one image each, four at a time; a layer whose own words are unchanged is not drawn again), fit (each
        drawing keyed and fitted onto the tile), pack (the package, its six renders through ictool, and the plain
        assembly) and sheet (out/review.png). Without --stage every stage runs, and a run that needs the tile makes
        it first when the direction has none. draw and every dry run print SPENT, the images drawn for the icon so
        far in every direction, kept or replaced, a shared copy counted once. pack prints a CONTRAST line per
        appearance, each layer against what is behind it, and a WARNING for a layer that fades into it; then an EDGE
        line per layer, its outline and fill in Default against the pick at full size: outline (how far the edge
        wobbles about its own course, px), band (how much lighter or darker the pixels just inside the edge are than
        those a little further in) and fill (the grain inside), each at the 64 px block where Default is furthest
        from the pick, then the inside's median lightness and its colour ΔE against the pick's, and a WARNING with
        boxes where the outline is rougher, carries a band the pick's does not, or the fill is mottled, or where the
        colour is off (ΔE 3 or more; a layer's "match": true takes the pick's colour, free). sheet writes out/compare.png, the pick against Default, prints a MATCH line with boxes
        where a part moved or changed shape, then a CHECK line for each of the plan's checks. The aids: zoom (the pick and the renders cropped
        at 1024 px, by --box in tile px or the four --quadrants; or with --outline LAYER, or --outlines for every
        layer, 1:1 crops along the layer's whole outline, the pick beside Default and Dark unless --rendition names
        others, as few sheets as hold them, out/zoom-outline-<layer>-<n>.png) and grid (part of the tile enlarged
        with a fine grid, for placing a box). --prune removes what a run from fit makes again.

        Only draw costs: it prints COST N images first, counting only what it will draw, and --stage draw
        --dry-run prints the count, a `would share` line per drawing it would copy from another direction and a
        `would draw` line per image, without drawing any.
        \(Renderer.help)

        Exit status: 0 the stages ran, 1 a stage failed, 2 a usage error or an invalid plan, 3 the image model
        refuses every render (a LIMIT line says why, and when it resets), 4 a stage's input is missing (the message names the command
        that makes it).
        """

    static let missingStatus: Int32 = 4

    /// The icons of one run, in either layout.
    struct Target {
        let layout: BuildLayout
        let ids: [String]
        /// The project, in the store layout.
        let store: ProjectStore?
        /// The command line that names one icon, for the messages that say what to run.
        let command: (String) -> String
        /// Each icon's title, in the store layout.
        var titles: [String: String] = [:]

        func folder(_ id: String) -> URL { layout.folder(id) }

        /// The layout of one icon: its own package name in the store.
        func layout(for id: String) -> BuildLayout {
            guard layout.kind == .store, let title = titles[id] else { return layout }
            return layout.named(title)
        }
    }

    static func run(_ raw: ArraySlice<String>) throws -> Int32 {
        let args = try Arguments(
            raw, flags: ["--dry-run", "--quadrants", "--outlines", "--prune", "--help", "-h"],
            options: Set([
                "--root", "--stage", "--box", "--rendition", "--scale", "--outline", "--plan-file", "--redraw", "--restore", "--direction",
            ]).union(Renderer.options))
        if args.flag("--help") || args.flag("-h") {
            Output.out(help)
            return 0
        }
        let json = args.flag("--json")
        // with --json the lines go to stderr and one reply to stdout
        let say: @Sendable (String) -> Void = { line in
            (json ? FileHandle.standardError : FileHandle.standardOutput).write(Data((line + "\n").utf8))
        }

        // what to run
        let stage = args.value("--stage")
        if let stage, !(stages + aids).contains(stage) {
            throw UsageError("unknown stage \"\(stage)\"; the stages are \((stages + aids).joined(separator: ", "))")
        }
        let redraw = args.values("--redraw")
        let restore = args.values("--restore")
        let planFile = args.value("--plan-file")
        let dryRun = args.flag("--dry-run")
        if dryRun, !(stage == "draw" || (stage == nil && planFile != nil)) {
            throw UsageError("--dry-run goes with --stage draw, or with --plan-file to price a plan without storing it")
        }
        if args.flag("--prune"), stage != nil || planFile != nil || !redraw.isEmpty || !restore.isEmpty {
            throw UsageError("--prune takes no --stage, --plan-file, --redraw or --restore")
        }
        if !restore.isEmpty, stage != nil || planFile != nil || !redraw.isEmpty {
            throw UsageError("--restore takes no --stage, --plan-file or --redraw")
        }
        let aid = try Aid.parse(stage, args)
        guard !args.positionals.isEmpty else { throw UsageError("usage:\n\(usage)") }
        if ["zoom", "grid"].contains(stage), args.positionals.count != 1 { throw UsageError("--stage \(stage!) takes one icon") }
        if planFile != nil || !redraw.isEmpty || !restore.isEmpty, args.positionals.count != 1 {
            throw UsageError("--plan-file, --redraw and --restore take one icon")
        }
        let target: Target
        switch try resolve(args, say: say) {
        case .target(let t): target = t
        case .missing(let message):
            Output.err("ERROR: \(message)")
            return missingStatus
        }

        if args.flag("--prune") { return try prune(target, say: say, json: json) }

        // One build of an icon at a time: a build writes the whole folder, and a reader checks this lock before
        // it reads out/
        var locks: [BuildLock] = []
        for id in target.ids {
            guard let lock = try BuildLock(target.folder(id).appending(path: ".lock"), say: say, id: id) else { return 1 }
            locks.append(lock)
        }
        defer { withExtendedLifetime(locks) {} }

        let work = BuildStages(target: target, say: say, renderer: Result { try Renderer.make(args) })
        if let planFile, dryRun {
            // what the new plan would draw against what is drawn, with nothing stored and nothing spent
            let checked: PlanFile.Checked
            switch try readPlan(planFile) {
            case .data(let data):
                do { checked = try PlanFile.check(data) } catch let invalid as PlanFile.Invalid {
                    Output.err("ERROR: \(invalid)")
                    return 2
                }
            case .status(let status): return status
            }
            for warning in checked.warnings { Output.err("WARNING: \(target.ids[0]): \(warning)") }
            try work.previewMissing()
            if let missing = work.missingInput("draw", redraw: redraw, planStored: false) {
                Output.err("ERROR: \(missing)")
                return missingStatus
            }
            let drawn = try work.draw(redraw: redraw, dryRun: true, plan: checked.plan)
            for id in target.ids { say(work.spentLine(id)) }
            if json { try Output.json(reply(target, stages: [], cost: drawn.cost)) }
            return 0
        }
        if let planFile {
            if let status = try storePlan(planFile, target, say: say) { return status }
        }
        if !restore.isEmpty {
            do { try work.restore(restore) } catch {
                Output.err("ERROR: \(error)")
                return missingStatus
            }
        }
        let run = stage.map { [$0] } ?? (!restore.isEmpty ? ["fit", "pack", "sheet"]
            : planFile != nil || !redraw.isEmpty ? fromDraw : stages)
        var picks: [String: String] = [:]
        if target.store != nil {
            for id in target.ids { picks[id] = (try? BuildRecord.sha256(of: target.layout.pick(id))) ?? "" }
        }

        if !run.contains("preview"), run.contains(where: { ["draw", "fit", "grid"].contains($0) }) { try work.previewMissing() }
        var done: [String] = []
        var cost: String?
        var status: Int32 = 0
        // run.json, so the app shows the build while it runs: only a run that changes how the build looks writes it
        let tracked = target.store != nil && run.contains { ["draw", "fit", "pack"].contains($0) }
        let started = Date()
        var rounds: [String: Int] = [:]
        for id in target.ids where tracked { rounds[id] = BuildRun.round(in: target.folder(id)) }
        /// False when an icon was deleted meanwhile: the run stops rather than make its folder again.
        func track(_ state: BuildRun.State, stage: String?, failed: String? = nil) -> Bool {
            guard tracked, let store = target.store else { return true }
            for id in target.ids {
                let (set, slug) = split(id)
                let record = BuildRun(
                    state: state, stage: stage, stages: done, failed: failed, host: Jobs.hostPID, round: rounds[id] ?? 0,
                    started: started)
                do { try store.writeBuildRun(record, set: set, slug: slug, direction: target.layout.direction) } catch StoreError.notFound(let message) {
                    Output.err("ERROR: \(message); the build stops")
                    return false
                } catch {
                    Output.err("WARNING: could not write run.json for \(id): \(error)")
                }
            }
            return true
        }
        if !track(.running, stage: run.first) { return missingStatus }
        stageLoop: for name in run {
            if let missing = work.missingInput(name, redraw: redraw + restore) {
                Output.err("ERROR: \(missing)")
                status = missingStatus
                break
            }
            if !done.isEmpty, stages.contains(name), !track(.running, stage: name) {
                status = missingStatus
                break
            }
            do {
                switch name {
                case "preview": try work.preview()
                case "draw":
                    let drawn = try work.draw(redraw: redraw, dryRun: dryRun)
                    cost = drawn.cost
                    status = drawn.status
                    for id in target.ids { say(work.spentLine(id)) }
                    if status != 0 { break stageLoop }
                case "fit": try work.fit()
                case "pack": try work.pack()
                case "sheet": try work.sheet()
                case "zoom": try work.zoom(aid)
                case "grid": try work.grid(aid)
                default: break
                }
            } catch let invalid as PlanFile.Invalid {
                Output.err("ERROR: \(invalid)")
                status = 2
                break
            } catch {
                Output.err("ERROR: the \(name) stage failed: \(error)")
                status = 1
                break
            }
            done.append(name)
        }
        let failed = status == 0 ? nil : run.first { !done.contains($0) }
        _ = track(status == 0 ? .done : .failed, stage: nil, failed: failed)
        // only a run that makes the package records it: an aid run after the pick changed must not make a stale
        // build look fresh, since the app compares the pick's hash with this one
        if let store = target.store, run.contains("pack") {
            for id in target.ids {
                let (set, slug) = split(id)
                let direction = target.layout.direction
                var record = BuildRecord(
                    pick: picks[id] ?? "", rimlight: Rimlight.version, engine: "layers \(LayerPrompts.version)",
                    stages: done, failed: failed, built: Date(),
                    made: done.contains("pack") ? made(target, id, round: rounds[id] ?? 0) : nil)
                // a run that failed before pack left the last package in place, and the record still names it
                if !done.contains("pack"), let last = store.readBuildRecord(set: set, slug: slug, direction: direction) {
                    record.keepMade(from: last)
                }
                do { try store.writeBuildRecord(record, set: set, slug: slug, direction: direction) } catch {
                    Output.err("WARNING: could not write build.json for \(id): \(error)")
                }
            }
        }
        if json { try Output.json(reply(target, stages: done, cost: cost)) }
        return status
    }

    /// What pack made for `id`, as `build.json` names it: paths relative to the direction's folder, the layers read
    /// back from the package it wrote.
    private static func made(_ target: Target, _ id: String, round: Int) -> BuildRecord.Made {
        let folder = target.folder(id)
        let package = target.layout(for: id).packageURL(id)
        let fm = FileManager.default
        let renders = ICTool.renditions.reduce(into: [String: String]()) { all, rendition in
            let path = "out/renders/\(rendition).png"
            if fm.fileExists(atPath: folder.appending(path: path).path) { all[rendition] = path }
        }
        let layers = IconPackage.layers(of: package, relativeTo: folder)
        return BuildRecord.Made(
            host: Jobs.hostPID, round: round, package: IconPackage.relative(package, to: folder),
            hero: fm.fileExists(atPath: folder.appending(path: BuildStages.heroPath).path) ? BuildStages.heroPath : nil,
            renders: renders, ground: layers?.ground, layers: layers?.layers ?? [])
    }

    // MARK: Targets

    enum Resolved {
        case target(Target)
        case missing(String)
    }

    /// The icons the positionals name: `--root DIR` with plain ids, else `<set>/<slug>` in the project, in the
    /// direction `--direction` names. An icon's `build/` from 0.4.2 or earlier moves to `builds/main/` here.
    static func resolve(_ args: Arguments, say: (String) -> Void = { _ in }) throws -> Resolved {
        let ids = args.positionals
        let direction = args.value("--direction")
        if let direction, !BuildDirection.isValid(direction) {
            throw UsageError("--direction takes 1 to 32 of a-z, 0-9 and -, not \"\(direction)\"")
        }
        if let rootPath = args.value("--root") {
            guard args.value("--project") == nil else { throw UsageError("--root and --project can't be used together") }
            // a root id is one build with no siblings to name
            guard direction == nil else { throw UsageError("--direction goes with a project's <set>/<slug>, not --root") }
            let root = CLI.absolute(rootPath)
            guard ProjectStore.isDirectory(root.path) else { return .missing("no build root at \(root.path)") }
            for id in ids where id.isEmpty || id.contains("/") || id == "." || id == ".." || id.hasPrefix("-") {
                throw UsageError("--root takes plain ids, not \"\(id)\"")
            }
            let quoted = SkillText.shellQuoted(root.path)
            return .target(Target(
                layout: .root(root), ids: ids, store: nil, command: { "rimlight build --root \(quoted) \($0)" }))
        }
        let store = try CLI.store(args)
        var titles: [String: String] = [:]
        for id in ids {
            let parts = id.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2 else { throw UsageError("build takes <set-id>/<slug>, or --root DIR <id>, not \"\(id)\"") }
            titles[id] = try store.readIcon(set: parts[0], slug: parts[1]).icon.title
        }
        for id in ids {
            let (set, slug) = split(id)
            switch try store.moveLegacyBuild(set: set, slug: slug) {
            case .moved: say("MOVED \(id): build/ to builds/main/")
            case .kept: Output.err("WARNING: \(id): build/ is left as it is, since builds/main/ exists; move or remove it by hand")
            case .none: break
            }
        }
        let chosen = direction ?? BuildDirection.main
        let named = chosen == BuildDirection.main ? "" : " --direction \(chosen)"
        let project = args.value("--project").map { " --project \(SkillText.shellQuoted(CLI.absolute($0).path))" } ?? ""
        return .target(Target(
            layout: .store(store, direction: chosen), ids: ids, store: store,
            command: { "rimlight build \($0)\(named)\(project)" }, titles: titles))
    }

    static func split(_ id: String) -> (String, String) {
        let parts = id.split(separator: "/", maxSplits: 1).map(String.init)
        return (parts[0], parts.count > 1 ? parts[1] : "")
    }

    // MARK: Plan

    /// Checks and stores `--plan-file`; nil to go on, else the exit status.
    enum PlanRead { case data(Data), status(Int32) }

    /// `--plan-file`'s bytes, from stdin for `-`.
    static func readPlan(_ file: String) throws -> PlanRead {
        if file == "-" {
            guard isatty(STDIN_FILENO) == 0 else {
                throw UsageError("--plan-file - reads plan.json from stdin; pass it with a quoted heredoc (<<'JSON')")
            }
            return .data(FileHandle.standardInput.readDataToEndOfFile())
        }
        let url = CLI.absolute(file)
        guard let read = FileManager.default.contents(atPath: url.path) else {
            Output.err("ERROR: cannot read the plan file \(url.path)")
            return .status(missingStatus)
        }
        return .data(read)
    }

    static func storePlan(_ file: String, _ target: Target, say: @Sendable (String) -> Void) throws -> Int32? {
        let data: Data
        switch try readPlan(file) {
        case .data(let d): data = d
        case .status(let status): return status
        }
        let checked: PlanFile.Checked
        do { checked = try PlanFile.check(data) } catch let invalid as PlanFile.Invalid {
            Output.err("ERROR: \(invalid)")
            return 2
        }
        let id = target.ids[0]
        for warning in checked.warnings { Output.err("WARNING: \(id): \(warning)") }
        let folder = target.folder(id)
        let round = try target.store.map { store in try store.exclusive { try PlanFile.store(data, in: folder) } }
            ?? PlanFile.store(data, in: folder)
        say("PLAN FILE \(folder.appending(path: "plan.json").path)"
            + (round.map { ", the one before in rounds/\($0.lastPathComponent)" } ?? ""))
        return nil
    }

    // MARK: Prune

    static func prune(_ target: Target, say: @Sendable (String) -> Void, json: Bool) throws -> Int32 {
        struct Row: Encodable { var id: String; var removed: [String]; var megabytes: Int }
        var rows: [Row] = []
        for id in target.ids {
            guard let lock = try BuildLock(target.folder(id).appending(path: ".lock"), say: say, id: id) else { return 1 }
            let (removed, bytes) = try BuildPrune.prune(target.folder(id))
            withExtendedLifetime(lock) {}
            let mb = Int(bytes / 1_048_576)
            say("PRUNE \(id): \(removed.count) item\(removed.count == 1 ? "" : "s"), \(mb) MB; a run from fit makes them again")
            rows.append(Row(id: id, removed: removed, megabytes: mb))
        }
        if json { try Output.json(rows) }
        return 0
    }

    // MARK: JSON

    struct IconRow: Encodable {
        var id: String
        var package: String?
        var renders: String?
        var assembled: String?
        var review: String?
    }

    struct Reply: Encodable {
        /// The direction built, in the store layout.
        var direction: String?
        var stages: [String]
        var cost: String?
        var icons: [IconRow]
    }

    static func reply(_ target: Target, stages: [String], cost: String?) -> Reply {
        let fm = FileManager.default
        func existing(_ url: URL) -> String? { fm.fileExists(atPath: url.path) ? url.path : nil }
        let icons = target.ids.map { id in
            let layout = target.layout(for: id)
            return IconRow(
                id: id, package: existing(layout.packageURL(id)), renders: existing(layout.file(id, "out/renders")),
                assembled: existing(layout.file(id, "out/assembled.png")), review: existing(layout.file(id, "out/review.png")))
        }
        let direction = target.layout.kind == .store ? target.layout.direction : nil
        return Reply(direction: direction, stages: stages, cost: cost, icons: icons)
    }
}

/// zoom's and grid's options, checked before anything runs.
struct Aid {
    var box: [Int]?
    var quadrants = false
    /// The layers whose outlines zoom walks; empty for every layer, nil when zoom is by box or quadrant.
    var outlines: [String]?
    var renditions: [String] = []
    var scale: Double?

    static func parse(_ stage: String?, _ args: Arguments) throws -> Aid {
        let box = try args.value("--box").map(parseBox)
        let renditions = args.values("--rendition")
        let scale = args.value("--scale")
        let named = args.values("--outline")
        let outlines: [String]? = args.flag("--outlines") ? [] : named.isEmpty ? nil : named
        switch stage {
        case "zoom":
            for r in renditions where !ICTool.renditions.contains(r) {
                throw UsageError("unknown rendition \"\(r)\"; the renditions are \(ICTool.renditions.joined(separator: ", "))")
            }
            var value: Double?
            if let scale {
                guard let s = Double(scale), s > 0 else { throw UsageError("--scale takes a number over 0, not \"\(scale)\"") }
                value = s
            }
            let ways = [box != nil, args.flag("--quadrants"), args.flag("--outlines"), !named.isEmpty].filter { $0 }.count
            guard ways == 1 else {
                throw UsageError("--stage zoom takes one of --box X0,Y0,X1,Y1, --quadrants, --outline NAME or --outlines")
            }
            if outlines != nil, value != nil { throw UsageError("--outline draws 1:1 and takes no --scale") }
            return Aid(box: box, quadrants: args.flag("--quadrants"), outlines: outlines, renditions: renditions, scale: value)
        case "grid":
            guard let box, renditions.isEmpty, scale == nil, !args.flag("--quadrants"), outlines == nil else {
                throw UsageError("--stage grid takes --box X0,Y0,X1,Y1 alone")
            }
            return Aid(box: box)
        default:
            if box != nil || !renditions.isEmpty || scale != nil || args.flag("--quadrants") || outlines != nil {
                throw UsageError("--box, --quadrants, --outline, --outlines, --rendition and --scale go with --stage zoom or grid")
            }
            return Aid()
        }
    }

    /// `X0,Y0,X1,Y1` in the 1024 px tile.
    static func parseBox(_ raw: String) throws -> [Int] {
        let v = raw.split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard v.count == 4, let x0 = v[0], let y0 = v[1], let x1 = v[2], let y1 = v[3],
            0 <= x0, x0 < x1, x1 <= 1024, 0 <= y0, y0 < y1, y1 <= 1024
        else { throw UsageError("--box takes X0,Y0,X1,Y1 in the 1024 px tile, with X0 < X1 and Y0 < Y1, not \"\(raw)\"") }
        return [x0, y0, x1, y1]
    }
}

/// The exclusive lock on one icon's build folder, `.lock` there, held for the run. Waits, with a line, when
/// another build of the same icon holds it.
final class BuildLock {
    let fd: Int32

    init?(_ url: URL, say: (String) -> Void, id: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw StoreError.io("Cannot open \(url.path) (errno \(errno))") }
        var told = false
        while flock(fd, LOCK_EX | (told ? 0 : LOCK_NB)) != 0 {
            if errno == EINTR { continue }
            guard errno == EWOULDBLOCK, !told else {
                close(fd)
                Output.err("ERROR: cannot lock \(url.path) (errno \(errno))")
                return nil
            }
            say("WAIT another rimlight build of \(id) is running; this one starts when it ends")
            told = true
        }
        self.fd = fd
    }

    deinit { close(fd) }
}
