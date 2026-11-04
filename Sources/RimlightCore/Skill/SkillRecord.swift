import Foundation

/// `<skillsDir>/rimlight/.install.json`: which `rimlight` wrote the installed skill, with which
/// pick and command. `install-skill` keeps the pick when it runs again without `--style`, and a
/// newer `rimlight` rewrites a skill an older one wrote, so `brew upgrade` updates the skill too.
public struct SkillRecord: Codable, Hashable, Sendable {
    public var version: String
    /// The `--style` name: a style's slug, `adaptive` or `none`; or `file:<path>`.
    public var style: String
    /// What the skill calls the CLI: `rimlight`, or an absolute path.
    public var command: String
    public var installed: Date

    public init(version: String, style: String, command: String, installed: Date) {
        self.version = version
        self.style = style
        self.command = command
        self.installed = installed
    }

    static let filePrefix = "file:"

    /// The pick `style` names, or nil for a name this build does not know.
    public var skill: DesignSkill? {
        if style.hasPrefix(Self.filePrefix) {
            return DesignSkill(path: String(style.dropFirst(Self.filePrefix.count)))
        }
        return SkillText.skill(styleName: style)
    }

    /// The name a record keeps for `skill`.
    public static func styleName(of skill: DesignSkill) -> String {
        if case .file(let url) = skill { return filePrefix + url.path }
        return SkillText.styleName(of: skill) ?? SkillSource.storedAdaptive
    }
}

extension SkillText {
    /// `<skillsDir>/rimlight/.install.json`.
    public static func recordURL(in skillsDir: URL = defaultSkillsDir) -> URL {
        skillsDir.appending(path: skillName, directoryHint: .isDirectory)
            .appending(path: ".install.json", directoryHint: .notDirectory)
    }

    /// The record beside the installed skill; nil when there is none or it does not decode,
    /// as for a skill written before records existed.
    public static func record(in skillsDir: URL = defaultSkillsDir) -> SkillRecord? {
        guard let data = try? Data(contentsOf: recordURL(in: skillsDir)) else { return nil }
        return try? StateCoding.decoder().decode(SkillRecord.self, from: data)
    }

    static func writeRecord(_ record: SkillRecord, in skillsDir: URL) throws {
        try AtomicFile.write(try StateCoding.encoder().encode(record), to: recordURL(in: skillsDir))
    }

    /// What `install-skill` installs when it is given no `--style`: the recorded pick, else
    /// Adaptive.
    public static func defaultPick(in skillsDir: URL = defaultSkillsDir) -> DesignSkill {
        record(in: skillsDir)?.skill ?? .adaptive
    }

    /// Rewrites the installed skill with this build's text when a `rimlight` older than this one
    /// wrote it, keeping its pick. Only the copy `searchPath` runs does this, so a shadowed copy
    /// never points the skill at itself. Nothing happens without a record, an installed
    /// SKILL.md, or a pick this build knows. `harness` is the agent the folder is for. Returns
    /// whether it rewrote. One small read when there is nothing to do.
    @discardableResult
    public static func refreshIfOlder(
        executable: URL, searchPath: String?, skillsDir: URL = defaultSkillsDir, harness: SkillHarness = .claude
    ) throws -> Bool {
        guard let record = record(in: skillsDir), let recorded = RimlightVersion(record.version),
            recorded < RimlightVersion.current, let skill = record.skill,
            FileManager.default.fileExists(atPath: installedURL(in: skillsDir).path)
        else { return false }
        let command = cliCommand(executable: executable, searchPath: searchPath)
        guard command == commandName else { return false }
        try install(cliPath: command, to: skillsDir, skill: skill, harness: harness)
        return true
    }
}
