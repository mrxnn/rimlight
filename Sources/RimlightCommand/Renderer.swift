import Foundation
import RimlightCore

/// The image model a render command uses: the saved `ImageSettings`, with the command's own
/// flags on top.
struct Renderer: Sendable {
    var generator: any ImageGenerator
    var settings: ImageSettings

    /// The model renders ask for; nil leaves it to the generator.
    var model: String? { settings.model(for: settings.provider) }

    /// The options every render command takes.
    static let options: Set<String> = ["--provider", "--model", "--base-url", "--quality"]

    static let help = """
        --provider codex|openai|openrouter|custom, --model M, --base-url URL and --quality Q
        override the image model picked in Rimlight's settings for this command (`rimlight image`
        shows it).
        """

    /// The saved settings with the command's flags on top. Cheap: no key is fetched.
    static func settings(_ args: Arguments) throws -> ImageSettings {
        var provider: ImageProvider?
        if let raw = args.value("--provider") {
            guard let p = ImageProvider(rawValue: raw.lowercased()) else {
                throw UsageError(
                    "unknown --provider \"\(raw)\"; the providers are \(ImageProvider.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            provider = p
        }
        return ImageGenerators.resolve(
            try ImageSettings.load(),
            .init(provider: provider, model: args.value("--model"), baseURL: args.value("--base-url"), quality: args.value("--quality")))
    }

    /// The generator for `settings`, which for an API provider fetches its key.
    static func make(_ settings: ImageSettings) throws -> Renderer {
        Renderer(generator: try ImageGenerators.make(settings, onNote: { Output.err($0) }), settings: settings)
    }

    static func make(_ args: Arguments) throws -> Renderer { try make(settings(args)) }
}
