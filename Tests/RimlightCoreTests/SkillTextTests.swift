import Foundation
import Testing

@testable import RimlightCore

@Suite struct SkillTextTests {
    @Test func sourcesAreBundled() throws {
        let source = try SkillText.source()
        #expect(source.hasPrefix("---\nname: rimlight\n"))
        #expect(source.contains(SkillText.placeholder))
        // The instructions carry the frontmatter; the design skill is appended under them.
        let design = try SkillText.designSource()
        #expect(design.hasPrefix("## "))
        #expect(SkillSource.strippingFrontmatter(design) == design)
        #expect(try SkillText.adaptiveSource().contains(SkillText.stylesPlaceholder))
        // The instructions send the agent to build.md before `rimlight build`.
        #expect(source.contains(SkillText.buildPlaceholder))
        let build = try SkillText.buildSource()
        #expect(build.hasPrefix("# "))
        #expect(try SkillText.buildFile().lastPathComponent == "Build.md")
        #expect(try String(contentsOf: SkillText.buildFile(), encoding: .utf8) == build)
    }

    /// Every style is a file in the bundled Styles folder. The agent reads them there as they
    /// are, so none may carry frontmatter or a placeholder.
    @Test func stylesAreBundled() throws {
        let dir = try SkillText.stylesDirectory()
        #expect(dir.lastPathComponent == "Styles")
        let texts = try SkillText.bundledTexts()
        #expect(Set(texts.styles.keys) == Set(DesignStyle.allCases))
        for style in DesignStyle.allCases {
            let text = try #require(texts.styles[style])
            #expect(text.contains { !$0.isWhitespace }, "\(style.fileName) is blank")
            #expect(SkillSource.strippingFrontmatter(text) == text, "\(style.fileName) has frontmatter")
            #expect(!text.contains("{{RIMLIGHT_"), "\(style.fileName) has a placeholder")
            let onDisk = try String(
                contentsOf: dir.appending(path: style.fileName, directoryHint: .notDirectory), encoding: .utf8)
            #expect(onDisk == text)
        }
    }

    /// What `install-skill` writes: the instructions, Design.md, then the index of the styles,
    /// pointed at the installed styles folder and build.md.
    @Test func placeholderReplaced() throws {
        let cli = "/Applications/Rimlight.app/Contents/MacOS/rimlight"
        let skills = URL(filePath: "/Users/me/.claude/skills", directoryHint: .isDirectory)
        let text = try SkillText.rendered(cliPath: cli, skillsDir: skills)
        #expect(!text.contains(SkillText.placeholder))
        #expect(!text.contains(SkillText.stylesPlaceholder))
        #expect(!text.contains(SkillText.buildPlaceholder))
        #expect(text.contains("The command is `\(cli)`."))
        #expect(text.contains("Read\n`/Users/me/.claude/skills/rimlight/build.md` first"))
        let instructions = try SkillText.source()
        let texts = try SkillText.bundledTexts()
        let composed = SkillText.compose(instructions, sections: [texts.design, texts.adaptive])
        #expect(
            text
                == SkillText.render(
                    composed, cliPath: cli, stylesPath: "/Users/me/.claude/skills/rimlight/styles",
                    buildPath: "/Users/me/.claude/skills/rimlight/build.md"))
        let head = SkillText.render(
            instructions, cliPath: cli, stylesPath: "/s", buildPath: "/Users/me/.claude/skills/rimlight/build.md"
        ).trimmingCharacters(in: .newlines)
        #expect(text.hasPrefix(head + "\n\n## "))
        #expect(
            SkillText.render("run {{RIMLIGHT_CLI}} now", cliPath: "/My Apps/rim'light", stylesPath: "/s")
                == #"run '/My Apps/rim'\''light' now"#)
    }

    @Test func installWritesOnceThenNoOp() throws {
        try withTempDir { dir in
            let skills = dir.appending(path: "skills", directoryHint: .isDirectory)
            #expect(try SkillText.install(cliPath: "/a/rimlight", to: skills))
            let installed = SkillText.installedURL(in: skills)
            #expect(installed.path.hasSuffix("skills/rimlight/SKILL.md"))
            let stylesDir = SkillText.installedStylesURL(in: skills)
            #expect(stylesDir.path.hasSuffix("skills/rimlight/styles"))
            let stamp = try #require(FileStamp.of(installed))
            #expect(
                try String(contentsOf: installed, encoding: .utf8)
                    == SkillText.rendered(cliPath: "/a/rimlight", skillsDir: skills))

            // The styles folder holds the eight files as bundled, and nothing else.
            let texts = try SkillText.bundledTexts()
            let listed = try FileManager.default.contentsOfDirectory(atPath: stylesDir.path).sorted()
            #expect(listed == DesignStyle.allCases.map(\.fileName).sorted())
            let mascot = stylesDir.appending(path: DesignStyle.mascot.fileName, directoryHint: .notDirectory)
            for style in DesignStyle.allCases {
                let file = stylesDir.appending(path: style.fileName, directoryHint: .notDirectory)
                #expect(try String(contentsOf: file, encoding: .utf8) == texts.styles[style])
            }
            let mascotStamp = try #require(FileStamp.of(mascot))

            // build.md sits beside SKILL.md, rendered like it.
            let build = SkillText.installedBuildURL(in: skills)
            #expect(build.path.hasSuffix("skills/rimlight/build.md"))
            #expect(
                try String(contentsOf: build, encoding: .utf8)
                    == SkillText.render(
                        SkillText.buildSource(), cliPath: "/a/rimlight", stylesPath: stylesDir.path, buildPath: build.path))
            let buildStamp = try #require(FileStamp.of(build))

            #expect(try SkillText.install(cliPath: "/a/rimlight", to: skills) == false)
            #expect(FileStamp.of(installed) == stamp)
            #expect(FileStamp.of(mascot) == mascotStamp)
            #expect(FileStamp.of(build) == buildStamp)

            // A build.md removed on disk is put back, and that counts as a write.
            try FileManager.default.removeItem(at: build)
            #expect(try SkillText.install(cliPath: "/a/rimlight", to: skills))
            #expect(FileManager.default.fileExists(atPath: build.path))
            #expect(FileStamp.of(installed) == stamp)

            // A style edited or removed on disk is put back, and that counts as a write.
            try Data("stale".utf8).write(to: mascot)
            try FileManager.default.removeItem(
                at: stylesDir.appending(path: DesignStyle.monoMark.fileName, directoryHint: .notDirectory))
            #expect(try SkillText.install(cliPath: "/a/rimlight", to: skills))
            #expect(try String(contentsOf: mascot, encoding: .utf8) == texts.styles[.mascot])
            #expect(try FileManager.default.contentsOfDirectory(atPath: stylesDir.path).count == DesignStyle.allCases.count)
            #expect(FileStamp.of(installed) == stamp)

            #expect(try SkillText.install(cliPath: "/b/rimlight", to: skills))
            #expect(try String(contentsOf: installed, encoding: .utf8).contains("`/b/rimlight`"))
        }
    }

    /// With no pick, the installed skill is what a chat on the default Adaptive skill runs, with
    /// the styles it points at installed beside it.
    @Test func installedSkillIsTheDefault() throws {
        let cli = "/a/rimlight"
        let texts = try SkillText.bundledTexts()
        try withTempDir { dir in
            let skills = dir.appending(path: "my skills", directoryHint: .isDirectory)
            let stylesPath = SkillText.installedStylesURL(in: skills).path
            let buildPath = SkillText.installedBuildURL(in: skills).path
            func chat(_ skill: DesignSkill) -> String {
                SkillSource.load(skill, texts: texts, cliPath: cli, stylesPath: stylesPath, buildPath: buildPath)
                    .prompt.text
            }
            try SkillText.install(cliPath: cli, to: skills)
            let installed = try String(contentsOf: SkillText.installedURL(in: skills), encoding: .utf8)
            #expect(installed == chat(.adaptive))
            #expect(installed != chat(.none))
            #expect(installed != chat(.style(.soft3DObject)))
            // It finds every style it names in the installed folder.
            #expect(installed.contains("`\(stylesPath)`"))
            for style in DesignStyle.allCases {
                #expect(FileManager.default.fileExists(atPath: stylesPath + "/" + style.fileName))
            }
            // And the build guide it names.
            #expect(installed.contains("`\(buildPath)`"))
            #expect(FileManager.default.fileExists(atPath: buildPath))
        }
    }

    /// `install-skill --style` takes the bundled styles by file name, then `adaptive` and `none`,
    /// and every name it takes is the one the CLI reports back.
    @Test func styleNamesAreTheBundledStyles() throws {
        let names = SkillText.styleNames
        let bundled = try FileManager.default.contentsOfDirectory(atPath: SkillText.stylesDirectory().path)
            .filter { $0.hasSuffix(".md") }.map { String($0.dropLast(3)) }
        #expect(Set(names.dropLast(2)) == Set(bundled))
        #expect(names == DesignStyle.allCases.map(\.slug) + ["adaptive", "none"])
        for name in names {
            let skill = try #require(SkillText.skill(styleName: name), "\(name) is not taken")
            #expect(SkillText.styleName(of: skill) == name)
        }
        #expect(SkillText.skill(styleName: "adaptive") == .adaptive)
        #expect(SkillText.skill(styleName: "none") == DesignSkill.none)
        #expect(SkillText.skill(styleName: "mono-mark") == .style(.monoMark))
        #expect(SkillText.styleName(of: .adaptive) == "adaptive")
        #expect(SkillText.styleName(of: DesignSkill(path: "/tmp/Mine.md")) == nil)
        for unknown in ["", "bogus", "rimlight", "Mono-Mark", "mono-mark.md", "style:mono-mark", "Adaptive"] {
            #expect(SkillText.skill(styleName: unknown) == nil, "\(unknown) is taken")
        }
    }

    /// A style pick composes like the default, with that style's file as the tail.
    @Test func styleRenderEndsWithTheStyle() throws {
        let cli = "/a/rimlight"
        let skills = URL(filePath: "/Users/me/.claude/skills", directoryHint: .isDirectory)
        let stylesPath = SkillText.installedStylesURL(in: skills).path
        let buildPath = SkillText.installedBuildURL(in: skills).path
        let texts = try SkillText.bundledTexts()
        let text = try SkillText.rendered(cliPath: cli, skillsDir: skills, skill: .style(.monoMark))
        let composed = SkillText.compose(texts.instructions, sections: [texts.design, texts.styles[.monoMark]])
        #expect(text == SkillText.render(composed, cliPath: cli, stylesPath: stylesPath, buildPath: buildPath))
        let monoMark = try #require(texts.styles[.monoMark]).trimmingCharacters(in: .whitespacesAndNewlines)
        let design = texts.design.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(text.hasSuffix("\n\n" + design + "\n\n" + monoMark + "\n"))
        #expect(text != (try SkillText.rendered(cliPath: cli, skillsDir: skills)))
        // The soft 3D object style, the old default, is a pick like the others.
        let soft3D = try SkillText.rendered(cliPath: cli, skillsDir: skills, skill: .style(.soft3DObject))
        let soft3DComposed = SkillText.compose(texts.instructions, sections: [texts.design, texts.styles[.soft3DObject]])
        #expect(soft3D == SkillText.render(soft3DComposed, cliPath: cli, stylesPath: stylesPath, buildPath: buildPath))
        #expect(soft3D != (try SkillText.rendered(cliPath: cli, skillsDir: skills)))
    }

    /// The default is Adaptive: it points the agent at the styles installed beside the skill
    /// and lists all eight of them by file.
    @Test func defaultRenderNamesTheInstalledStyles() throws {
        let skills = URL(filePath: "/Users/me/my skills", directoryHint: .isDirectory)
        let stylesPath = SkillText.installedStylesURL(in: skills).path
        #expect(stylesPath == "/Users/me/my skills/rimlight/styles")
        let text = try SkillText.rendered(cliPath: "/a/rimlight", skillsDir: skills)
        #expect(!text.contains(SkillText.stylesPlaceholder))
        #expect(!text.contains(SkillText.placeholder))
        #expect(text.contains("`\(stylesPath)`"))
        for style in DesignStyle.allCases {
            #expect(text.contains("\n- `\(style.fileName)`: "), "\(style.fileName) is not listed")
        }
        let texts = try SkillText.bundledTexts()
        let composed = SkillText.compose(texts.instructions, sections: [texts.design, texts.adaptive])
        let buildPath = SkillText.installedBuildURL(in: skills).path
        #expect(buildPath == "/Users/me/my skills/rimlight/build.md")
        #expect(text.contains("`\(buildPath)`"))
        #expect(
            text == SkillText.render(composed, cliPath: "/a/rimlight", stylesPath: stylesPath, buildPath: buildPath))
    }

    /// `install-skill --style adaptive` is the same bytes as no flag.
    @Test func defaultIsStyleAdaptive() throws {
        let cli = "/a/rimlight"
        let named = try #require(SkillText.skill(styleName: "adaptive"))
        try withTempDir { dir in
            let skills = dir.appending(path: "skills", directoryHint: .isDirectory)
            let byDefault = try SkillText.rendered(cliPath: cli, skillsDir: skills)
            #expect(try SkillText.rendered(cliPath: cli, skillsDir: skills, skill: named) == byDefault)
            #expect(try SkillText.install(cliPath: cli, to: skills))
            #expect(try SkillText.install(cliPath: cli, to: skills, skill: named) == false)
        }
    }

    /// None is the instructions alone: no design process, no style.
    @Test func noneRenderIsTheInstructions() throws {
        let skills = URL(filePath: "/Users/me/.claude/skills", directoryHint: .isDirectory)
        let text = try SkillText.rendered(cliPath: "/a/rimlight", skillsDir: skills, skill: .none)
        let instructions = try SkillText.source()
        #expect(
            text
                == SkillText.render(
                    instructions, cliPath: "/a/rimlight", stylesPath: "/unused",
                    buildPath: SkillText.installedBuildURL(in: skills).path))
        #expect(text.hasPrefix("---\nname: rimlight\n"))
        #expect(!text.contains("## Designing icons"))
        #expect(try SkillText.designSource().hasPrefix("## Designing icons"))
    }

    /// Every pick gets all eight style files and build.md; switching picks rewrites only
    /// SKILL.md. A file pick that cannot load writes nothing rather than installing Adaptive in
    /// its place.
    @Test func installWritesThePick() throws {
        let cli = "/a/rimlight"
        try withTempDir { dir in
            let skills = dir.appending(path: "skills", directoryHint: .isDirectory)
            let installed = SkillText.installedURL(in: skills)
            let stylesDir = SkillText.installedStylesURL(in: skills)

            let missing = dir.appending(path: "Missing.md", directoryHint: .notDirectory)
            #expect(throws: StoreError.self) {
                try SkillText.install(cliPath: cli, to: skills, skill: DesignSkill(path: missing.path))
            }
            #expect(!FileManager.default.fileExists(atPath: skills.path))

            #expect(try SkillText.install(cliPath: cli, to: skills, skill: .none))
            #expect(
                try String(contentsOf: installed, encoding: .utf8)
                    == SkillText.rendered(cliPath: cli, skillsDir: skills, skill: .none))
            let listed = try FileManager.default.contentsOfDirectory(atPath: stylesDir.path).sorted()
            #expect(listed == DesignStyle.allCases.map(\.fileName).sorted())
            let mascot = stylesDir.appending(path: DesignStyle.mascot.fileName, directoryHint: .notDirectory)
            let mascotStamp = try #require(FileStamp.of(mascot))
            let build = SkillText.installedBuildURL(in: skills)
            let buildStamp = try #require(FileStamp.of(build), "None got no build.md")

            #expect(try SkillText.install(cliPath: cli, to: skills, skill: .style(.monoMark)))
            #expect(
                try String(contentsOf: installed, encoding: .utf8)
                    == SkillText.rendered(cliPath: cli, skillsDir: skills, skill: .style(.monoMark)))
            #expect(FileStamp.of(mascot) == mascotStamp)
            #expect(FileStamp.of(build) == buildStamp)
            #expect(try SkillText.install(cliPath: cli, to: skills, skill: .style(.monoMark)) == false)

            // Back to the default.
            #expect(try SkillText.install(cliPath: cli, to: skills))
            #expect(
                try String(contentsOf: installed, encoding: .utf8)
                    == SkillText.rendered(cliPath: cli, skillsDir: skills))
        }
    }

    /// The skill says plain `rimlight` only when that is the binary a shell finds first.
    @Test func cliCommandIsRimlightWhenPathFindsThisBinary() throws {
        let exe = try #require(CurrentProcess.executableURL)
        try withTempDir { dir in
            let fm = FileManager.default
            let bin = dir.appending(path: "bin", directoryHint: .isDirectory)
            let other = dir.appending(path: "other", directoryHint: .isDirectory)
            let folder = dir.appending(path: "folder", directoryHint: .isDirectory)
            for d in [bin, other, folder.appending(path: "rimlight")] {
                try fm.createDirectory(at: d, withIntermediateDirectories: true)
            }
            // A Homebrew-style link to the running binary.
            try fm.createSymbolicLink(atPath: bin.path + "/rimlight", withDestinationPath: exe.path)
            #expect(CurrentProcess.lookup("rimlight", searchPath: bin.path)?.path == exe.path)
            // Missing, relative and empty entries, and a folder named rimlight, are passed over.
            let path = "/nonexistent::bin:\(folder.path):\(bin.path)"
            #expect(SkillText.cliCommand(executable: exe, searchPath: path) == "rimlight")

            // Another rimlight first on PATH is what a shell would run: keep the absolute path.
            let script = other.path + "/rimlight"
            try Data("#!/bin/sh\n".utf8).write(to: URL(filePath: script))
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script)
            #expect(SkillText.cliCommand(executable: exe, searchPath: "\(other.path):\(bin.path)") == exe.path)
            // Unless it cannot run.
            try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: script)
            #expect(SkillText.cliCommand(executable: exe, searchPath: "\(other.path):\(bin.path)") == "rimlight")

            // No rimlight on PATH, or no PATH.
            #expect(SkillText.cliCommand(executable: exe, searchPath: other.path) == exe.path)
            #expect(SkillText.cliCommand(executable: exe, searchPath: "") == exe.path)
            #expect(SkillText.cliCommand(executable: exe, searchPath: nil) == exe.path)

            // Off PATH, a standalone link to this binary is named instead of the version folder.
            let link = dir.appending(path: "local/bin/rimlight", directoryHint: .notDirectory)
            try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(atPath: link.path, withDestinationPath: exe.path)
            #expect(SkillText.cliCommand(executable: exe, searchPath: other.path, standaloneLink: link) == link.path)
            // PATH still wins when it runs this binary.
            #expect(SkillText.cliCommand(executable: exe, searchPath: bin.path, standaloneLink: link) == "rimlight")
        }
    }
}
