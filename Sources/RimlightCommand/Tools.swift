import Foundation
import RimlightCore

/// The commands about the tools themselves rather than a project: printing the skill text,
/// the version, a health check, and installing or removing the standalone copy.
enum Tools {
    static var searchPath: String? { ProcessInfo.processInfo.environment["PATH"] }

    static func executable() throws -> URL {
        guard let url = CurrentProcess.executableURL else { throw StoreError.io("Cannot tell where this rimlight binary is") }
        return url
    }

    /// `rimlight skill`: the skill text a chat starts with, printed for the app or anyone who
    /// wants to see it. Adaptive unless `--style` or `--file` says otherwise; the command it
    /// names follows the same PATH rule as `install-skill`; the style files and Build.md are this
    /// copy's own.
    static func skill(_ raw: ArraySlice<String>) throws {
        let args = try Arguments(raw, options: ["--style", "--file", "--cli", "--styles-dir"])
        try args.expectPositionals(0, "rimlight skill [--style NAME | --file PATH] [--cli COMMAND] [--styles-dir DIR]")
        let style = args.value("--style")
        let file = args.value("--file")
        if style != nil, file != nil { throw UsageError("--style and --file can't be used together") }
        var pick = DesignSkill.adaptive
        if let style { pick = try CLI.pick(style) }
        if let file { pick = DesignSkill(path: CLI.absolute(file).path) }
        let command = try args.value("--cli") ?? SkillText.cliCommand(executable: executable(), searchPath: searchPath)
        let styles = try args.value("--styles-dir").map { CLI.absolute($0).path } ?? SkillText.stylesDirectory().path
        let build = try SkillText.buildFile().path
        let loaded = SkillSource.load(
            pick, texts: try SkillText.bundledTexts(), cliPath: command, stylesPath: styles, buildPath: build)
        if let fallback = loaded.fallback { throw StoreError.notFound(fallback) }
        if args.flag("--json") {
            struct Reply: Encodable { var version, style, command, styles, build, text: String }
            try Output.json(Reply(
                version: Rimlight.version, style: SkillRecord.styleName(of: pick), command: command, styles: styles,
                build: build, text: loaded.prompt.text))
        } else {
            FileHandle.standardOutput.write(Data(loaded.prompt.text.utf8))
        }
    }

    static func version(_ raw: ArraySlice<String>) throws {
        let args = try Arguments(raw)
        try args.expectPositionals(0, "rimlight version [--json]")
        guard args.flag("--json") else {
            Output.out("rimlight \(Rimlight.version)")
            return
        }
        struct Reply: Encodable { var version, path, kind: String; var bundle: String?; var schema: Int }
        let path = try executable().path
        try Output.json(Reply(
            version: Rimlight.version, path: path, kind: ToolCopy.kind(ofResolved: path).rawValue,
            bundle: CoreResources.bundleURL()?.path, schema: Project.currentSchema))
    }

    /// `rimlight self-install`: this binary and its resources into the standalone layout under
    /// `--prefix` (`~/.local`), then the skill for Claude Code, and for Codex when it is set up,
    /// each keeping its recorded pick. `--skills-dir` installs Claude Code's alone, there.
    static func selfInstall(_ raw: ArraySlice<String>) throws {
        let args = try Arguments(raw, flags: ["--no-skill"], options: ["--prefix", "--skills-dir"])
        try args.expectPositionals(0, "rimlight self-install [--prefix DIR] [--skills-dir DIR] [--no-skill]")
        let prefix = args.value("--prefix").map(CLI.absolute) ?? StandaloneInstall.defaultPrefix
        guard let bundle = CoreResources.bundleURL() else {
            throw StoreError.notFound("\(CoreResources.bundleName) not found beside this rimlight")
        }
        let link = try StandaloneInstall.install(
            binary: executable(), bundle: bundle, version: .current, prefix: prefix)

        // The skill names `rimlight` when PATH runs the new link, else the link itself, which
        // stays valid across updates where the versioned folder does not.
        let command = SkillText.cliCommand(executable: link, searchPath: searchPath)
        var installs: [CLI.SkillInstall] = []
        if !args.flag("--no-skill") {
            installs = try CLI.installSkills(
                CLI.skillTargets(harness: nil, skillsDir: args.value("--skills-dir")), command: command, style: nil,
                required: false, quiet: true)
        }
        let runs = ToolCopy.all(searchPath: searchPath).first
        let linkResolved = CurrentProcess.realPath(link.path)
        let note: String? =
            if runs == nil { "\(link.deletingLastPathComponent().path) is not on PATH: add it to your shell's PATH." }
            else if runs?.resolved != linkResolved { "PATH runs \(runs!.path) first, not this install. Run `rimlight doctor`." }
            else { nil }

        if args.flag("--json") {
            struct SkillReply: Encodable { var harness, path, style: String; var written: Bool }
            // `skill` is the first install, Claude Code's, as when it was the only one.
            struct Reply: Encodable {
                var version, link, command: String
                var skill: SkillReply?
                var skills: [SkillReply]
                var note: String?
            }
            let skills = installs.map {
                SkillReply(harness: $0.harness.rawValue, path: $0.path, style: $0.style, written: $0.written)
            }
            try Output.json(Reply(
                version: Rimlight.version, link: link.path, command: command, skill: skills.first, skills: skills,
                note: note))
        } else {
            var lines = ["Installed rimlight \(Rimlight.version) at \(link.path)"]
            lines += installs.map(\.line)
            if let note { lines.append("NOTE: \(note)") }
            Output.out(lines.joined(separator: "\n"))
        }
    }

    /// `rimlight self-uninstall`: removes the standalone copy under `--prefix`. Homebrew's copy
    /// and the Claude Code skill stay.
    static func selfUninstall(_ raw: ArraySlice<String>) throws {
        let args = try Arguments(raw, options: ["--prefix"])
        try args.expectPositionals(0, "rimlight self-uninstall [--prefix DIR]")
        let prefix = args.value("--prefix").map(CLI.absolute) ?? StandaloneInstall.defaultPrefix
        let removed = try StandaloneInstall.remove(prefix: prefix)
        let link = StandaloneInstall.link(prefix: prefix).path
        if args.flag("--json") {
            struct Reply: Encodable { var link: String; var removed: Bool }
            try Output.json(Reply(link: link, removed: removed))
        } else {
            Output.out(removed ? "Removed the standalone rimlight at \(link)" : "No standalone rimlight at \(link)")
        }
    }

    /// `rimlight doctor`: every copy on PATH and which one runs, the installed skill, and what
    /// is wrong with either, each with the command that fixes it.
    static func doctor(_ raw: ArraySlice<String>) throws {
        let args = try Arguments(raw, options: ["--skills-dir"])
        try args.expectPositionals(0, "rimlight doctor [--skills-dir DIR]")
        let report = Doctor.Report.make(
            executable: try executable(), searchPath: searchPath,
            skillsDir: args.value("--skills-dir").map(CLI.absolute) ?? SkillText.defaultSkillsDir)
        if args.flag("--json") {
            try Output.json(report)
        } else {
            Output.out(report.text)
        }
    }
}

enum Doctor {
    struct Copy: Encodable {
        var path, resolved, kind: String
        var version: String?
        var runs: Bool
    }

    struct Skill: Encodable {
        var path: String
        var installed: Bool
        var record: SkillRecord?
    }

    /// What `rimlight build` needs on this Mac besides an image model: Icon Composer's renderer.
    struct BuildInfo: Encodable {
        var ictool: String?

        static func make() -> BuildInfo { BuildInfo(ictool: ICTool.locate()?.path) }

        var problems: [String] {
            guard ictool == nil else { return [] }
            return [
                "No Icon Composer, so `rimlight build` makes the package but no renders. Install Xcode 26 and select it "
                    + "with `sudo xcode-select -s /Applications/Xcode.app`."
            ]
        }

        var lines: [String] { ["ictool: \(ictool ?? "none")"] }
    }

    struct Report: Encodable {
        var version, path, kind: String
        var copies: [Copy]
        var skill: Skill
        var build: BuildInfo
        var problems: [String]

        static func make(executable: URL, searchPath: String?, skillsDir: URL) -> Report {
            let me = executable.path
            let found = ToolCopy.all(searchPath: searchPath)
            let copies = found.enumerated().map { i, copy in
                Copy(
                    path: copy.path, resolved: copy.resolved, kind: copy.kind.rawValue,
                    version: copy.resolved == me ? Rimlight.version : copy.probeVersion()?.description, runs: i == 0)
            }
            let skillURL = SkillText.installedURL(in: skillsDir)
            let skill = Skill(
                path: skillURL.path, installed: FileManager.default.fileExists(atPath: skillURL.path),
                record: SkillText.record(in: skillsDir))
            let build = BuildInfo.make()
            return Report(
                version: Rimlight.version, path: me, kind: ToolCopy.kind(ofResolved: me).rawValue, copies: copies,
                skill: skill, build: build, problems: problems(copies: copies, skill: skill) + build.problems)
        }

        static func problems(copies: [Copy], skill: Skill) -> [String] {
            var problems: [String] = []
            guard let runs = copies.first else {
                problems.append(
                    "No rimlight on PATH. Run `rimlight self-install` from this copy.")
                return problems
            }
            for copy in copies.dropFirst() {
                let what = "\(copy.path) (\(copy.kind), \(copy.version ?? "unknown version"))"
                let fix =
                    switch (runs.kind, copy.kind) {
                    case ("standalone", "homebrew"):
                        "Run `\(uninstall(runs))` to remove the standalone copy, and Homebrew's will run."
                    case (_, "standalone"): "Run `\(uninstall(copy))` to remove it."
                    case (_, "homebrew"): "Run `brew uninstall rimlight` to remove it."
                    default: "Remove it by hand."
                    }
                problems.append("\(what) never runs, because PATH finds \(runs.path) first. \(fix)")
            }
            guard skill.installed else {
                problems.append("No Claude Code skill installed. Run `rimlight install-skill`.")
                return problems
            }
            guard let record = skill.record else {
                problems.append("The installed skill has no install record, so an older rimlight wrote it. Run `rimlight install-skill`.")
                return problems
            }
            if let recorded = RimlightVersion(record.version), let running = runs.version.flatMap(RimlightVersion.init),
                recorded < running
            {
                problems.append(
                    "rimlight \(record.version) wrote the installed skill, and PATH runs \(running). "
                        + "Run `rimlight install-skill`, or any project command, to update it.")
            }
            if record.command != SkillText.commandName, CurrentProcess.realPath(record.command) != runs.resolved {
                problems.append(
                    "The skill calls \(record.command), but PATH runs \(runs.path). Run `rimlight install-skill`.")
            }
            return problems
        }

        /// The command that removes a standalone copy: `--prefix` only when it is not ~/.local.
        static func uninstall(_ copy: Copy) -> String {
            // <prefix>/share/rimlight/<version>/rimlight
            let prefix = URL(filePath: copy.resolved).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path
            let home = StandaloneInstall.defaultPrefix.standardizedFileURL.path
            let resolvedHome = CurrentProcess.realPath(home) ?? home
            return prefix == home || prefix == resolvedHome
                ? "rimlight self-uninstall" : "rimlight self-uninstall --prefix \(SkillText.shellQuoted(prefix))"
        }

        var text: String {
            var lines = ["rimlight \(version) at \(path) (\(kind))", "On PATH:"]
            if copies.isEmpty { lines.append("  none") }
            for copy in copies {
                let target = copy.path == copy.resolved ? copy.path : "\(copy.path) -> \(copy.resolved)"
                lines.append("  \(copy.runs ? "*" : " ") \(target)  \(copy.kind) \(copy.version ?? "?")\(copy.runs ? "  (runs)" : "")")
            }
            if let record = skill.record {
                lines.append(
                    "Skill: \(skill.path), written by \(record.version), style \(record.style), command \(record.command)")
            } else {
                lines.append("Skill: \(skill.path)\(skill.installed ? ", no install record" : ", not installed")")
            }
            lines += build.lines
            lines.append(problems.isEmpty ? "No problems found." : "Problems:")
            lines += problems.map { "  - \($0)" }
            return lines.joined(separator: "\n")
        }
    }
}
