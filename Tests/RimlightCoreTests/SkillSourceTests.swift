import Foundation
import Testing

@testable import RimlightCore

@Suite struct SkillSourceTests {
    /// The pill shows a short name; it must stay short and tell the styles apart.
    @Test func shortNamesAreShortAndDistinct() {
        let names = DesignStyle.allCases.map(\.shortName)
        #expect(Set(names).count == names.count)
        #expect(names.allSatisfy { $0.count <= 10 })
    }

    private static let instructions = "---\nname: rimlight\n---\nThe command is `{{RIMLIGHT_CLI}}`.\n"
    private static let design = "## Designing icons\n\nOne idea per icon.\n"
    private static let adaptive = "## Picking a style\n\nRead the styles in `{{RIMLIGHT_STYLES}}`.\n"
    private static func styleText(_ style: DesignStyle) -> String { "\n### \(style.name)\n\nThe \(style.slug) standard.\n\n" }
    private static let texts = SkillSource.Texts(
        instructions: instructions, design: design, adaptive: adaptive,
        styles: Dictionary(uniqueKeysWithValues: DesignStyle.allCases.map { ($0, styleText($0)) }))
    private static let builtInNames = [
        "Adaptive", "None", "Soft 3D object", "Glass and chrome", "Lettermark and wordmark", "Mono mark",
        "Mascot", "Hardware and skeuomorph", "System glyph", "Scene and collage",
    ]

    private func write(_ text: String, _ name: String, in dir: URL) throws -> URL {
        let url = dir.appending(path: name, directoryHint: .notDirectory)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func load(
        _ skill: DesignSkill, texts: SkillSource.Texts = SkillSourceTests.texts, cliPath: String = "/a/rimlight", stylesPath: String = "/b/Styles"
    ) -> SkillSource.Loaded {
        SkillSource.load(skill, texts: texts, cliPath: cliPath, stylesPath: stylesPath)
    }

    /// The instructions with the CLI rendered, then the design process, as every pick but None
    /// starts.
    private static let head =
        "---\nname: rimlight\n---\nThe command is `/a/rimlight`.\n\n## Designing icons\n\nOne idea per icon.\n\n"

    /// The Adaptive skill as `load` composes it, to compare fallbacks with.
    private var adaptive: PromptText {
        PromptText(skill: .adaptive, text: Self.head + "## Picking a style\n\nRead the styles in `/b/Styles`.\n")
    }

    @Test func emptyOrMissingFolderListsTheBuiltInSkills() throws {
        try withTempDir { dir in
            #expect(SkillSource.skills(in: dir) == DesignSkill.builtIn)
            #expect(SkillSource.skills(in: dir.appending(path: "Nope", directoryHint: .isDirectory)) == DesignSkill.builtIn)
        }
        #expect(DesignSkill.builtIn.map(\.name) == Self.builtInNames)
        #expect(DesignSkill.builtIn.prefix(2) == [.adaptive, .none])
        #expect(DesignSkill.builtIn.dropFirst(2).compactMap(\.style) == DesignStyle.allCases)
        #expect(DesignSkill.builtIn.allSatisfy { $0.path == nil })
        #expect(Set(DesignSkill.builtIn.map(\.id)).count == DesignSkill.builtIn.count)
    }

    @Test func listsMarkdownFilesByNameIgnoringCase() throws {
        try withTempDir { dir in
            let beta = try write("b", "beta.md", in: dir)
            let alpha = try write("a", "Alpha.md", in: dir)
            _ = try write("notes", "notes.txt", in: dir)
            _ = try write("lock", ".#alpha.md", in: dir)
            try FileManager.default.createDirectory(
                at: dir.appending(path: "folder.md", directoryHint: .isDirectory), withIntermediateDirectories: false)

            let skills = SkillSource.skills(in: dir)
            #expect(skills.map(\.name) == Self.builtInNames + ["Alpha", "beta"])
            #expect(Array(skills.prefix(DesignSkill.builtIn.count)) == DesignSkill.builtIn)
            #expect(skills[0] == .adaptive && skills[0].path == nil)
            #expect(skills.dropFirst(DesignSkill.builtIn.count).map(\.path) == [alpha.path, beta.path])
            #expect(skills.dropFirst(DesignSkill.builtIn.count).allSatisfy { $0.style == nil && $0 != .adaptive })
        }
    }

    @Test func followsSymlinkedFolderAndFiles() throws {
        try withTempDir { dir in
            let repo = dir.appending(path: "repo", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: false)
            _ = try write("terse", "terse.md", in: repo)
            let elsewhere = try write("long", "long-form.md", in: dir)
            try FileManager.default.createSymbolicLink(
                at: repo.appending(path: "linked.md", directoryHint: .notDirectory), withDestinationURL: elsewhere)
            try FileManager.default.createSymbolicLink(
                at: repo.appending(path: "broken.md", directoryHint: .notDirectory),
                withDestinationURL: dir.appending(path: "gone.md", directoryHint: .notDirectory))
            let folder = dir.appending(path: "Skills", directoryHint: .isDirectory)
            try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: repo)

            let files = Array(SkillSource.skills(in: folder).dropFirst(DesignSkill.builtIn.count))
            #expect(files.map(\.name) == ["linked", "terse"])
            // The paths go through the folder as given, so a pick survives a re-pointed link.
            #expect(files[1].path == folder.appending(path: "terse.md", directoryHint: .notDirectory).path)
            #expect(load(files[0]).prompt.text == Self.head + "long\n")

            try SkillSource.createFolder(folder)
            #expect(SkillSource.skills(in: folder).count == DesignSkill.builtIn.count + 2)
        }
    }

    @Test func createFolderMakesItOnce() throws {
        try withTempDir { dir in
            let folder = dir.appending(path: "Rimlight/Skills", directoryHint: .isDirectory)
            try SkillSource.createFolder(folder)
            _ = try write("x", "x.md", in: folder)
            try SkillSource.createFolder(folder)
            #expect(SkillSource.skills(in: folder).map(\.name) == Self.builtInNames + ["x"])
        }
    }

    /// The instructions, the design process, then the pick's own text, a blank line between
    /// each, rendered as one.
    @Test func composesInstructionsThenTheProcessThenThePick() throws {
        let adaptive = load(.adaptive)
        #expect(adaptive.fallback == nil)
        #expect(adaptive.prompt == self.adaptive)

        for style in DesignStyle.allCases {
            let loaded = load(.style(style))
            #expect(loaded.fallback == nil)
            #expect(loaded.prompt.skill == .style(style))
            #expect(loaded.prompt.text == Self.head + "### \(style.name)\n\nThe \(style.slug) standard.\n")
        }
    }

    /// A file takes the place of the style; the process still comes before it.
    @Test func aFileFollowsTheProcess() throws {
        try withTempDir { dir in
            let file = try write("\n\nRun {{RIMLIGHT_CLI}} twice, styles in {{RIMLIGHT_STYLES}}.\n\n\n", "terse.md", in: dir)
            let terse = load(DesignSkill(path: file.path), cliPath: "/My Apps/rimlight", stylesPath: "/My Apps/Styles")
            #expect(terse.fallback == nil)
            #expect(terse.prompt.skill == DesignSkill(path: file.path))
            #expect(
                terse.prompt.text
                    == "---\nname: rimlight\n---\nThe command is `'/My Apps/rimlight'`.\n\n## Designing icons\n\nOne idea per icon.\n\n"
                    + "Run '/My Apps/rimlight' twice, styles in /My Apps/Styles.\n")
        }
    }

    @Test func noneIsTheInstructionsAlone() {
        let none = load(.none)
        #expect(none.fallback == nil)
        #expect(
            none.prompt
                == PromptText(skill: .none, text: SkillText.render(Self.instructions, cliPath: "/a/rimlight", stylesPath: "/b/Styles")))
        #expect(SkillText.compose(Self.instructions, sections: []) == Self.instructions)
        #expect(SkillText.compose(Self.instructions, sections: [nil, " \n"]) == Self.instructions)
        #expect(SkillText.compose("A\n\n", sections: [" B ", nil, "", "\nC\n"]) == "A\n\nB\n\nC\n")
    }

    /// Both placeholders render wherever they are: the CLI path shell-quoted when it needs it,
    /// the styles path as it is, since the agent opens it with file tools rather than a shell.
    @Test func stylesPlaceholderRendersPlain() {
        let source = "Run {{RIMLIGHT_CLI}}; read {{RIMLIGHT_STYLES}}/mascot.md and {{RIMLIGHT_STYLES}}."
        #expect(
            SkillText.render(source, cliPath: "/a/rimlight", stylesPath: "/b/Styles")
                == "Run /a/rimlight; read /b/Styles/mascot.md and /b/Styles.")
        #expect(
            SkillText.render(source, cliPath: "/My Apps/rim'light", stylesPath: "/Users/me/App Support/Rim'light/Styles")
                == #"Run '/My Apps/rim'\''light'; read /Users/me/App Support/Rim'light/Styles/mascot.md and /Users/me/App Support/Rim'light/Styles."#)
        #expect(!load(.adaptive, stylesPath: "/x y/Styles").prompt.text.contains(SkillText.stylesPlaceholder))
        #expect(load(.adaptive, stylesPath: "/x y/Styles").prompt.text.contains("`/x y/Styles`"))
    }

    /// The build guide's path renders as it is too, and with none given it is the bundled
    /// Build.md, the file `rimlight skill` names.
    @Test func buildPlaceholderRendersPlain() throws {
        let source = "Run {{RIMLIGHT_CLI}}; read {{RIMLIGHT_BUILD}} first."
        #expect(
            SkillText.render(source, cliPath: "/a/rimlight", stylesPath: "/s", buildPath: "/Rim'light Skills/build.md")
                == "Run /a/rimlight; read /Rim'light Skills/build.md first.")
        let bundled = try SkillText.buildFile().path
        #expect(SkillText.render(source, cliPath: "/a/rimlight", stylesPath: "/s") == "Run /a/rimlight; read \(bundled) first.")
        let texts = SkillSource.Texts(instructions: source, design: "", adaptive: "", styles: [:])
        #expect(
            SkillSource.load(.none, texts: texts, cliPath: "/a/rimlight", stylesPath: "/s", buildPath: "/b/build.md")
                .prompt.text == "Run /a/rimlight; read /b/build.md first.")
    }

    /// Texts without a style's file give Adaptive and say which.
    @Test func aMissingStyleTextFallsBackToAdaptive() {
        var texts = Self.texts
        texts.styles[.mascot] = nil
        let mascot = load(.style(.mascot), texts: texts)
        #expect(mascot.prompt == adaptive)
        #expect(mascot.fallback == "The Mascot style is missing")
    }

    /// The instructions carry the skill's frontmatter, so a file's own is dropped.
    @Test func aFilesFrontmatterIsStripped() throws {
        try withTempDir { dir in
            let file = try write("---\nname: mine\ndescription: x\n---\n\n## My way\n\nBold.\n", "mine.md", in: dir)
            let mine = load(DesignSkill(path: file.path))
            #expect(mine.fallback == nil)
            #expect(mine.prompt.text == Self.head + "## My way\n\nBold.\n")

            let crlf = try write("---\r\nname: mine\r\n---\r\nBold.\r\n", "crlf.md", in: dir)
            #expect(load(DesignSkill(path: crlf.path)).prompt.text == Self.head + "Bold.\n")
        }
        #expect(SkillSource.strippingFrontmatter("No block.\n---\nkept\n---\n") == "No block.\n---\nkept\n---\n")
        #expect(SkillSource.strippingFrontmatter("---\nnever closes\n") == "---\nnever closes\n")
        #expect(SkillSource.strippingFrontmatter("---\n---\nBody") == "Body")
    }

    @Test func missingOrEmptyFileFallsBackToAdaptive() throws {
        try withTempDir { dir in
            let missing = load(DesignSkill(path: dir.appending(path: "gone.md", directoryHint: .notDirectory).path))
            #expect(missing.prompt == adaptive)
            #expect(missing.fallback?.contains("gone.md is missing") == true)

            let blank = try write(" \n\n", "blank.md", in: dir)
            let empty = load(DesignSkill(path: blank.path))
            #expect(empty.prompt == adaptive)
            #expect(empty.fallback?.contains("blank.md is empty") == true)

            let onlyFrontmatter = try write("---\nname: x\n---\n\n", "bare.md", in: dir)
            #expect(load(DesignSkill(path: onlyFrontmatter.path)).fallback?.contains("bare.md is empty") == true)

            let binary = dir.appending(path: "binary.md", directoryHint: .notDirectory)
            try Data([0xFF, 0xFE, 0xC0, 0x00]).write(to: binary)
            let unreadable = load(DesignSkill(path: binary.path))
            #expect(unreadable.prompt == adaptive)
            #expect(unreadable.fallback?.hasPrefix("Cannot read") == true)
        }
    }

    /// Nothing stored is Adaptive, as is an unknown style or a path with no file behind it. The
    /// old Rimlight pick, stored as nothing, reads as Adaptive.
    @Test func storedPickResolves() throws {
        try withTempDir { dir in
            let file = try write("x", "x.md", in: dir)
            #expect(SkillSource.skill(stored: nil) == .adaptive)
            #expect(SkillSource.skill(stored: "rimlight") == .adaptive)
            #expect(SkillSource.skill(stored: "none") == .none)
            #expect(SkillSource.skill(stored: "adaptive") == .adaptive)
            #expect(SkillSource.skill(stored: "style:mascot") == .style(.mascot))
            #expect(SkillSource.skill(stored: "style:soft-3d-object") == .style(.soft3DObject))
            #expect(SkillSource.skill(stored: "style:nope") == .adaptive)
            #expect(SkillSource.skill(stored: "style:") == .adaptive)
            #expect(SkillSource.skill(stored: "None") == .adaptive)
            #expect(SkillSource.skill(stored: file.path) == DesignSkill(path: file.path))
            #expect(SkillSource.skill(stored: file.path).name == "x")
            #expect(SkillSource.skill(stored: dir.appending(path: "gone.md").path) == .adaptive)
            #expect(SkillSource.skill(stored: dir.path) == .adaptive)
            #expect(SkillSource.skill(stored: "x.md") == .adaptive)

            for skill in DesignSkill.builtIn + [DesignSkill(path: file.path)] {
                #expect(SkillSource.skill(stored: SkillSource.stored(skill)) == skill)
                #expect(skill.id == SkillSource.stored(skill) ?? "adaptive")
            }
            #expect(SkillSource.stored(.adaptive) == nil)
            #expect(SkillSource.stored(.none) == "none")
            #expect(SkillSource.stored(.style(.hardwareAndSkeuomorph)) == "style:hardware-and-skeuomorph")
            #expect(SkillSource.stored(DesignSkill(path: file.path)) == file.path)
        }
    }

    /// A stored path and a listed one are the same pick, spaces in the folder name included.
    @Test func aStoredPathMatchesTheListedOne() throws {
        try withTempDir { dir in
            let folder = dir.appending(path: "Application Support/Skills", directoryHint: .isDirectory)
            try SkillSource.createFolder(folder)
            let file = try write("x", "my skill.md", in: folder)
            let listed = try #require(SkillSource.skills(in: folder).last)
            #expect(SkillSource.skill(stored: file.path) == listed)
        }
    }

    /// The comparison a send makes against what the process launched with.
    @Test func anEditOrAnotherSkillIsADifferentPrompt() throws {
        try withTempDir { dir in
            let a = try write("Be brief.", "a.md", in: dir)
            let b = try write("Be brief.", "b.md", in: dir)
            func prompt(_ url: URL) -> PromptText { load(DesignSkill(path: url.path)).prompt }
            let launched = prompt(a)
            #expect(prompt(a) == launched)
            #expect(prompt(b) != launched)
            _ = try write("Be very brief.", "a.md", in: dir)
            #expect(prompt(a) != launched)
            #expect(load(.none).prompt != load(.adaptive).prompt)
            #expect(load(.style(.soft3DObject)).prompt != load(.adaptive).prompt)
            #expect(load(.style(.mascot)).prompt != load(.style(.monoMark)).prompt)
        }
    }
}
