import Foundation

/// The agent's system prompt: the fixed instructions in `Resources/Instructions.md`, the design
/// process in `Resources/Design.md`, then the picked design skill's own text (a style from
/// `Resources/Styles`, the style index in `Resources/Adaptive.md`, or a file of the person's),
/// rendered with the path of the `rimlight` CLI, of the folder holding the style files and of
/// `Resources/Build.md`, the guide to `rimlight build`. The installed `rimlight` Claude Code skill
/// is Adaptive unless `install-skill --style` names another built-in pick, with the style files
/// and build.md installed beside it either way; a pick in the app changes only the app's chats.
public enum SkillText {
    public static let placeholder = "{{RIMLIGHT_CLI}}"
    public static let stylesPlaceholder = "{{RIMLIGHT_STYLES}}"
    public static let buildPlaceholder = "{{RIMLIGHT_BUILD}}"
    public static let resourceBundleName = CoreResources.bundleName
    public static let skillName = "rimlight"
    /// The CLI's name on PATH.
    public static let commandName = "rimlight"

    /// `~/.claude/skills`.
    public static var defaultSkillsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude", directoryHint: .isDirectory)
            .appending(path: "skills", directoryHint: .isDirectory)
    }

    /// The bundled Instructions.md, frontmatter and placeholder included.
    public static func source() throws -> String { try read("Instructions") }

    /// The bundled Design.md, the design process.
    public static func designSource() throws -> String { try read("Design") }

    /// The bundled Adaptive.md, the index of the styles.
    public static func adaptiveSource() throws -> String { try read("Adaptive") }

    /// The bundled Build.md, what the agent reads before `rimlight build`, placeholders included.
    public static func buildSource() throws -> String { try read("Build") }

    /// The bundled Build.md, which the agent reads in the app's chats.
    public static func buildFile() throws -> URL {
        guard let url = CoreResources.url("Build", withExtension: "md") else {
            throw StoreError.notFound("Build.md not found: \(resourceBundleName) is missing")
        }
        return url
    }

    /// The bundled `Styles` folder, which the agent reads style files from in the app.
    public static func stylesDirectory() throws -> URL {
        guard let url = CoreResources.url("Styles", withExtension: nil) else {
            throw StoreError.notFound("Styles not found: \(resourceBundleName) is missing")
        }
        return url
    }

    /// Every bundled text a prompt is made from: eleven small reads.
    public static func bundledTexts() throws -> SkillSource.Texts {
        let dir = try stylesDirectory()
        var styles: [DesignStyle: String] = [:]
        for style in DesignStyle.allCases {
            let url = dir.appending(path: style.fileName, directoryHint: .notDirectory)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw StoreError.notFound("Styles/\(style.fileName) not found in \(resourceBundleName)")
            }
            styles[style] = try read(url)
        }
        return SkillSource.Texts(
            instructions: try source(), design: try designSource(), adaptive: try adaptiveSource(), styles: styles)
    }

    private static func read(_ name: String) throws -> String {
        guard let url = CoreResources.url(name, withExtension: "md") else {
            throw StoreError.notFound("\(name).md not found: \(resourceBundleName) is missing")
        }
        return try read(url)
    }

    private static func read(_ url: URL) throws -> String {
        do { return try String(contentsOf: url, encoding: .utf8) } catch {
            throw StoreError.io("Cannot read \(url.path): \(error.localizedDescription)")
        }
    }

    /// `instructions`, then each section that is not blank, trimmed, with a blank line before
    /// each. With none, `instructions` as it is.
    public static func compose(_ instructions: String, sections: [String?]) -> String {
        let parts = sections.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return instructions }
        var head = instructions
        while head.last?.isWhitespace == true { head.removeLast() }
        return ([head] + parts).joined(separator: "\n\n") + "\n"
    }

    /// What `rimlight install-skill` writes to `<skillsDir>/rimlight/SKILL.md`: `skill` as a chat
    /// in the app gets it, pointed at the style files and build.md installed beside it. The
    /// default, Adaptive, is the instructions, Design.md and the index of the styles.
    public static func rendered(
        cliPath: String, skillsDir: URL = defaultSkillsDir, skill: DesignSkill = .adaptive
    ) throws -> String {
        try rendered(
            cliPath: cliPath, stylesPath: installedStylesURL(in: skillsDir).path,
            buildPath: installedBuildURL(in: skillsDir).path, skill: skill)
    }

    /// `skill` pointed at the style files in `stylesPath` and the build guide at `buildPath`. The
    /// committed `skills/rimlight/SKILL.md` is the default with `rimlight`, `styles` and
    /// `build.md`, the folder and the file beside it.
    static func rendered(
        cliPath: String, stylesPath: String, buildPath: String, skill: DesignSkill = .adaptive
    ) throws -> String {
        try installedText(bundledTexts(), skill: skill, cliPath: cliPath, stylesPath: stylesPath, buildPath: buildPath)
    }

    /// Build.md rendered like the skill that names it, so it may call the CLI too. The committed
    /// `skills/rimlight/build.md` is this with `rimlight`, `styles` and `build.md`.
    static func renderedBuild(cliPath: String, stylesPath: String, buildPath: String) throws -> String {
        render(try buildSource(), cliPath: cliPath, stylesPath: stylesPath, buildPath: buildPath)
    }

    private static func installedText(
        _ texts: SkillSource.Texts, skill: DesignSkill, cliPath: String, stylesPath: String, buildPath: String
    ) throws -> String {
        let loaded = SkillSource.load(
            skill, texts: texts, cliPath: cliPath, stylesPath: stylesPath, buildPath: buildPath)
        // A file pick that fell back would install Adaptive while saying it installed the file.
        if let fallback = loaded.fallback { throw StoreError.notFound(fallback) }
        return loaded.prompt.text
    }

    /// The names `install-skill --style` takes: each bundled style's slug, then `adaptive` and `none`.
    public static var styleNames: [String] {
        DesignStyle.allCases.map(\.slug) + [SkillSource.storedAdaptive, SkillSource.storedNone]
    }

    /// The pick `install-skill --style name` installs, or nil when `name` is not in `styleNames`.
    public static func skill(styleName name: String) -> DesignSkill? {
        switch name {
        case SkillSource.storedAdaptive: DesignSkill.adaptive
        // Spelled out: a bare `.none` here would be the optional's nil.
        case SkillSource.storedNone: DesignSkill.none
        default: DesignStyle(rawValue: name).map(DesignSkill.style)
        }
    }

    /// The `--style` name that installs `skill`'s text, `adaptive` for the default; a file has none.
    public static func styleName(of skill: DesignSkill) -> String? {
        switch skill {
        case .adaptive: SkillSource.storedAdaptive
        case .none: SkillSource.storedNone
        case .style(let style): style.slug
        case .file: nil
        }
    }

    /// `source` with `{{RIMLIGHT_CLI}}` replaced by `cliPath`, shell-quoted when it needs it,
    /// `{{RIMLIGHT_STYLES}}` by `stylesPath` and `{{RIMLIGHT_BUILD}}` by `buildPath`, both as
    /// they are: the agent reads that folder and that file with its file tools, not a shell, so
    /// quotes would become part of the path. With no `buildPath` it is the bundled Build.md,
    /// looked up only when `source` names it.
    public static func render(
        _ source: String, cliPath: String, stylesPath: String, buildPath: String? = nil
    ) -> String {
        var text = source.replacingOccurrences(of: placeholder, with: shellQuoted(cliPath))
            .replacingOccurrences(of: stylesPlaceholder, with: stylesPath)
        if text.contains(buildPlaceholder) {
            // A bundle without Build.md fails `bundledTexts` first, so the bare name is a backstop.
            let path = buildPath ?? (try? buildFile().path) ?? buildFileName
            text = text.replacingOccurrences(of: buildPlaceholder, with: path)
        }
        return text
    }

    /// What build.md is called beside SKILL.md.
    static let buildFileName = "build.md"

    /// `<skillsDir>/rimlight/SKILL.md`.
    public static func installedURL(in skillsDir: URL = defaultSkillsDir) -> URL {
        skillsDir.appending(path: skillName, directoryHint: .isDirectory)
            .appending(path: "SKILL.md", directoryHint: .notDirectory)
    }

    /// `<skillsDir>/rimlight/styles`, the style files the installed skill reads.
    public static func installedStylesURL(in skillsDir: URL = defaultSkillsDir) -> URL {
        skillsDir.appending(path: skillName, directoryHint: .isDirectory)
            .appending(path: "styles", directoryHint: .isDirectory)
    }

    /// `<skillsDir>/rimlight/build.md`, the guide the installed skill reads before `rimlight build`.
    public static func installedBuildURL(in skillsDir: URL = defaultSkillsDir) -> URL {
        skillsDir.appending(path: skillName, directoryHint: .isDirectory)
            .appending(path: buildFileName, directoryHint: .notDirectory)
    }

    /// Writes the style files, as bundled, to `<skillsDir>/rimlight/styles/`, Build.md rendered
    /// to `<skillsDir>/rimlight/build.md`, then `skill` rendered to `<skillsDir>/rimlight/SKILL.md`,
    /// each only when it differs from what is there, then the record of which version, pick and
    /// command wrote them. Every pick gets all the style files and build.md. `harness` adds its
    /// note to SKILL.md; Claude Code's text is the app's. Returns whether it wrote the skill,
    /// build.md or a style; the record does not count.
    @discardableResult
    public static func install(
        cliPath: String, to skillsDir: URL = defaultSkillsDir, skill: DesignSkill = .adaptive,
        harness: SkillHarness = .claude
    ) throws -> Bool {
        let texts = try bundledTexts()
        let stylesDir = installedStylesURL(in: skillsDir)
        let buildURL = installedBuildURL(in: skillsDir)
        // Rendered first, so a pick that cannot load writes nothing.
        let skillText = harness.skillText(
            try installedText(
                texts, skill: skill, cliPath: cliPath, stylesPath: stylesDir.path, buildPath: buildURL.path))
        let buildText = try renderedBuild(cliPath: cliPath, stylesPath: stylesDir.path, buildPath: buildURL.path)
        var wrote = false
        for style in DesignStyle.allCases {
            guard let text = texts.styles[style] else { continue }
            let dest = stylesDir.appending(path: style.fileName, directoryHint: .notDirectory)
            if try writeIfChanged(Data(text.utf8), to: dest) { wrote = true }
        }
        // Before SKILL.md, so a skill that names build.md never lands without it.
        if try writeIfChanged(Data(buildText.utf8), to: buildURL) { wrote = true }
        if try writeIfChanged(Data(skillText.utf8), to: installedURL(in: skillsDir)) { wrote = true }
        // Written even when the text did not change, so a newer version with the same text
        // stops counting as a refresh to do.
        let record = SkillRecord(
            version: Rimlight.version, style: SkillRecord.styleName(of: skill), command: cliPath, installed: Date())
        if let old = Self.record(in: skillsDir), old.version == record.version, old.style == record.style,
            old.command == record.command
        {
            return wrote
        }
        try writeRecord(record, in: skillsDir)
        return wrote
    }

    private static func writeIfChanged(_ data: Data, to dest: URL) throws -> Bool {
        if let existing = try? Data(contentsOf: dest), existing == data { return false }
        let dir = dest.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw StoreError.io("Cannot create \(dir.path): \(error.localizedDescription)")
        }
        try AtomicFile.write(data, to: dest)
        return true
    }

    /// What the installed skill calls the CLI: plain `rimlight` when the `rimlight` a shell
    /// finds on `searchPath` is `executable` once symlinks are resolved, so a Homebrew upgrade
    /// keeps the skill working; else the standalone link when it points at `executable`, since
    /// an update removes the version folder behind it; else `executable`'s absolute path.
    public static func cliCommand(
        executable: URL, searchPath: String?,
        standaloneLink: URL = StandaloneInstall.link(prefix: StandaloneInstall.defaultPrefix)
    ) -> String {
        let mine = CurrentProcess.realPath(executable.path)
        if let mine, let found = CurrentProcess.lookup(commandName, searchPath: searchPath), found.path == mine {
            return commandName
        }
        if let mine, CurrentProcess.realPath(standaloneLink.path) == mine { return standaloneLink.path }
        return executable.path
    }

    /// `s` as one POSIX shell word, single-quoted only when it holds characters outside a safe set.
    public static func shellQuoted(_ s: String) -> String {
        let safe = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+@%:,=".unicodeScalars)
        if !s.isEmpty, s.unicodeScalars.allSatisfy(safe.contains) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}

public enum CurrentProcess {
    /// This process's executable, symlinks resolved. Unlike `Bundle.main.executableURL`, it is
    /// the CLI itself when the CLI runs from inside the app's Contents/MacOS.
    public static var executableURL: URL? {
        var size: UInt32 = 0
        _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size) + 1)
        guard _NSGetExecutablePath(&buffer, &size) == 0 else { return nil }
        guard let real = realpath(buffer, nil) else {
            let path = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            return URL(filePath: path, directoryHint: .notDirectory)
        }
        defer { free(real) }
        return URL(filePath: String(cString: real), directoryHint: .notDirectory)
    }

    /// The program a shell runs for `name`: the first executable regular file called `name` in
    /// `searchPath`'s absolute entries, symlinks resolved. Relative and empty entries depend on
    /// the shell's cwd and are skipped. One `stat` and one `access` per entry.
    public static func lookup(_ name: String, searchPath: String?) -> URL? {
        guard let searchPath, !name.isEmpty, !name.contains("/") else { return nil }
        for dir in searchPath.split(separator: ":") where dir.hasPrefix("/") {
            let candidate = (String(dir) as NSString).appendingPathComponent(name)
            var st = stat()
            guard stat(candidate, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, access(candidate, X_OK) == 0 else {
                continue
            }
            return realPath(candidate).map { URL(filePath: $0, directoryHint: .notDirectory) }
        }
        return nil
    }

    /// `path` with every symlink resolved, or nil when it does not exist.
    public static func realPath(_ path: String) -> String? {
        guard let real = realpath(path, nil) else { return nil }
        defer { free(real) }
        return String(cString: real)
    }
}
