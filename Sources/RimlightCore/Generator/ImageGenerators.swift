import Foundation

/// The generator a command renders with: the saved `ImageSettings`, with any of the command's
/// own flags on top.
public enum ImageGenerators {
    /// A command's `--provider`, `--model`, `--base-url` and `--quality`; nil keeps the setting.
    public struct Overrides: Sendable {
        public var provider: ImageProvider?
        public var model: String?
        public var baseURL: String?
        public var quality: String?

        public init(provider: ImageProvider? = nil, model: String? = nil, baseURL: String? = nil, quality: String? = nil) {
            self.provider = provider
            self.model = model
            self.baseURL = baseURL
            self.quality = quality
        }
    }

    /// The settings with `overrides` applied: a model or base URL given on the command line
    /// belongs to the provider it names, or to the saved one.
    public static func resolve(_ settings: ImageSettings, _ overrides: Overrides) -> ImageSettings {
        var settings = settings
        if let provider = overrides.provider { settings.provider = provider }
        if let model = overrides.model { settings.setModel(model, for: settings.provider) }
        if let baseURL = overrides.baseURL {
            settings.baseURL = baseURL
            // An address on its own is the custom provider's.
            if overrides.provider == nil { settings.provider = .custom }
        }
        if let quality = overrides.quality { settings.quality = quality }
        return settings
    }

    public static func make(
        _ settings: ImageSettings,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        onNote: @escaping @Sendable (String) -> Void = { _ in }
    ) throws -> any ImageGenerator {
        switch settings.provider {
        case .codex:
            return CodexImageGen(environment: environment, onNote: onNote)
        case .openai, .openrouter, .custom:
            let provider = settings.provider
            guard let baseURL = provider == .custom ? settings.baseURL.flatMap(URL.init(string:)) : provider.defaultBaseURL
            else { throw ImageFailure.unavailable("The custom image provider needs a baseURL in \(ImageSettings.url(environment: environment).path)") }
            let key: String
            switch KeySource.lookup(provider, environment: environment, onWait: {
                onNote("NOTE: waiting for the Rimlight app to hand over the \(provider.displayName) key; if it shows a dialog, answer it")
            }) {
            case .found(let found, _): key = found
            case .missing(let why): throw ImageFailure.unavailable(why)
            }
            return HTTPImageGen(
                provider: provider, baseURL: baseURL, dialect: provider.dialect ?? settings.dialect ?? .openai, key: key,
                defaultModel: ImageModels.defaultModel(for: provider), quality: settings.quality,
                environment: environment, onNote: onNote)
        }
    }

}
