import Foundation

/// `.rimlight/project.json`.
public struct Project: Codable, Hashable, Sendable {
    public static let currentSchema = 1

    public var schema: Int
    public var created: Date

    public init(schema: Int = Project.currentSchema, created: Date) {
        self.schema = schema
        self.created = created
    }

    /// Checks `schema` before any other field: a newer file may have changed them.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(Int.self, forKey: .schema)
        try Self.checkSchema(schema)
        created = try c.decode(Date.self, forKey: .created)
    }

    /// Throws `StoreError.newerSchema` for a schema this build does not read. A record
    /// without one reads as the current schema.
    static func checkSchema(_ schema: Int?) throws {
        if let schema, schema > currentSchema { throw StoreError.newerSchema(schema) }
    }
}

/// `.rimlight/sets/<id>/set.json`. One exploration: a folder of icons.
public struct IconSet: Codable, Hashable, Sendable, Identifiable {
    /// `set-NNN`.
    public var id: String
    public var title: String
    public var created: Date
    /// Harness name to session id, written by the app only.
    public var chat: [String: String]
    /// Harness name to every session the chat has had, oldest first (`ChatSessions`). Written
    /// by the app only; a record without the key has none.
    public var chatHistory: [String: [String]]
    /// Off the sidebar, with every icon in Archived. A record without the key reads as false.
    public var archived: Bool

    public init(
        id: String, title: String, created: Date, chat: [String: String] = [:],
        chatHistory: [String: [String]] = [:], archived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.created = created
        self.chat = chat
        self.chatHistory = chatHistory
        self.archived = archived
    }

    private enum CodingKeys: String, CodingKey { case schema, id, title, created, chat, chatHistory, archived }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try Project.checkSchema(c.decodeIfPresent(Int.self, forKey: .schema))
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        created = try c.decode(Date.self, forKey: .created)
        chat = try c.decodeIfPresent([String: String].self, forKey: .chat) ?? [:]
        chatHistory = try c.decodeIfPresent([String: [String]].self, forKey: .chatHistory) ?? [:]
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Project.currentSchema, forKey: .schema)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(created, forKey: .created)
        try c.encode(chat, forKey: .chat)
        try c.encode(chatHistory, forKey: .chatHistory)
        try c.encode(archived, forKey: .archived)
    }
}

public enum IconMode: String, Codable, Hashable, Sendable {
    case generate
    case refine
}

/// The icon a render was made from.
public struct IconParent: Codable, Hashable, Sendable {
    public var set: String
    public var icon: String

    public init(set: String, icon: String) {
        self.set = set
        self.icon = icon
    }

    /// `<set>/<icon>`.
    public var path: String { "\(set)/\(icon)" }
}

/// An image passed to the generator: a Rimlight icon (`set` and `icon`) or any other file (`path`).
public struct IconRef: Codable, Hashable, Sendable {
    public var set: String?
    public var icon: String?
    public var path: String?

    public init(set: String? = nil, icon: String? = nil, path: String? = nil) {
        self.set = set
        self.icon = icon
        self.path = path
    }

    public static func icon(set: String, icon: String) -> IconRef { IconRef(set: set, icon: icon) }
    public static func file(_ path: String) -> IconRef { IconRef(path: path) }
}

/// `IconRef` without the clash: Foundation on macOS also exports CoreServices' `IconRef`, so
/// outside this module a bare `IconRef` in a type position is ambiguous. Use this name or
/// `RimlightCore.IconRef` there.
public typealias IconReference = IconRef

public struct GeneratorInfo: Codable, Hashable, Sendable {
    public var tool: String
    public var model: String

    public init(tool: String, model: String) {
        self.tool = tool
        self.model = model
    }
}

/// The render's size from its PNG header, and `alpha`: whether its pixels are transparent
/// outside the tile (`ImageProbe.isTransparent`), not merely whether the file has a channel.
public struct ImageInfo: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int
    public var alpha: Bool

    public init(width: Int, height: Int, alpha: Bool) {
        self.width = width
        self.height = height
        self.alpha = alpha
    }
}

/// One automatic transparency fix attempt, as `icon.json` records it in `fixAttempts`.
public struct FixAttempt: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        /// An edit of the opaque render with `TransparencyFix.prompt`.
        case transparencyEdit = "transparency-edit"
        /// A fresh render of the icon's own prompt and refs.
        case reroll
        /// The ground cut away on the Mac (`BackgroundCutout`), no render spent.
        case cutout
    }

    public var kind: Kind
    /// Whether the attempt's pixels came back transparent; false when it failed to render.
    public var transparent: Bool
    public var seconds: Double

    public init(kind: Kind, transparent: Bool, seconds: Double) {
        self.kind = kind
        self.transparent = transparent
        self.seconds = seconds
    }
}

/// `.rimlight/sets/<set>/<slug>/icon.json`. One render and how it was made.
public struct Icon: Codable, Hashable, Sendable, Identifiable {
    public var id: String { slug }

    public var slug: String
    public var title: String
    public var created: Date
    /// Who asked for the render, e.g. `claude-code` or `codex`.
    public var by: String
    public var mode: IconMode
    public var prompt: String
    public var parent: IconParent?
    public var refs: [IconRef]
    public var generator: GeneratorInfo?
    public var image: ImageInfo
    public var archived: Bool
    /// Listed in Favorites. Written by the app only.
    public var favorite: Bool
    /// Harness name to session id, written by the app only.
    public var chat: [String: String]
    /// Harness name to every session the chat has had, oldest first (`ChatSessions`). Written
    /// by the app only; a record without the key has none.
    public var chatHistory: [String: [String]]
    /// Prompts of the fixes made to this render in place (a transparency fix is an edit of
    /// the icon's own file), oldest first. `prompt` stays the concept's. nil when none.
    public var fixes: [String]?
    /// Every automatic transparency fix attempt made for this icon, oldest first, the failed
    /// ones included. nil when none.
    public var fixAttempts: [FixAttempt]?

    public init(
        slug: String,
        title: String,
        created: Date,
        by: String,
        mode: IconMode? = nil,
        prompt: String,
        parent: IconParent? = nil,
        refs: [IconRef] = [],
        generator: GeneratorInfo? = nil,
        image: ImageInfo,
        archived: Bool = false,
        favorite: Bool = false,
        chat: [String: String] = [:],
        chatHistory: [String: [String]] = [:],
        fixes: [String]? = nil,
        fixAttempts: [FixAttempt]? = nil
    ) {
        self.slug = slug
        self.title = title
        self.created = created
        self.by = by
        self.mode = mode ?? (parent == nil ? .generate : .refine)
        self.prompt = prompt
        self.parent = parent
        self.refs = refs
        self.generator = generator
        self.image = image
        self.archived = archived
        self.favorite = favorite
        self.chat = chat
        self.chatHistory = chatHistory
        self.fixes = fixes
        self.fixAttempts = fixAttempts
    }

    private enum CodingKeys: String, CodingKey {
        case schema, slug, title, created, by, mode, prompt, parent, refs, generator, image, archived, chat, fixes
        case chatHistory, fixAttempts, favorite
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try Project.checkSchema(c.decodeIfPresent(Int.self, forKey: .schema))
        slug = try c.decode(String.self, forKey: .slug)
        title = try c.decode(String.self, forKey: .title)
        created = try c.decode(Date.self, forKey: .created)
        by = try c.decodeIfPresent(String.self, forKey: .by) ?? ""
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        parent = try c.decodeIfPresent(IconParent.self, forKey: .parent)
        mode = try c.decodeIfPresent(IconMode.self, forKey: .mode) ?? (parent == nil ? .generate : .refine)
        refs = try c.decodeIfPresent([IconRef].self, forKey: .refs) ?? []
        generator = try c.decodeIfPresent(GeneratorInfo.self, forKey: .generator)
        image = try c.decode(ImageInfo.self, forKey: .image)
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        favorite = try c.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        chat = try c.decodeIfPresent([String: String].self, forKey: .chat) ?? [:]
        chatHistory = try c.decodeIfPresent([String: [String]].self, forKey: .chatHistory) ?? [:]
        fixes = try c.decodeIfPresent([String].self, forKey: .fixes)
        fixAttempts = try c.decodeIfPresent([FixAttempt].self, forKey: .fixAttempts)
    }

    /// Every key is written, `parent`, `generator`, `fixes` and `fixAttempts` as null when absent,
    /// so the file's shape never varies.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Project.currentSchema, forKey: .schema)
        try c.encode(slug, forKey: .slug)
        try c.encode(title, forKey: .title)
        try c.encode(created, forKey: .created)
        try c.encode(by, forKey: .by)
        try c.encode(mode, forKey: .mode)
        try c.encode(prompt, forKey: .prompt)
        try c.encode(parent, forKey: .parent)
        try c.encode(refs, forKey: .refs)
        try c.encode(generator, forKey: .generator)
        try c.encode(image, forKey: .image)
        try c.encode(archived, forKey: .archived)
        try c.encode(favorite, forKey: .favorite)
        try c.encode(chat, forKey: .chat)
        try c.encode(chatHistory, forKey: .chatHistory)
        try c.encode(fixes, forKey: .fixes)
        try c.encode(fixAttempts, forKey: .fixAttempts)
    }
}

/// A file's modification time and size from one `stat`, enough to tell that a render changed.
public struct FileStamp: Hashable, Sendable {
    public var mtimeNS: UInt64
    public var size: UInt64

    public init(mtimeNS: UInt64, size: UInt64) {
        self.mtimeNS = mtimeNS
        self.size = size
    }

    /// nil when the file does not exist or is not a regular file.
    public static func of(_ url: URL) -> FileStamp? {
        var st = stat()
        let rc = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return stat(path, &st)
        }
        guard rc == 0, (st.st_mode & S_IFMT) == S_IFREG else { return nil }
        let ns = UInt64(max(0, st.st_mtimespec.tv_sec)) * 1_000_000_000 + UInt64(max(0, st.st_mtimespec.tv_nsec))
        return FileStamp(mtimeNS: ns, size: UInt64(max(0, st.st_size)))
    }
}

/// One icon as the grid shows it: the record, where it lives, and the render's stamp at read time.
public struct IconSnapshot: Hashable, Sendable, Identifiable {
    /// `<set>/<slug>`, unique in the project.
    public let id: String
    public var icon: Icon
    public var setID: String
    public var folder: URL
    public var imageURL: URL
    /// nil when `icon.png` is missing.
    public var stamp: FileStamp?

    public init(icon: Icon, setID: String, folder: URL, imageURL: URL, stamp: FileStamp?) {
        self.id = "\(setID)/\(icon.slug)"
        self.icon = icon
        self.setID = setID
        self.folder = folder
        self.imageURL = imageURL
        self.stamp = stamp
    }
}
