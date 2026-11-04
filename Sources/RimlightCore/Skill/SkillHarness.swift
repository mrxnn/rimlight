import Foundation

/// The coding agents `install-skill` writes the skill for, each in its own skills folder.
/// Claude Code gets the text exactly as a chat in the app starts with it. Codex gets the same
/// text with `codexNote` after it, since the text was written for Claude Code's tools. OpenCode
/// needs no install of its own: it reads `~/.claude/skills`.
public enum SkillHarness: String, CaseIterable, Sendable {
    case claude
    case codex

    /// The name a person knows it by.
    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    /// `~/.claude/skills`, or `$CODEX_HOME/skills` (`~/.codex/skills`). Codex also reads
    /// `~/.agents/skills`, but other agents share that folder and the Codex note is for Codex.
    public func defaultSkillsDir(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        switch self {
        case .claude: SkillText.defaultSkillsDir
        case .codex:
            CodexImageGen.codexHome(environment: environment).appending(path: "skills", directoryHint: .isDirectory)
        }
    }

    /// What an install that names no harness writes for: Claude Code always, as before Codex
    /// had a copy, and Codex when its home folder exists, so a Mac without Codex gets no
    /// `~/.codex`. Not Codex when its skill folder is Claude Code's through a link.
    public static func defaults(environment: [String: String] = ProcessInfo.processInfo.environment) -> [SkillHarness] {
        var isDirectory: ObjCBool = false
        let home = CodexImageGen.codexHome(environment: environment).path
        let codex =
            FileManager.default.fileExists(atPath: home, isDirectory: &isDirectory) && isDirectory.boolValue
            && !isClaudeFolder(SkillHarness.codex.defaultSkillsDir(environment: environment))
        return codex ? [.claude, .codex] : [.claude]
    }

    /// Whether `skillsDir`'s `rimlight` folder is `claudeSkillsDir`'s once links are resolved,
    /// as when `~/.codex/skills/rimlight` or `~/.codex/skills` links to Claude Code's. Codex
    /// reads such a folder already, and writing Codex's copy there would change Claude Code's.
    public static func isClaudeFolder(_ skillsDir: URL, claudeSkillsDir: URL = SkillText.defaultSkillsDir) -> Bool {
        func resolved(_ dir: URL) -> String? {
            let folder = dir.appending(path: SkillText.skillName, directoryHint: .isDirectory).path
            if let real = CurrentProcess.realPath(folder) { return real }
            return CurrentProcess.realPath(dir.path).map { ($0 as NSString).appendingPathComponent(SkillText.skillName) }
        }
        guard let mine = resolved(skillsDir), let claude = resolved(claudeSkillsDir) else { return false }
        return mine == claude
    }

    /// What follows the skill's text in this agent's SKILL.md; nil leaves the text as it is.
    public var note: String? {
        switch self {
        case .claude: nil
        case .codex: Self.codexNote
        }
    }

    /// The installed skill's text for this agent: `text`, then the note.
    public func skillText(_ text: String) -> String {
        guard let note else { return text }
        return SkillText.compose(text, sections: [note])
    }

    /// Codex in a terminal, where the app's Codex driver is not there to sandbox, gate or ask:
    /// the sandbox blocks the network and writes outside the folder, and there is no
    /// `AskUserQuestion`. The app's chats get their own note from the app instead.
    public static let codexNote = """
        ## Codex

        This skill was written for Claude Code. In Codex:

        - Run every `rimlight` command outside the sandbox, asking for escalated permissions when
          you need them. It renders over the network, and with Codex as the image model it writes
          to `~/.codex`; the sandbox blocks both, sometimes without an error.
        - Run each `rimlight` command on its own, with nothing chained before or after it.
        - `run_in_background`, the Bash timeout and Monitor, here and in build.md, are Claude
          Code's. Give each `rimlight generate` and `rimlight build` a timeout of at least
          600000 ms and wait for it to finish. Start several renders together when you can run
          commands side by side, else one after another.
        - To look at an image, use `view_image` with its absolute path. Never `open` a file or
          launch an app.
        - Where the skill says `AskUserQuestion` and you have no tool by that name, ask in plain
          text: the options as a numbered list, then wait for the reply.
        """
}
