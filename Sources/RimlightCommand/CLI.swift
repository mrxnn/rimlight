import Foundation
import RimlightCore

/// `rimlight <command> …`. Returns the exit status: 0 on success, 1 on a failure, 2 on a usage error.
enum CLI {
    static let usage = """
        rimlight \(Rimlight.version): Rimlight's icon store and renderer

        Usage:
          rimlight status [--json]
          rimlight init
          rimlight set create [--title "..."]
          rimlight set rename <set-id> --title "..."
          rimlight generate --set <set-id> --slug <slug> --title "..."
                            (--prompt-file FILE | --prompt-file - | --prompt "...")
                            [--ref IMAGE]... [--parent <set-id>/<slug>] [--count N] [--force]
                            [--fix-attempts N] [--by NAME] [--effort E] [--timeout SECONDS] [--dry-run]
                            [--provider P] [--model M] [--quality Q] [--base-url URL]
          rimlight fix <set-id>/<slug> [--attempts N]
          rimlight fix --all --set <set-id> [--attempts N]
          rimlight fit <set-id>/<slug>
          rimlight fit --all --set <set-id>
          rimlight build <set-id>/<slug> [--stage STAGE] [--plan-file FILE|-] [--redraw NAME]... [--dry-run]
                         [--direction NAME]
          rimlight build --root DIR <id>... [the same options]
          rimlight image [--set PROVIDER [--model M] [--quality Q] [--base-url URL]] [--models]
          rimlight install-skill [--harness claude|codex] [--skills-dir DIR] [--style NAME]
          rimlight skill [--style NAME | --file PATH] [--cli COMMAND] [--styles-dir DIR]
          rimlight self-install [--prefix DIR] [--skills-dir DIR] [--no-skill]
          rimlight self-uninstall [--prefix DIR]
          rimlight doctor
          rimlight version

        Every command takes --project DIR (default: the nearest folder at or above the
        current one that holds .rimlight/) and --json. `--prompt-file -` reads the prompt
        from stdin (a quoted heredoc); `generate --dry-run` checks the arguments, prints the
        prompt's length and renders nothing. `rimlight generate --help` shows an example.
        `generate` checks each render's pixels and fixes an opaque one in up to --fix-attempts N
        attempts (default 3): a transparency edit, a fresh re-roll of the same request, and an
        edit of the re-roll. `fix` runs that fix on stored icons, in place, after correcting any
        stored alpha the pixels disagree with; an icon that is already transparent costs no render.
        Both fit every transparent result to Apple's tile shape before storing it and keep the
        image before the fit as raw.png, and the model's opaque render as original.png when a fix
        made the image from it. `fit` redoes that fit on stored icons, in place, from
        raw.png (or icon.png when there is none), without a render.
        `build` turns a picked render into an Icon Composer .icon package with a true Dark and Mono: the
        image model draws each layer of the agent's plan.json as an edit of the pick, and rimlight keys, fits
        and packs them; `rimlight build --help` has the stages, the aids and the exit codes.
        `image` shows the image model generate, fix and build render with, picked in Rimlight's settings
        or with `rimlight image --set`: Codex on the ChatGPT plan it's signed in with, or OpenAI or
        OpenRouter on your own key. --provider, --model, --quality and --base-url override it for one
        command.
        `install-skill` writes the adaptive skill, which has the agent pick the styles that suit
        each app and read their files. `--style NAME` installs one style in its place, and
        `--style none` the instructions alone, with no design process or style. The styles are
          \(DesignStyle.allCases.prefix(4).map(\.slug).joined(separator: ", ")),
          \(DesignStyle.allCases.dropFirst(4).map(\.slug).joined(separator: ", ")).
        Their files go beside SKILL.md whatever the pick. Without --style it keeps the pick the
        skill was last installed with. It installs for Claude Code in ~/.claude/skills, and for
        Codex in ~/.codex/skills when ~/.codex exists, with a few lines on Codex's tools after
        the text; --harness names one, and --skills-dir sets its folder, Claude Code's unless
        --harness says codex. A project command run by a newer rimlight
        than the one that wrote a skill rewrites it with the same pick.
        `skill` prints the text a chat starts with, adaptive unless --style or --file says
        otherwise. `self-install` copies this rimlight into ~/.local/share/rimlight/<version>,
        points ~/.local/bin/rimlight at it and installs the skill; `self-uninstall` removes that
        copy. `doctor` lists every rimlight on PATH, which one runs, and the installed skill.
        """

    static func main(_ args: [String]) -> Int32 {
        guard let command = args.first else {
            Output.out(usage)
            return 2
        }
        let rest = args.dropFirst()
        do {
            if projectCommands.contains(command) { refreshSkill() }
            switch command {
            case "status": try status(rest)
            case "init": try initProject(rest)
            case "set": try set(rest)
            case "generate": return try Generate.run(rest)
            case "fix": return try Fix.run(rest)
            case "fit": return try Fit.run(rest)
            case "build": return try Build.run(rest)
            case "image": return try Image.run(rest)
            case "install-skill": try installSkill(rest)
            case "skill": try Tools.skill(rest)
            case "self-install": try Tools.selfInstall(rest)
            case "self-uninstall": try Tools.selfUninstall(rest)
            case "doctor": try Tools.doctor(rest)
            case "version": try Tools.version(rest)
            case "--version", "-v": Output.out("rimlight \(Rimlight.version)")
            case "help", "--help", "-h": Output.out(usage)
            default: throw UsageError("unknown command \"\(command)\"")
            }
            return 0
        } catch let error as UsageError {
            Output.err("rimlight: \(error)\nRun `rimlight help` for usage.")
            return 2
        } catch {
            Output.err("ERROR: \(error)")
            return 1
        }
    }

    /// The commands that open a project; the agent's first is `status`.
    static let projectCommands: Set<String> = ["status", "init", "set", "generate", "fix", "fit"]

    /// Rewrites the installed skill when an older rimlight wrote it, so `brew upgrade` updates
    /// the skill as well as the binary. One small read when there is nothing to do; a failure
    /// is left for `rimlight doctor` and never stops the command.
    static func refreshSkill() {
        guard let exe = CurrentProcess.executableURL else { return }
        for harness in SkillHarness.allCases {
            let dir = harness.defaultSkillsDir()
            // A Codex folder linked to Claude Code's is Claude Code's skill: refreshing it as
            // Codex's would add the Codex note.
            if harness == .codex, SkillHarness.isClaudeFolder(dir) { continue }
            guard
                (try? SkillText.refreshIfOlder(
                    executable: exe, searchPath: Tools.searchPath, skillsDir: dir, harness: harness)) == true
            else { continue }
            Output.err("NOTE: updated the installed \(harness.displayName) skill to rimlight \(Rimlight.version)")
        }
    }

    /// The pick a `--style` name stands for, or a usage error that lists the names.
    static func pick(_ name: String) throws -> DesignSkill {
        guard let picked = SkillText.skill(styleName: name) else {
            let names = SkillText.styleNames
            throw UsageError(
                "unknown style \"\(name)\"; --style takes \(names.dropLast().joined(separator: ", ")) or \(names.last ?? "")")
        }
        return picked
    }

    // MARK: Project lookup

    static var cwd: URL { URL(filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory) }

    /// An absolute, standardized file URL for a path typed on the command line.
    static func absolute(_ path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(filePath: expanded, directoryHint: .inferFromPath, relativeTo: cwd).absoluteURL.standardized
    }

    /// The store for `--project DIR`, else for the nearest `.rimlight/` at or above cwd.
    /// Refuses a project a newer rimlight wrote.
    static func store(_ args: Arguments) throws -> ProjectStore {
        let root: URL
        if let dir = args.value("--project") {
            root = absolute(dir)
            guard FileManager.default.fileExists(atPath: root.appending(path: ProjectStore.folderName).path) else {
                throw StoreError.notFound("No Rimlight project at \(root.path): run `rimlight init --project \(dir)` first")
            }
        } else {
            guard let found = ProjectStore.locate(from: cwd) else {
                throw StoreError.notFound("No .rimlight/ in \(cwd.path) or above it: run `rimlight init` first")
            }
            root = found
        }
        let store = ProjectStore(projectRoot: root)
        try store.checkSchema()
        return store
    }

    // MARK: Commands

    static func initProject(_ raw: ArraySlice<String>) throws {
        let args = try Arguments(raw)
        try args.expectPositionals(0, "rimlight init [--project DIR]")
        let root = args.value("--project").map(absolute) ?? cwd
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            throw StoreError.notFound("Folder does not exist: \(root.path)")
        }
        let store = ProjectStore(projectRoot: root)
        let created = try store.create()
        if args.flag("--json") {
            struct Reply: Encodable { var project: String; var created: Bool; var sets: [String] }
            try Output.json(Reply(project: store.root.path, created: created, sets: try store.readSets().map(\.id)))
        } else {
            Output.out(created ? "Created \(store.stateRoot.path)" : "Already a Rimlight project: \(store.stateRoot.path)")
        }
    }

    static func status(_ raw: ArraySlice<String>) throws {
        let args = try Arguments(raw)
        try args.expectPositionals(0, "rimlight status [--json]")
        let store = try store(args)
        let sets = try store.readSets().map { set in (set, try store.readIcons(in: set.id)) }
        // A render killed with SIGKILL leaves its marker; those go first, so the rest are running.
        let pruned = store.pruneDeadJobs()
        let jobs = store.readJobs()

        if args.flag("--json") {
            struct JobRow: Encodable {
                var set, slug, title, mode: String
                var pid: Int32
                var hostPID: Int32?
                var started: Date
                var alive: Bool
            }
            let jobRow = { (m: JobMarker, alive: Bool) in
                JobRow(
                    set: m.set, slug: m.slug, title: m.title, mode: m.mode.rawValue, pid: m.pid, hostPID: m.hostPID,
                    started: m.started, alive: alive)
            }
            struct IconRow: Encodable {
                var slug, title, image, mode: String
                var archived, alpha: Bool
                var width, height: Int
                var parent: String?
                var created: Date
            }
            struct SetRow: Encodable { var id, title: String; var archived: Bool; var created: Date; var icons: [IconRow] }
            struct Reply: Encodable { var project: String; var sets: [SetRow]; var jobs: [JobRow]; var pruned: [JobRow] }
            let rows = sets.map { set, icons in
                SetRow(id: set.id, title: set.title, archived: set.archived, created: set.created, icons: icons.map { s in
                    IconRow(
                        slug: s.icon.slug, title: s.icon.title, image: s.imageURL.path, mode: s.icon.mode.rawValue,
                        archived: s.icon.archived, alpha: s.icon.image.alpha, width: s.icon.image.width,
                        height: s.icon.image.height, parent: s.icon.parent?.path, created: s.icon.created)
                })
            }
            try Output.json(Reply(
                project: store.root.path, sets: rows, jobs: jobs.map { jobRow($0.marker, $0.alive) },
                pruned: pruned.map { jobRow($0, false) }))
            return
        }

        var lines = ["Project \(store.root.path)"]
        for (set, icons) in sets {
            let flag = set.archived ? " archived" : ""
            // What `rimlight fix --all` would fix: opaque and not archived.
            let opaque = icons.count { !$0.icon.image.alpha && !$0.icon.archived }
            lines.append("\(set.id) \"\(set.title)\" (\(icons.count) icon\(icons.count == 1 ? "" : "s")) opaque: \(opaque)\(flag)")
            for s in icons {
                var line = "  \(s.icon.slug) \"\(s.icon.title)\" \(s.icon.image.width)x\(s.icon.image.height)"
                line += " alpha=\(s.icon.image.alpha ? "yes" : "no")"
                if s.icon.archived { line += " archived" }
                if let parent = s.icon.parent { line += " parent=\(parent.path)" }
                line += " \(s.imageURL.path)"
                lines.append(line)
            }
        }
        let jobLine = { (m: JobMarker, alive: Bool) in
            "  \(m.iconID) \"\(m.title)\" pid \(m.pid) \(m.mode.rawValue) \(alive ? "alive" : "dead")"
        }
        lines.append("jobs: \(jobs.count { $0.alive }) running")
        lines += jobs.map { jobLine($0.marker, $0.alive) }
        if !pruned.isEmpty {
            lines.append("pruned: \(pruned.count) dead")
            lines += pruned.map { jobLine($0, false) }
        }
        Output.out(lines.joined(separator: "\n"))
    }

    static func set(_ raw: ArraySlice<String>) throws {
        guard let sub = raw.first else { throw UsageError("usage: rimlight set create|rename …") }
        let args = try Arguments(raw.dropFirst(), options: ["--title"])
        let store = try store(args)
        let set: IconSet
        switch sub {
        case "create":
            try args.expectPositionals(0, "rimlight set create [--title \"...\"]")
            set = try store.createSet(title: args.value("--title") ?? ProjectStore.defaultSetTitle)
            if !args.flag("--json") { Output.out(set.id) }
        case "rename":
            try args.expectPositionals(1, "rimlight set rename <set-id> --title \"...\"")
            set = try store.renameSet(args.positionals[0], title: try args.required("--title"))
            if !args.flag("--json") { Output.out("\(set.id) \"\(set.title)\"") }
        default:
            throw UsageError("unknown set command \"\(sub)\" (create or rename)")
        }
        if args.flag("--json") { try Output.json(set) }
    }

    static func installSkill(_ raw: ArraySlice<String>) throws {
        let args = try Arguments(raw, options: ["--harness", "--skills-dir", "--style"])
        try args.expectPositionals(
            0, "rimlight install-skill [--harness claude|codex] [--skills-dir DIR] [--style NAME]")
        let harness = args.value("--harness")
        let targets = try skillTargets(harness: harness, skillsDir: args.value("--skills-dir"))
        let style = try args.value("--style").map(pick)
        let cli = try Tools.executable()
        let command = SkillText.cliCommand(
            executable: cli, searchPath: ProcessInfo.processInfo.environment["PATH"])
        let installs = try installSkills(
            targets, command: command, style: style, required: harness != nil, quiet: args.flag("--json"))
        if args.flag("--json") {
            struct Skill: Encodable {
                var harness, path, style, styles, build: String
                var written: Bool
                init(_ i: SkillInstall) {
                    harness = i.harness.rawValue
                    path = i.path
                    style = i.style
                    styles = SkillText.installedStylesURL(in: i.dir).path
                    build = SkillText.installedBuildURL(in: i.dir).path
                    written = i.written
                }
            }
            // The first install's fields at the top, as when there was one, and every install in `skills`.
            struct Reply: Encodable {
                var harness, path, style, styles, build, cli, command: String
                var written: Bool
                var skills: [Skill]
            }
            let skills = installs.map(Skill.init)
            guard let first = skills.first else { return }
            try Output.json(Reply(
                harness: first.harness, path: first.path, style: first.style, styles: first.styles, build: first.build,
                cli: cli.path, command: command, written: first.written, skills: skills))
        } else {
            Output.out(installs.map(\.line).joined(separator: "\n"))
        }
    }

    struct SkillInstall {
        var harness: SkillHarness
        var dir: URL
        var path: String
        var style: String
        var written: Bool
        var line: String
    }

    /// Installs the skill for each target, `style` or each folder's recorded pick. A harness the
    /// person did not name (`required` false) is a bonus: Codex's install failing is a NOTE on
    /// stderr, so a Codex folder rimlight can't write never fails Claude Code's install or
    /// `self-install`. A failure that is an error still says what installed before it.
    static func installSkills(
        _ targets: [(SkillHarness, URL)], command: String, style: DesignSkill?, required: Bool, quiet: Bool
    ) throws -> [SkillInstall] {
        var installs: [SkillInstall] = []
        for (harness, dir) in targets {
            let skill = style ?? SkillText.defaultPick(in: dir)
            do {
                let written = try SkillText.install(cliPath: command, to: dir, skill: skill, harness: harness)
                let path = SkillText.installedURL(in: dir).path
                let name = SkillRecord.styleName(of: skill)
                installs.append(SkillInstall(
                    harness: harness, dir: dir, path: path, style: name, written: written,
                    line: (written ? "Installed \(path)" : "Up to date: \(path)") + " (style: \(name), command: \(command))"))
            } catch {
                if !required, harness != .claude {
                    Output.err("NOTE: could not install the \(harness.displayName) skill in \(dir.path): \(error)")
                    continue
                }
                if !installs.isEmpty, !quiet { Output.out(installs.map(\.line).joined(separator: "\n")) }
                throw error
            }
        }
        return installs
    }

    /// The harnesses an install writes for, each with its skills folder: the one `--harness`
    /// names; else Claude Code alone in `--skills-dir`, as before there was a Codex copy; else
    /// `SkillHarness.defaults` in their own folders.
    static func skillTargets(harness name: String?, skillsDir: String?) throws -> [(SkillHarness, URL)] {
        let dir = skillsDir.map(absolute)
        guard let name else {
            if let dir { return [(.claude, dir)] }
            return SkillHarness.defaults().map { ($0, $0.defaultSkillsDir()) }
        }
        guard let harness = SkillHarness(rawValue: name) else {
            throw UsageError("unknown harness \"\(name)\"; --harness takes claude or codex")
        }
        let target = dir ?? harness.defaultSkillsDir()
        if harness == .codex, SkillHarness.isClaudeFolder(target) {
            throw UsageError(
                "\(target.path)/\(SkillText.skillName) is Claude Code's skill folder through a link, so Codex already reads it; "
                    + "a Codex install there would put the Codex note in Claude Code's skill")
        }
        return [(harness, target)]
    }
}

enum Output {
    static func out(_ s: String) { print(s) }

    static func err(_ s: String) {
        FileHandle.standardError.write(Data((s.hasSuffix("\n") ? s : s + "\n").utf8))
    }

    static func json<T: Encodable>(_ value: T) throws {
        print(String(decoding: try StateCoding.encoder().encode(value), as: UTF8.self))
    }
}
