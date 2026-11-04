import Foundation
import RimlightCore
import Synchronization

/// `rimlight image`: which image model renders, whether its key reaches rimlight, and, for a
/// terminal without the app, a way to change it. Never prints a key.
enum Image {
    static let usage = """
        rimlight image [--json]
        rimlight image --set codex|openai|openrouter|custom [--model M] [--quality Q] [--base-url URL] [--dialect openai|openrouter]
        rimlight image --models [--provider P]
        """

    static let help = """
        usage:
        \(usage)

        Without options it prints the image model generate, fix and build render with, from
        \(ImageSettings.url().path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")),
        and where its key comes from: Rimlight's settings, through the running app, or the
        provider's RIMLIGHT_<PROVIDER>_API_KEY. The app writes the same file, so a pick in either
        place holds for both. --set changes it. --models lists the models a provider offers.
        """

    static func run(_ raw: ArraySlice<String>) throws -> Int32 {
        let args = try Arguments(
            raw, flags: ["--models", "--help", "-h"],
            options: ["--set", "--model", "--quality", "--base-url", "--dialect", "--provider"])
        if args.flag("--help") || args.flag("-h") {
            Output.out(help)
            return 0
        }
        try args.expectPositionals(0, usage)
        var settings = try ImageSettings.load()

        if let raw = args.value("--set") {
            guard let provider = ImageProvider(rawValue: raw.lowercased()) else {
                throw UsageError("unknown provider \"\(raw)\"; the providers are \(ImageProvider.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            settings.provider = provider
            if let model = args.value("--model") { settings.setModel(model, for: provider) }
            if let quality = args.value("--quality") { settings.quality = quality.isEmpty ? nil : quality }
            if let url = args.value("--base-url") { settings.baseURL = url.isEmpty ? nil : url }
            if let raw = args.value("--dialect") {
                guard let dialect = ImageAPIDialect(rawValue: raw.lowercased()) else {
                    throw UsageError("--dialect is openai or openrouter, not \"\(raw)\"")
                }
                settings.dialect = dialect
            }
            if provider == .custom, settings.baseURL == nil { throw UsageError("--set custom needs --base-url") }
            try settings.save()
        } else if args.value("--model") != nil || args.value("--quality") != nil {
            throw UsageError("--model and --quality go with --set")
        }

        if args.flag("--models") {
            var provider = settings.provider
            if let raw = args.value("--provider") {
                guard let p = ImageProvider(rawValue: raw.lowercased()) else { throw UsageError("unknown --provider \"\(raw)\"") }
                provider = p
            }
            return try models(provider, settings: settings, json: args.flag("--json"))
        }
        return try show(settings, json: args.flag("--json"))
    }

    private static func waiting(_ provider: ImageProvider) -> String {
        "NOTE: waiting for the Rimlight app to hand over the \(provider.displayName) key; if it shows a dialog, answer it"
    }

    private struct Status: Encodable {
        var provider, name: String
        var model: String?
        var quality, baseURL: String?
        /// `app`, `environment`, `missing`, or nil for Codex.
        var key: String?
        var settings: String
    }

    private static func show(_ settings: ImageSettings, json: Bool) throws -> Int32 {
        let provider = settings.provider
        let model = settings.model(for: provider) ?? ImageModels.defaultModel(for: provider)
        var key: String?
        var why: String?
        if provider.usesKey {
            switch KeySource.lookup(provider, onWait: { Output.err(waiting(provider)) }) {
            case .found(_, let origin): key = origin.rawValue
            case .missing(let reason):
                key = "missing"
                why = reason
            }
        }
        let status = Status(
            provider: provider.rawValue, name: provider.displayName, model: model, quality: settings.quality,
            baseURL: provider == .custom ? settings.baseURL : nil, key: key, settings: ImageSettings.url().path)
        if json {
            try Output.json(status)
        } else {
            var line = "IMAGE \(provider.rawValue)"
            if let model { line += " model=\(model)" } else if provider == .codex { line += " model=default" }
            if let quality = settings.quality { line += " quality=\(quality)" }
            if let url = status.baseURL { line += " base-url=\(url)" }
            switch key {
            case "app": line += " key=from-app"
            case "environment": line += " key=\(provider.keyVariable ?? "environment")"
            case "missing": line += " key=missing"
            default: break
            }
            Output.out(line)
            if let why { Output.err("NOTE: \(why)") }
            if provider.usesKey, model == nil {
                Output.err("NOTE: no \(provider.displayName) model is picked; `rimlight image --models` lists them")
            }
        }
        return key == "missing" ? 1 : 0
    }

    private static func models(_ provider: ImageProvider, settings: ImageSettings, json: Bool) throws -> Int32 {
        guard provider.usesKey else {
            Output.out(json ? "[]" : "NOTE: Codex picks its own image model")
            return 0
        }
        let key: String
        switch KeySource.lookup(provider, onWait: { Output.err(waiting(provider)) }) {
        case .found(let found, _): key = found
        case .missing(let why): throw ImageFailure.unavailable(why)
        }
        let baseURL = provider == .custom ? settings.baseURL.flatMap(URL.init(string:)) : nil
        let result = Mutex<Result<[ImageModelOption], any Error>?>(nil)
        let done = DispatchSemaphore(value: 0)
        Task {
            let outcome: Result<[ImageModelOption], any Error>
            do { outcome = .success(try await ImageModels.list(provider, key: key, baseURL: baseURL)) } catch {
                outcome = .failure(error)
            }
            result.withLock { $0 = outcome }
            done.signal()
        }
        done.wait()
        let options = try (result.withLock { $0 } ?? .success([])).get()
        if json {
            struct Row: Encodable {
                var id, name: String
                var note: String?
                var tested: Bool
                var transparency: Bool?
                var price: String?
            }
            try Output.json(options.map {
                Row(id: $0.id, name: $0.name, note: $0.note, tested: $0.tested, transparency: $0.transparency, price: $0.price?.label)
            })
        } else {
            for option in options {
                var line = "MODEL \(option.id)"
                if option.tested { line += " tested" }
                if let clear = option.transparency { line += clear ? " transparent" : " opaque" }
                line += "  \(option.name)"
                if let note = option.note { line += ": \(note)" }
                if let price = option.price { line += " (\(price.label))" }
                Output.out(line)
            }
        }
        return 0
    }
}
