import Foundation

/// Who renders the images.
public enum ImageProvider: String, Codable, CaseIterable, Sendable {
    /// The Codex CLI's image tool, on the ChatGPT plan Codex is signed in with. No key.
    case codex
    /// OpenAI's Images API, on the person's own key.
    case openai
    /// OpenRouter's Images API, on the person's own key.
    case openrouter
    /// Any service that speaks one of the two APIs above, at `ImageSettings.baseURL`. Set in
    /// the config file or with `--base-url`; the app doesn't offer it.
    case custom

    public var displayName: String {
        switch self {
        case .codex: "Codex"
        case .openai: "OpenAI"
        case .openrouter: "OpenRouter"
        case .custom: "Custom endpoint"
        }
    }

    /// What `icon.json` records as `generator.tool`.
    public var tool: String {
        switch self {
        case .codex: "codex-image-gen"
        case .openai: "openai-images"
        case .openrouter: "openrouter-images"
        case .custom: "custom-images"
        }
    }

    /// The API root requests go to; nil for Codex, and for the custom provider, whose root is
    /// `ImageSettings.baseURL`.
    public var defaultBaseURL: URL? {
        switch self {
        case .openai: URL(string: "https://api.openai.com/v1")
        case .openrouter: URL(string: "https://openrouter.ai/api/v1")
        case .codex, .custom: nil
        }
    }

    /// The API shape the provider speaks; nil for Codex.
    public var dialect: ImageAPIDialect? {
        switch self {
        case .openai: .openai
        case .openrouter: .openrouter
        case .codex, .custom: nil
        }
    }

    /// Whether renders need an API key. Codex signs in with ChatGPT instead.
    public var usesKey: Bool { self != .codex }

    /// The variable a terminal can hold the key in when the app isn't running. Rimlight's own
    /// name, so a stray `OPENAI_API_KEY` in someone's shell is never spent without asking.
    public var keyVariable: String? {
        usesKey ? "RIMLIGHT_\(rawValue.uppercased())_API_KEY" : nil
    }
}

/// Which image model renders, shared by the app, which writes it, and the CLI, which reads it
/// on every render, so a switch in the app takes effect on the next image. Nothing secret:
/// keys live in the app's Keychain item. Kept at `$XDG_CONFIG_HOME/rimlight/image.json`, else
/// `~/.config/rimlight/image.json`.
public struct ImageSettings: Codable, Equatable, Sendable {
    public var provider: ImageProvider
    /// The model picked for each provider, by raw value, so switching back keeps the pick.
    public var models: [String: String]
    /// The custom provider's API root, such as `https://example.com/v1`. Ignored by the others.
    public var baseURL: String?
    /// Which API the custom provider speaks.
    public var dialect: ImageAPIDialect?
    /// The image API's quality, such as `medium`. nil is the provider's default.
    public var quality: String?

    public init(
        provider: ImageProvider = .codex, models: [String: String] = [:], baseURL: String? = nil,
        dialect: ImageAPIDialect? = nil, quality: String? = nil
    ) {
        self.provider = provider
        self.models = models
        self.baseURL = baseURL
        self.dialect = dialect
        self.quality = quality
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = try c.decodeIfPresent(ImageProvider.self, forKey: .provider) ?? .codex
        models = try c.decodeIfPresent([String: String].self, forKey: .models) ?? [:]
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL)
        dialect = try c.decodeIfPresent(ImageAPIDialect.self, forKey: .dialect)
        quality = try c.decodeIfPresent(String.self, forKey: .quality)
    }

    /// The model picked for `provider`, if any.
    public func model(for provider: ImageProvider) -> String? {
        models[provider.rawValue].flatMap { $0.isEmpty ? nil : $0 }
    }

    public mutating func setModel(_ model: String?, for provider: ImageProvider) {
        models[provider.rawValue] = model
    }

    // MARK: The file

    /// `$RIMLIGHT_CONFIG_DIR`, else `$XDG_CONFIG_HOME/rimlight`, else `~/.config/rimlight`,
    /// then `image.json`.
    public static func url(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let dir: URL
        if let custom = environment["RIMLIGHT_CONFIG_DIR"], !custom.isEmpty {
            dir = URL(filePath: (custom as NSString).expandingTildeInPath, directoryHint: .isDirectory)
        } else if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            dir = URL(filePath: (xdg as NSString).expandingTildeInPath, directoryHint: .isDirectory)
                .appending(path: "rimlight", directoryHint: .isDirectory)
        } else {
            dir = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: ".config/rimlight", directoryHint: .isDirectory)
        }
        return dir.appending(path: "image.json", directoryHint: .notDirectory)
    }

    /// The saved settings; Codex when there is no file. A file that can't be read is an
    /// error, not a silent fall back to Codex.
    public static func load(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> ImageSettings {
        let url = url(environment: environment)
        let data: Data
        do { data = try Data(contentsOf: url) } catch CocoaError.fileReadNoSuchFile {
            return ImageSettings()
        } catch {
            throw StoreError.io("Cannot read \(url.path): \(error.localizedDescription)")
        }
        do { return try JSONDecoder().decode(ImageSettings.self, from: data) } catch {
            throw StoreError.invalidArgument("\(url.path) is not valid image settings: \(error)")
        }
    }

    public func save(environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        let url = Self.url(environment: environment)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try AtomicFile.write(try encoder.encode(self) + Data("\n".utf8), to: url)
    }
}

/// The two image API shapes Rimlight speaks. Most services copy one of them.
public enum ImageAPIDialect: String, Codable, CaseIterable, Sendable {
    /// `POST /images/generations` and `/images/edits`, refs as `images`.
    case openai
    /// `POST /images`, refs as `input_references`.
    case openrouter
}
