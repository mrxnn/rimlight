import Foundation

/// A look the agent can be held to: one file in the bundled `Styles` folder, named by its slug.
public enum DesignStyle: String, CaseIterable, Sendable, Hashable {
    case soft3DObject = "soft-3d-object"
    case glassAndChrome = "glass-and-chrome"
    case lettermarkAndWordmark = "lettermark-and-wordmark"
    case monoMark = "mono-mark"
    case mascot = "mascot"
    case hardwareAndSkeuomorph = "hardware-and-skeuomorph"
    case systemGlyph = "system-glyph"
    case sceneAndCollage = "scene-and-collage"

    public var slug: String { rawValue }

    /// `<slug>.md`.
    public var fileName: String { rawValue + ".md" }

    public var name: String {
        switch self {
        case .soft3DObject: "Soft 3D object"
        case .glassAndChrome: "Glass and chrome"
        case .lettermarkAndWordmark: "Lettermark and wordmark"
        case .monoMark: "Mono mark"
        case .mascot: "Mascot"
        case .hardwareAndSkeuomorph: "Hardware and skeuomorph"
        case .systemGlyph: "System glyph"
        case .sceneAndCollage: "Scene and collage"
        }
    }

    /// One word or two for a tight label, such as the app's composer pill.
    public var shortName: String {
        switch self {
        case .soft3DObject: "Soft 3D"
        case .glassAndChrome: "Glass"
        case .lettermarkAndWordmark: "Lettermark"
        case .monoMark: "Mono mark"
        case .mascot: "Mascot"
        case .hardwareAndSkeuomorph: "Hardware"
        case .systemGlyph: "Glyph"
        case .sceneAndCollage: "Scene"
        }
    }
}

/// The design skill a chat runs with after the fixed instructions: Adaptive (the design process
/// and the index of the styles), one style, none, or a Markdown file in the skills folder.
/// Adaptive is the default.
public enum DesignSkill: Sendable, Hashable, Identifiable {
    case adaptive
    case none
    case style(DesignStyle)
    case file(URL)

    /// Adaptive, None, then the styles in their fixed order.
    public static let builtIn: [DesignSkill] = [.adaptive, .none] + DesignStyle.allCases.map(DesignSkill.style)

    /// The skill for the Markdown file at `path`. Listings and stored picks both go through
    /// here, so the same file gives equal values.
    public init(path: String) {
        self = .file(URL(filePath: path, directoryHint: .notDirectory))
    }

    /// "Adaptive", "None", the style's name, or the file's name without `.md`.
    public var name: String {
        switch self {
        case .adaptive: "Adaptive"
        case .none: "None"
        case .style(let style): style.name
        case .file(let url): url.deletingPathExtension().lastPathComponent
        }
    }

    /// The file, which is what a pick of one is stored as.
    public var path: String? {
        if case .file(let url) = self { url.path } else { nil }
    }

    public var style: DesignStyle? {
        if case .style(let style) = self { style } else { nil }
    }

    /// What the pick is stored as, with "adaptive" for Adaptive.
    public var id: String { SkillSource.stored(self) ?? SkillSource.storedAdaptive }
}

/// The rendered instructions a chat's process starts with, and the design skill in them. A send
/// that renders a different one restarts the process.
public struct PromptText: Sendable, Equatable {
    public var skill: DesignSkill
    public var text: String

    public init(skill: DesignSkill, text: String) {
        self.skill = skill
        self.text = text
    }
}

/// The design skills: the built-in ones, plus every `.md` file in a folder the person keeps them in.
public enum SkillSource {
    /// `~/Library/Application Support/Rimlight/Skills`.
    public static var defaultFolder: URL {
        URL.applicationSupportDirectory
            .appending(path: "Rimlight", directoryHint: .isDirectory)
            .appending(path: "Skills", directoryHint: .isDirectory)
    }

    /// What a pick of None is stored as. Adaptive, the default, is stored as nothing, a file as
    /// its path.
    public static let storedNone = "none"
    /// What an Adaptive pick was stored as before it became the default. It still reads as
    /// Adaptive, and it is the name `install-skill --style` takes.
    public static let storedAdaptive = "adaptive"
    /// A style is stored as this and its slug.
    public static let storedStylePrefix = "style:"

    /// Makes `folder` unless a folder, or a symlink to one, is already there.
    public static func createFolder(_ folder: URL = defaultFolder) throws {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory)
        if exists, isDirectory.boolValue { return }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw StoreError.io("Cannot create \(folder.path): \(error.localizedDescription)")
        }
    }

    /// Adaptive, None, the styles, then every `.md` file in `folder` by name, ignoring
    /// case. Symlinks are followed, to the folder and to each file; hidden files are left out. A
    /// folder that is not there lists the built-in ones. One directory listing and a stat per entry.
    public static func skills(in folder: URL = defaultFolder) -> [DesignSkill] {
        let builtIn = DesignSkill.builtIn
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder.resolvingSymlinksInPath().path) else {
            return builtIn
        }
        var files: [DesignSkill] = []
        for name in names where !name.hasPrefix(".") && (name as NSString).pathExtension.lowercased() == "md" {
            let path = folder.appending(path: name, directoryHint: .notDirectory).path
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
            files.append(DesignSkill(path: path))
        }
        files.sort { a, b in
            switch a.name.compare(b.name, options: [.caseInsensitive, .numeric]) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: a.name < b.name
            }
        }
        return builtIn + files
    }

    /// The skill a stored pick names: Adaptive for nothing, an unknown style, or a path with no
    /// file behind it. The old Rimlight pick was stored as nothing, so it reads as Adaptive too.
    public static func skill(stored value: String?) -> DesignSkill {
        guard let value else { return .adaptive }
        if value == storedNone { return .none }
        if value == storedAdaptive { return .adaptive }
        if value.hasPrefix(storedStylePrefix) {
            return DesignStyle(rawValue: String(value.dropFirst(storedStylePrefix.count))).map(DesignSkill.style) ?? .adaptive
        }
        var isDirectory: ObjCBool = false
        guard value.hasPrefix("/"), FileManager.default.fileExists(atPath: value, isDirectory: &isDirectory),
            !isDirectory.boolValue
        else { return .adaptive }
        return DesignSkill(path: value)
    }

    /// What `skill` is stored as: nil (nothing stored) for Adaptive, the default.
    public static func stored(_ skill: DesignSkill) -> String? {
        switch skill {
        case .adaptive: nil
        case .none: storedNone
        case .style(let style): storedStylePrefix + style.slug
        case .file(let url): url.path
        }
    }

    /// The bundled texts a prompt is made from, as bundled, placeholders and the instructions'
    /// frontmatter included: Instructions.md, Design.md (the design process every pick but None
    /// takes), Adaptive.md (the index of the styles) and the style files.
    public struct Texts: Sendable {
        public var instructions: String
        public var design: String
        public var adaptive: String
        public var styles: [DesignStyle: String]

        public init(instructions: String, design: String, adaptive: String, styles: [DesignStyle: String]) {
            self.instructions = instructions
            self.design = design
            self.adaptive = adaptive
            self.styles = styles
        }
    }

    /// What `load` gives: the text to launch with, and why the pick's file was not used.
    public struct Loaded: Sendable {
        public var prompt: PromptText
        public var fallback: String?

        public init(prompt: PromptText, fallback: String? = nil) {
            self.prompt = prompt
            self.fallback = fallback
        }
    }

    /// The instructions, then for every pick but None the design process and the pick's own
    /// text: the style index for Adaptive, a style's file, or a file from the folder. A file is
    /// read fresh and loses a leading frontmatter block, since the instructions carry their own;
    /// it takes the place of the style, not of the process. Rendered with `cliPath`,
    /// `stylesPath`, the folder the agent reads style files from, and `buildPath`, the build
    /// guide, which is the bundled Build.md when nil. A file that is missing, unreadable or empty
    /// gives Adaptive instead, with the reason in `fallback`, so a chat never starts without a
    /// design skill it did not ask to drop.
    public static func load(
        _ skill: DesignSkill, texts: Texts, cliPath: String, stylesPath: String, buildPath: String? = nil
    ) -> Loaded {
        func loaded(_ skill: DesignSkill, _ tail: String?, fallback: String? = nil) -> Loaded {
            let sections = skill == .none ? [] : [texts.design, tail]
            let composed = SkillText.compose(texts.instructions, sections: sections)
            let text = SkillText.render(composed, cliPath: cliPath, stylesPath: stylesPath, buildPath: buildPath)
            return Loaded(prompt: PromptText(skill: skill, text: text), fallback: fallback)
        }
        let path: String
        switch skill {
        case .adaptive: return loaded(.adaptive, texts.adaptive)
        case .none: return loaded(.none, nil)
        case .style(let style):
            guard let text = texts.styles[style] else {
                return loaded(.adaptive, texts.adaptive, fallback: "The \(style.name) style is missing")
            }
            return loaded(skill, text)
        case .file(let url): path = url.path
        }
        let fallback: String
        do {
            let source = try String(contentsOf: URL(filePath: path, directoryHint: .notDirectory), encoding: .utf8)
            let text = strippingFrontmatter(source)
            if text.contains(where: { !$0.isWhitespace }) { return loaded(skill, text) }
            fallback = "\(path) is empty"
        } catch {
            fallback = FileManager.default.fileExists(atPath: path)
                ? "Cannot read \(path): \(error.localizedDescription)"
                : "\(path) is missing"
        }
        return loaded(.adaptive, texts.adaptive, fallback: fallback)
    }

    /// `text` without a YAML frontmatter block (`---` lines around it) at its very start. Text
    /// whose first line is not `---`, or whose block never closes, comes back as it is.
    public static func strippingFrontmatter(_ text: String) -> String {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        func isFence(_ line: Substring) -> Bool { line.trimmingCharacters(in: .whitespacesAndNewlines) == "---" }
        guard let first = lines.first, isFence(first),
            let close = lines.dropFirst().firstIndex(where: isFence)
        else { return text }
        return lines[(close + 1)...].joined(separator: "\n")
    }
}
