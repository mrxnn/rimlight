import Foundation

/// A model a provider offers for rendering, as the app's picker shows it.
public struct ImageModelOption: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// A few words on when to pick it.
    public var note: String?
    /// Whether it has rendered the layer trial's regression set and a blind build well enough
    /// to recommend. Tested models sit at the top of a list.
    public var tested: Bool
    /// Whether it can draw on real transparency; nil when its provider doesn't say. One that
    /// can't paints a ground, which Rimlight cuts out on the Mac.
    public var transparency: Bool?
    /// What it charges; nil when no price is listed.
    public var price: ImagePrice?

    public init(
        id: String, name: String, note: String? = nil, tested: Bool = false, transparency: Bool? = nil,
        price: ImagePrice? = nil
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.tested = tested
        self.transparency = transparency
        self.price = price
    }
}

/// The models each provider offers, and a check that a key works. Shared by the app's picker
/// and `rimlight image`.
public enum ImageModels {
    /// The model ids that passed the regression set and a blind build.
    public static let tested: Set<String> = []

    /// OpenAI's image models worth offering, newest first.
    public static let openAI: [ImageModelOption] = [
        ImageModelOption(
            id: "gpt-image-2.5-flare", name: "GPT Image 2.5 Flare", note: "Fast, for most renders",
            tested: tested.contains("gpt-image-2.5-flare"), transparency: true),
        ImageModelOption(
            id: "gpt-image-2.5-sunburst", name: "GPT Image 2.5 Sunburst", note: "Slower, more precise edits",
            tested: tested.contains("gpt-image-2.5-sunburst"), transparency: true),
    ]

    /// Whether an OpenAI model draws on real transparency. gpt-image-2 takes only `auto` and
    /// `opaque` backgrounds; the others take `transparent`.
    public static func openAIDrawsTransparency(_ model: String) -> Bool {
        !(model == "gpt-image-2" || model.hasPrefix("gpt-image-2-"))
    }

    /// Where OpenRouter lists prices without a key. OpenAI's own models are priced from there
    /// too, under `openai/<id>`, since OpenAI's API has no price list; the key never goes there.
    static let publicPrices = URL(string: "https://openrouter.ai/api/v1/images/models")!

    /// The model a provider renders with when none is picked; nil when the person has to pick.
    public static func defaultModel(for provider: ImageProvider) -> String? {
        switch provider {
        case .openai: openAI.first?.id
        case .codex, .openrouter, .custom: nil
        }
    }

    /// The models `provider` offers that can render Rimlight's requests. For OpenRouter that
    /// is every image model that takes images as input, since refinements, fixes and layered
    /// builds all send reference images; tested ones first, then by name. Takes no key: both
    /// lists are public, so showing a menu never reads a key from the Keychain or sends it.
    public static func list(
        _ provider: ImageProvider, baseURL: URL? = nil, session: URLSession = .shared
    ) async throws -> [ImageModelOption] {
        switch provider {
        case .codex, .custom:
            return []
        case .openai:
            return await priced(openAI, root: publicPrices, prefix: "openai/", session: session)
        case .openrouter:
            let root = try root(provider, baseURL)
            let data = try await get(root.appending(path: "images/models"), key: nil, provider: provider, session: session)
            return await priced(openRouterModels(data), root: root.appending(path: "images/models"), prefix: "", session: session)
        }
    }

    /// `options` with each one's price, looked up side by side, a few at a time. A price that
    /// can't be read is left out rather than failing the list.
    static func priced(
        _ options: [ImageModelOption], root: URL, prefix: String, session: URLSession
    ) async -> [ImageModelOption] {
        await withTaskGroup(of: (Int, ImagePrice?).self) { group in
            var priced = options
            var next = 0
            func add() {
                guard next < options.count else { return }
                let index = next
                let url = root.appending(path: prefix + options[index].id).appending(path: "endpoints")
                group.addTask {
                    let request = URLRequest(url: url, timeoutInterval: 15)
                    guard let (data, response) = try? await session.data(for: request),
                        ((response as? HTTPURLResponse)?.statusCode ?? 0) / 100 == 2
                    else { return (index, nil) }
                    return (index, ImagePrice.parse(endpoints: data))
                }
                next += 1
            }
            for _ in 0..<8 { add() }
            for await (index, price) in group {
                priced[index].price = price
                add()
            }
            return priced
        }
    }

    /// Throws when `key` doesn't work for `provider`: `ImageFailure.unavailable` with the
    /// reason. Makes one free, authenticated request.
    public static func verifyKey(
        _ provider: ImageProvider, key: String, baseURL: URL? = nil, session: URLSession = .shared
    ) async throws {
        let root = try root(provider, baseURL)
        // OpenRouter's /key describes the key itself; OpenAI's /models needs any valid key.
        let path = provider == .openrouter ? "key" : "models"
        _ = try await get(root.appending(path: path), key: key, provider: provider, session: session)
    }

    /// OpenRouter's `/images/models` reply, kept to models that take images and draw raster
    /// ones (a vector model's SVG can't be fitted to the tile), tested first.
    static func openRouterModels(_ data: Data) -> [ImageModelOption] {
        let options = OpenRouterCapabilities.entries(data).compactMap { entry -> ImageModelOption? in
            guard let id = entry["id"] as? String, !id.isEmpty else { return nil }
            let inputs = (entry["architecture"] as? [String: Any])?["input_modalities"] as? [String] ?? []
            guard inputs.contains("image"), OpenRouterCapabilities(entry: entry).drawsRaster else { return nil }
            return ImageModelOption(
                id: id, name: entry["name"] as? String ?? id, tested: tested.contains(id),
                transparency: OpenRouterCapabilities(entry: entry).drawsTransparency)
        }
        // Tested first, then the ones that draw on transparency, which need no cutout.
        func rank(_ o: ImageModelOption) -> (Int, Int, String) {
            (o.tested ? 0 : 1, o.transparency == true ? 0 : 1, o.name.lowercased())
        }
        return options.sorted { rank($0) < rank($1) }
    }

    private static func root(_ provider: ImageProvider, _ baseURL: URL?) throws -> URL {
        guard let root = baseURL ?? provider.defaultBaseURL else {
            throw ImageFailure.unavailable("\(provider.displayName) has no API address")
        }
        return root
    }

    private static func get(_ url: URL, key: String?, provider: ImageProvider, session: URLSession) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 20)
        if let key { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: return data
        case 401 where key != nil: throw ImageFailure.unavailable("\(provider.displayName) rejected the key")
        case 403:
            // A good key without this permission; the key may still render.
            let reason = HTTPImageGen.message(in: data) ?? "no reason given"
            throw ImageFailure.unavailable("\(provider.displayName) refused this request: \(reason)")
        default: throw ImageFailure.unavailable("\(provider.displayName) answered \(status)")
        }
    }
}
