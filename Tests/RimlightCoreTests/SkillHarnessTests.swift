import Foundation
import Testing

@testable import RimlightCore

@Suite struct SkillHarnessTests {
    /// Claude Code's skill is the app's text as it is: the harness adds nothing.
    @Test func claudeTextIsUnchanged() throws {
        #expect(SkillHarness.claude.note == nil)
        let text = try SkillText.rendered(cliPath: "rimlight", stylesPath: "styles", buildPath: "build.md")
        #expect(SkillHarness.claude.skillText(text) == text)
    }

    /// For every pick, Codex's SKILL.md is Claude Code's text for the same folder with the Codex
    /// note after it, and build.md and the styles are the same files.
    @Test func codexInstallIsClaudeTextThenTheNote() throws {
        try withTempDir { dir in
            for skill in DesignSkill.builtIn {
                let name = SkillRecord.styleName(of: skill)
                let claude = dir.appending(path: "claude-\(name)", directoryHint: .isDirectory)
                let codex = dir.appending(path: "codex-\(name)", directoryHint: .isDirectory)
                try SkillText.install(cliPath: "rimlight", to: claude, skill: skill)
                try SkillText.install(cliPath: "rimlight", to: codex, skill: skill, harness: .codex)

                let claudeText = try String(contentsOf: SkillText.installedURL(in: claude), encoding: .utf8)
                #expect(claudeText == (try SkillText.rendered(cliPath: "rimlight", skillsDir: claude, skill: skill)))
                #expect(!claudeText.contains("## Codex\n"))

                let codexText = try String(contentsOf: SkillText.installedURL(in: codex), encoding: .utf8)
                let base = try SkillText.rendered(cliPath: "rimlight", skillsDir: codex, skill: skill)
                #expect(codexText.hasPrefix(base.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n## Codex\n"))
                #expect(codexText.hasSuffix(SkillHarness.codexNote + "\n"))
                #expect(codexText.hasPrefix("---\nname: rimlight\n"))

                let claudeBuild = try String(contentsOf: SkillText.installedBuildURL(in: claude), encoding: .utf8)
                let codexBuild = try String(contentsOf: SkillText.installedBuildURL(in: codex), encoding: .utf8)
                #expect(
                    codexBuild
                        == claudeBuild.replacingOccurrences(of: claude.path, with: codex.path))
                for style in DesignStyle.allCases {
                    let a = SkillText.installedStylesURL(in: claude).appending(path: style.fileName)
                    let b = SkillText.installedStylesURL(in: codex).appending(path: style.fileName)
                    #expect(try Data(contentsOf: a) == Data(contentsOf: b))
                }

                // A second install changes nothing.
                #expect(try !SkillText.install(cliPath: "rimlight", to: codex, skill: skill, harness: .codex))
            }
        }
    }

    /// Codex's folder is `$CODEX_HOME/skills`, and an install that names no harness writes for
    /// Codex only when that home exists.
    @Test func codexFollowsItsHome() throws {
        try withTempDir { dir in
            let home = dir.appending(path: "codex-home", directoryHint: .isDirectory)
            let env = ["CODEX_HOME": home.path]
            #expect(SkillHarness.codex.defaultSkillsDir(environment: env).path == home.appending(path: "skills").path)
            #expect(SkillHarness.defaults(environment: env) == [.claude])

            try Data().write(to: home)
            #expect(SkillHarness.defaults(environment: env) == [.claude], "a file is not a Codex home")
            try FileManager.default.removeItem(at: home)

            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            #expect(SkillHarness.defaults(environment: env) == [.claude, .codex])
        }
        #expect(SkillHarness.claude.defaultSkillsDir() == SkillText.defaultSkillsDir)
    }

    /// A Codex folder linked to Claude Code's, whole or just `rimlight/`, is Claude Code's, so a
    /// default install leaves Codex out rather than add the Codex note to Claude Code's skill.
    @Test func aLinkedCodexFolderIsClaudeCodes() throws {
        try withTempDir { dir in
            let fm = FileManager.default
            let claude = dir.appending(path: "claude/skills", directoryHint: .isDirectory)
            try SkillText.install(cliPath: "rimlight", to: claude)

            // Separate folders, the folder missing or present.
            let own = dir.appending(path: "own/skills", directoryHint: .isDirectory)
            #expect(!SkillHarness.isClaudeFolder(own, claudeSkillsDir: claude))
            try SkillText.install(cliPath: "rimlight", to: own, harness: .codex)
            #expect(!SkillHarness.isClaudeFolder(own, claudeSkillsDir: claude))

            // The whole skills folder linked.
            let linkedDir = dir.appending(path: "a/skills", directoryHint: .isDirectory)
            try fm.createDirectory(at: linkedDir.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: linkedDir, withDestinationURL: claude)
            #expect(SkillHarness.isClaudeFolder(linkedDir, claudeSkillsDir: claude))

            // Only rimlight/ linked.
            let linkedSkill = dir.appending(path: "b/skills", directoryHint: .isDirectory)
            try fm.createDirectory(at: linkedSkill, withIntermediateDirectories: true)
            try fm.createSymbolicLink(
                at: linkedSkill.appending(path: SkillText.skillName),
                withDestinationURL: claude.appending(path: SkillText.skillName))
            #expect(SkillHarness.isClaudeFolder(linkedSkill, claudeSkillsDir: claude))

            // Codex's home is set up, but its skills folder is Claude Code's.
            let home = dir.appending(path: "codex-home", directoryHint: .isDirectory)
            try fm.createDirectory(at: home, withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: home.appending(path: "skills"), withDestinationURL: SkillText.defaultSkillsDir)
            #expect(SkillHarness.defaults(environment: ["CODEX_HOME": home.path]) == [.claude])
        }
    }

    /// A newer rimlight rewrites an older Codex skill with the note still after it.
    @Test func refreshKeepsTheCodexNote() throws {
        try withTempDir { dir in
            let fm = FileManager.default
            let skills = dir.appending(path: "skills", directoryHint: .isDirectory)
            let real = dir.appending(path: "real", directoryHint: .isDirectory)
            let bin = dir.appending(path: "bin", directoryHint: .isDirectory)
            try fm.createDirectory(at: real, withIntermediateDirectories: true)
            try fm.createDirectory(at: bin, withIntermediateDirectories: true)
            let exe = real.appending(path: "rimlight")
            try Data("#!/bin/sh\necho rimlight 0.0.0\n".utf8).write(to: exe)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
            try fm.createSymbolicLink(at: bin.appending(path: "rimlight"), withDestinationURL: exe)

            try SkillText.install(cliPath: "rimlight", to: skills, skill: .style(.mascot), harness: .codex)
            let fresh = try String(contentsOf: SkillText.installedURL(in: skills), encoding: .utf8)
            var record = try #require(SkillText.record(in: skills))
            record.version = "0.0.1"
            try SkillText.writeRecord(record, in: skills)
            try Data("old text\n".utf8).write(to: SkillText.installedURL(in: skills))

            #expect(try SkillText.refreshIfOlder(executable: exe, searchPath: bin.path, skillsDir: skills, harness: .codex))
            #expect(try String(contentsOf: SkillText.installedURL(in: skills), encoding: .utf8) == fresh)
            #expect(SkillText.record(in: skills)?.style == "mascot")
            #expect(SkillText.record(in: skills)?.version == Rimlight.version)
        }
    }
}
