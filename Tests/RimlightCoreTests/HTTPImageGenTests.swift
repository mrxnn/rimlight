import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import Testing

@testable import RimlightCore

/// Answers every request a stubbed session makes with the next of its canned replies, and
/// keeps the requests it saw.
final class StubAPI: URLProtocol {
    struct Reply: Sendable {
        var status: Int
        var body: Data
    }

    static let state = Mutex<(replies: [Reply], seen: [URLRequest], models: Reply?)>(([], [], nil))

    /// `models` answers every `GET …/images/models`, apart from the queue; nil answers 404.
    static func session(_ replies: [Reply], models: Reply? = nil) -> URLSession {
        state.withLock { $0 = (replies, [], models) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubAPI.self]
        return URLSession(configuration: config)
    }

    static var seen: [URLRequest] { state.withLock { $0.seen } }
    static var posts: [URLRequest] { seen.filter { $0.httpMethod == "POST" } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // URLProtocol hands the body over as a stream.
        var request = request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 65536)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                body.append(contentsOf: buffer[..<n])
            }
            stream.close()
            request.httpBody = body
        }
        let reply = Self.state.withLock { state -> Reply in
            state.seen.append(request)
            if request.httpMethod != "POST", request.url?.path.hasSuffix("images/models") == true {
                return state.models ?? Reply(status: 404, body: Data())
            }
            return state.replies.isEmpty ? Reply(status: 500, body: Data()) : state.replies.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized) struct HTTPImageGenTests {
    static func images(_ pngs: [Data], usage: [String: Any]? = nil) throws -> StubAPI.Reply {
        var json: [String: Any] = ["data": pngs.map { ["b64_json": $0.base64EncodedString()] }]
        if let usage { json["usage"] = usage }
        return StubAPI.Reply(status: 200, body: try JSONSerialization.data(withJSONObject: json))
    }

    static func error(_ status: Int, code: String, message: String) -> StubAPI.Reply {
        let json: [String: Any] = ["error": ["code": code, "message": message]]
        return StubAPI.Reply(status: status, body: try! JSONSerialization.data(withJSONObject: json))
    }

    static func generator(
        _ provider: ImageProvider = .openai, session: URLSession, env: [String: String] = [:],
        onNote: @escaping @Sendable (String) -> Void = { _ in }
    ) -> HTTPImageGen {
        HTTPImageGen(
            provider: provider, baseURL: provider.defaultBaseURL!, dialect: provider.dialect!, key: "sk-test",
            defaultModel: ImageModels.defaultModel(for: provider), quality: "medium", environment: env, session: session,
            onNote: onNote, backoff: [0, 0])
    }

    /// An OpenRouter error body: the status again as a number, and metadata.
    static func openRouterError(_ status: Int, message: String, metadata: [String: Any]? = nil) -> StubAPI.Reply {
        var error: [String: Any] = ["code": status, "message": message]
        if let metadata { error["metadata"] = metadata }
        return StubAPI.Reply(status: status, body: try! JSONSerialization.data(withJSONObject: ["error": error]))
    }

    /// A `/images/models` reply listing `id` with `parameters` as its `supported_parameters`.
    static func models(_ id: String, _ parameters: [String: Any]) -> StubAPI.Reply {
        let entry: [String: Any] = [
            "id": id, "name": id, "architecture": ["input_modalities": ["text", "image"], "output_modalities": ["image"]],
            "supported_parameters": parameters,
        ]
        return StubAPI.Reply(status: 200, body: try! JSONSerialization.data(withJSONObject: ["data": [entry]]))
    }

    static func enumeration(_ values: [String]) -> [String: Any] { ["type": "enum", "values": values] }
    static func range(_ low: Int, _ high: Int) -> [String: Any] { ["type": "range", "min": low, "max": high] }

    /// Like OpenRouter's `openai/gpt-image-2` on 2026-10-31: no transparent background, no
    /// resolution, no output format.
    static var gptImage2: [String: Any] { [
        "aspect_ratio": enumeration(["1:1", "3:2", "auto"]), "quality": enumeration(["auto", "low", "medium", "high"]),
        "background": enumeration(["auto", "opaque"]), "n": range(1, 10), "input_references": range(0, 16),
    ] }

    /// Like `x-ai/grok-imagine-image-quality`: tiers, one image a call, three references.
    static var grok: [String: Any] { [
        "resolution": enumeration(["1K", "2K"]), "aspect_ratio": enumeration(["1:1", "3:4", "auto"]),
        "n": range(1, 1), "input_references": range(0, 3),
    ] }

    static func capabilities(_ parameters: [String: Any]) -> OpenRouterCapabilities {
        OpenRouterCapabilities.find("m", in: models("m", parameters).body)!
    }

    static func body(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func aFreshRenderAsksOpenAIForATransparentSquare() throws {
        let gen = Self.generator(session: StubAPI.session([]))
        let request = try gen.urlRequest(for: ImageRequest(prompt: "A dial.", count: 2), model: "gpt-image-2.5-flare")
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/images/generations")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        let body = try Self.body(request)
        #expect(body["model"] as? String == "gpt-image-2.5-flare")
        #expect(body["n"] as? Int == 2)
        #expect(body["size"] as? String == "1248x1248")
        #expect(body["background"] as? String == "transparent")
        #expect(body["output_format"] as? String == "png")
        #expect(body["quality"] as? String == "medium")
        #expect(body["moderation"] as? String == "low")
        #expect(body["images"] == nil)
    }

    @Test func anEditSendsItsRefsAsDataURLs() throws {
        try withTempDir { dir in
            let ref = dir.appending(path: "parent.png")
            try DrawnPNG.transparent(size: 64).write(to: ref)
            let gen = Self.generator(session: StubAPI.session([]))
            let request = try gen.urlRequest(
                for: ImageRequest(prompt: "Edit Image 1.", refs: [ref], background: .opaque), model: "gpt-image-1.5")
            #expect(request.url?.lastPathComponent == "edits")
            let body = try Self.body(request)
            let images = try #require(body["images"] as? [[String: String]])
            #expect(images.count == 1 && images[0]["image_url"]?.hasPrefix("data:image/png;base64,") == true)
            #expect(body["size"] as? String == "1024x1024")
            #expect(body["background"] as? String == "opaque")
            #expect(body["moderation"] == nil)
        }
    }

    @Test func openRouterSpeaksItsOwnShape() throws {
        try withTempDir { dir in
            let ref = dir.appending(path: "parent.png")
            try DrawnPNG.transparent(size: 64).write(to: ref)
            let gen = Self.generator(.openrouter, session: StubAPI.session([]))
            let request = try gen.urlRequest(
                for: ImageRequest(prompt: "p", refs: [ref], background: .auto), model: "vendor/model")
            #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/images")
            #expect(request.value(forHTTPHeaderField: "X-Title") == "Rimlight")
            let body = try Self.body(request)
            // Unknown capabilities: the fields most models take, and no `n` or pixel `size`.
            #expect(body["aspect_ratio"] as? String == "1:1")
            #expect(body["output_format"] as? String == "png")
            #expect(body["quality"] as? String == "medium")
            #expect(body["background"] == nil)
            #expect(body["n"] == nil && body["size"] == nil && body["resolution"] == nil)
            let refs = try #require(body["input_references"] as? [[String: Any]])
            #expect(refs.first?["type"] as? String == "image_url")
            let url = try #require((refs.first?["image_url"] as? [String: String])?["url"])
            #expect(url.hasPrefix("data:image/png;base64,"))
        }
    }

    /// A field the model doesn't list is left out, and so is a value it doesn't take.
    @Test func openRouterSendsOnlyWhatTheModelTakes() throws {
        let gen = Self.generator(.openrouter, session: StubAPI.session([]))
        let gpt = try Self.body(gen.urlRequest(
            for: ImageRequest(prompt: "p"), model: "m", capabilities: Self.capabilities(Self.gptImage2)))
        #expect(gpt["background"] == nil)
        #expect(gpt["quality"] as? String == "medium")
        #expect(gpt["aspect_ratio"] as? String == "1:1")
        #expect(gpt["output_format"] == nil && gpt["resolution"] == nil && gpt["n"] == nil)

        let grok = try Self.body(gen.urlRequest(
            for: ImageRequest(prompt: "p", background: .opaque), model: "m", capabilities: Self.capabilities(Self.grok)))
        #expect(grok["resolution"] as? String == "1K")
        #expect(grok["quality"] == nil && grok["background"] == nil && grok["output_format"] == nil)

        var transparent = Self.gptImage2
        transparent["background"] = Self.enumeration(["auto", "transparent", "opaque"])
        transparent["output_format"] = Self.enumeration(["png", "jpeg"])
        let full = try Self.body(gen.urlRequest(
            for: ImageRequest(prompt: "p"), model: "m", capabilities: Self.capabilities(transparent)))
        #expect(full["background"] as? String == "transparent")
        #expect(full["output_format"] as? String == "png")

        // Nothing listed means nothing supported, square included.
        let bare = try Self.body(gen.urlRequest(for: ImageRequest(prompt: "p"), model: "m", capabilities: Self.capabilities([:])))
        #expect(Set(bare.keys) == ["model", "prompt"])
    }

    /// The tier nearest 1254 px: 1K over 1.5K, and the smallest a model has when that's bigger.
    @Test func theResolutionTierIsTheNearestToTheFrame() {
        func tier(_ values: [String]) -> String? {
            Self.capabilities(["resolution": Self.enumeration(values)]).resolution
        }
        #expect(tier(["512", "1K", "2K", "4K"]) == "1K")
        #expect(tier(["768", "1K", "1.5K", "2K"]) == "1K")
        #expect(tier(["2K", "4K"]) == "2K")
        #expect(tier(["768", "1.5K"]) == "1.5K")
        #expect(tier(["8K"]) == nil)
        #expect(Self.capabilities([:]).resolution == nil)
    }

    /// Variants go one request each, in parallel, and the capabilities are looked up once.
    @Test func openRouterVariantsAreOneRequestEach() throws {
        try withTempDir { dir in
            let png = try DrawnPNG.transparent(size: 1024)
            let reply = try Self.images([png], usage: ["prompt_tokens": 10, "completion_tokens": 1000, "cost": 0.04])
            let session = StubAPI.session([reply, reply, reply, reply], models: Self.models("x-ai/grok", Self.grok))
            let gen = Self.generator(.openrouter, session: session)
            let result = try gen.run(
                ImageRequest(prompt: "p", count: 3, model: "x-ai/grok", outputDir: dir.appending(path: "out")))
            #expect(result.images.map(\.lastPathComponent) == ["image-1.png", "image-2.png", "image-3.png"])
            #expect(StubAPI.posts.count == 3)
            for post in StubAPI.posts { #expect(try Self.body(post)["n"] == nil) }
            #expect(result.usage == ImageUsage(input: 30, cached: 0, output: 3000))
            #expect(abs((result.cost ?? 0) - 0.12) < 1e-9)
            #expect(result.model == "x-ai/grok")

            // The same generator asks no second time.
            _ = try gen.run(ImageRequest(prompt: "p", model: "x-ai/grok", outputDir: dir.appending(path: "again")))
            #expect(StubAPI.seen.filter { $0.httpMethod != "POST" }.count == 1)
        }
    }

    /// One failed variant leaves the others, and says why in a note.
    @Test func aFailedVariantLeavesTheOthers() throws {
        try withTempDir { dir in
            let ok = try Self.images([try DrawnPNG.transparent(size: 1254)])
            let bad = Self.openRouterError(400, message: "Invalid request parameters")
            let notes = Mutex<[String]>([])
            let gen = Self.generator(
                .openrouter, session: StubAPI.session([ok, bad, ok]), onNote: { note in notes.withLock { $0.append(note) } })
            let result = try gen.run(ImageRequest(prompt: "p", count: 3, model: "m", outputDir: dir.appending(path: "out")))
            #expect(result.images.map(\.lastPathComponent) == ["image-1.png", "image-2.png"])
            let said = notes.withLock { $0 }
            #expect(said.count == 1 && said[0].contains("of 3 failed: OpenRouter answered 400: Invalid request parameters"))
        }
    }

    @Test func allVariantsFailingThrowsTheFirst() throws {
        let bad = Self.openRouterError(400, message: "Invalid request parameters")
        let gen = Self.generator(.openrouter, session: StubAPI.session([bad, bad]))
        #expect {
            try gen.run(ImageRequest(prompt: "p", count: 2, model: "m"))
        } throws: { "\($0)" == "OpenRouter answered 400: Invalid request parameters" }
    }

    /// Out of credit on any variant ends the render as a limit, even with images in hand.
    @Test func aLimitOnAnyVariantIsTheAnswer() throws {
        try withTempDir { dir in
            let env = ["RIMLIGHT_STATE_DIR": dir.path]
            let ok = try Self.images([try DrawnPNG.transparent(size: 1254)])
            let broke = Self.openRouterError(402, message: "Insufficient credits. Add more using https://openrouter.ai/credits")
            let gen = Self.generator(.openrouter, session: StubAPI.session([ok, broke, ok]), env: env)
            #expect {
                try gen.run(ImageRequest(prompt: "p", count: 3, model: "m", outputDir: dir.appending(path: "out")))
            } throws: { error in
                guard case ImageFailure.limit(let limit) = error else { return false }
                return limit.provider == "openrouter"
                    && limit.message() == "OpenRouter refused the render: Insufficient credits. Add more using https://openrouter.ai/credits. Renders fail until the account is sorted out."
            }
            #expect(RenderLimit.current(environment: env)?.provider == "openrouter")
        }
    }

    /// OpenRouter's errors, from its error reference, each as a line someone can act on.
    @Test func openRouterErrorsReadWell() throws {
        func failure(_ reply: StubAPI.Reply) -> ImageFailure? {
            HTTPImageGen.failure(status: reply.status, body: reply.body, provider: .openrouter, dialect: .openrouter, model: "a/b")
        }
        #expect(failure(Self.openRouterError(401, message: "User not found."))?.description
            == "OpenRouter rejected the key. Check it in Rimlight's settings.")
        let flagged = Self.openRouterError(
            403, message: "a/b requires moderation on OpenAI. Your input was flagged.",
            metadata: ["reasons": ["violence"], "flagged_input": "…", "provider_name": "OpenAI", "model_slug": "a/b"])
        #expect(failure(flagged)?.description
            == "OpenRouter refused the prompt: a/b requires moderation on OpenAI. Your input was flagged. (flagged for violence)")
        let policy = Self.openRouterError(403, message: "Blocked by SAFETY", metadata: ["error_type": "content_policy_violation"])
        #expect(failure(policy)?.description == "OpenRouter refused the prompt: Blocked by SAFETY")
        #expect(failure(Self.openRouterError(404, message: "Model not found"))?.description
            == "OpenRouter has no image model a/b: Model not found. Pick another in Rimlight's settings.")
        #expect(failure(Self.openRouterError(400, message: "nope/x is not a valid model ID"))?.description
            == "OpenRouter has no image model a/b: nope/x is not a valid model ID. Pick another in Rimlight's settings.")
        #expect(failure(Self.openRouterError(400, message: "Image too large", metadata: ["error_type": "image_too_large"]))?
            .description == "OpenRouter answered 400: Image too large")
        // Worth trying again: a provider's failure, a timeout, a rate limit, spending in flight.
        #expect(failure(Self.openRouterError(502, message: "Provider returned error")) == nil)
        #expect(failure(Self.openRouterError(408, message: "Timed out")) == nil)
        #expect(failure(Self.openRouterError(429, message: "Rate limit exceeded")) == nil)
        #expect(failure(Self.openRouterError(402, message: "In flight", metadata: ["limit_source": "openrouter_in_flight_budget"])) == nil)

        // A budget is a limit until it resets.
        let budget = Self.openRouterError(
            403, message: "Budget limit exceeded (weekly limit). $52.00 of $50.00 used; resets 2026-10-12T00:00:00.000Z.",
            metadata: ["limit_source": "openrouter_key_limit", "resets_at": "2026-10-12T00:00:00.000Z"])
        guard case .limit(let limit)? = failure(budget) else { Issue.record("not a limit"); return }
        #expect(limit.resetsAt == Date(timeIntervalSince1970: 1_791_763_200))
        let message = limit.message(now: Date(timeIntervalSince1970: 1_791_763_200 - 3600), timeZone: TimeZone(identifier: "UTC")!)
        #expect(message.hasPrefix("OpenRouter refused the render: Budget limit exceeded"))
        #expect(message.contains("used; resets 2026-10-12T00:00:00.000Z. It resets at "))
        #expect(message.hasSuffix(", in 1 h 0 min. Renders fail until then."))

        // The upstream provider rides along on the last retry's line.
        #expect(HTTPImageGen.reason(in: Self.openRouterError(502, message: "Provider returned error", metadata: ["provider_name": "xAI"]).body)
            == "Provider returned error (xAI)")
    }

    /// A provider failing after OpenRouter accepted the call answers 200 with only an error.
    @Test func anErrorInsideA200IsAFailure() throws {
        let failed = Self.openRouterError(502, message: "Provider returned error")
        let session = StubAPI.session([StubAPI.Reply(status: 200, body: failed.body)])
        #expect {
            try Self.generator(.openrouter, session: session).run(ImageRequest(prompt: "p", model: "m"))
        } throws: { "\($0)" == "OpenRouter answered 502: Provider returned error" }
        #expect(StubAPI.posts.count == 1)
    }

    /// OpenRouter's usage counts prompt and completion tokens; a vector reply can't be used.
    @Test func openRouterRepliesAreRead() throws {
        let png = try DrawnPNG.transparent(size: 64)
        let usage: [String: Any] = [
            "prompt_tokens": 16, "completion_tokens": 272, "total_tokens": 288, "cost": 0.011,
            "prompt_tokens_details": ["cached_tokens": 4],
        ]
        let body = try JSONSerialization.data(withJSONObject: [
            "created": 1_748_372_400, "data": [["b64_json": png.base64EncodedString(), "media_type": "image/png"]], "usage": usage,
        ])
        let reply = try HTTPImageGen.Reply(body, provider: .openrouter, model: "m")
        #expect(reply.images.count == 1)
        #expect(reply.usage == ImageUsage(input: 16, cached: 4, output: 272))
        #expect(abs((reply.cost ?? 0) - 0.011) < 1e-9)
        let svg = try JSONSerialization.data(withJSONObject: [
            "data": [["b64_json": Data("<svg/>".utf8).base64EncodedString(), "media_type": "image/svg+xml"]]
        ])
        #expect { try HTTPImageGen.Reply(svg, provider: .openrouter, model: "r/vector") } throws: {
            "\($0)".contains("vector image")
        }
    }

    /// A model's own limits stop a render before it is paid for.
    @Test func aModelsLimitsAreCheckedFirst() throws {
        try withTempDir { dir in
            let a = dir.appending(path: "a.png")
            let b = dir.appending(path: "b.png")
            try DrawnPNG.transparent(size: 64).write(to: a)
            try DrawnPNG.transparent(size: 64).write(to: b)
            var one = Self.grok
            one["input_references"] = Self.range(0, 1)
            let gen = Self.generator(.openrouter, session: StubAPI.session([], models: Self.models("m", one)))
            #expect {
                try gen.run(ImageRequest(prompt: "p", refs: [a, b], model: "m"))
            } throws: { "\($0)".contains("m takes at most 1 reference images and this render has 2") }

            let vector = Self.generator(
                .openrouter,
                session: StubAPI.session([], models: Self.models("v", ["output_format": Self.enumeration(["svg"])])))
            #expect { try vector.run(ImageRequest(prompt: "p", model: "v")) } throws: { "\($0)".contains("vector images only") }
            #expect(StubAPI.posts.isEmpty)
        }
    }

    /// The custom provider speaks either dialect at its own address, on its own key.
    @Test func theCustomProviderSpeaksEitherDialect() throws {
        let env = ["RIMLIGHT_KEY_SOCKET": "/nonexistent/keys.sock", "RIMLIGHT_CUSTOM_API_KEY": "sk-custom"]
        for (dialect, path) in [(ImageAPIDialect.openrouter, "/v1/images"), (.openai, "/v1/images/generations")] {
            let settings = ImageSettings(
                provider: .custom, models: ["custom": "house/model"], baseURL: "https://images.example.com/v1", dialect: dialect)
            let gen = try #require(try ImageGenerators.make(settings, environment: env) as? HTTPImageGen)
            #expect(gen.dialect == dialect)
            #expect(gen.tool == "custom-images")
            let request = try gen.urlRequest(for: ImageRequest(prompt: "p"), model: "house/model")
            #expect(request.url?.host() == "images.example.com" && request.url?.path() == path)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-custom")
        }
        // No dialect is OpenAI's; no address can't render.
        let plain = ImageSettings(provider: .custom, baseURL: "https://images.example.com/v1")
        #expect((try ImageGenerators.make(plain, environment: env) as? HTTPImageGen)?.dialect == .openai)
        #expect { try ImageGenerators.make(ImageSettings(provider: .custom), environment: env) } throws: {
            "\($0)".contains("needs a baseURL")
        }
    }

    /// A custom address with OpenRouter's shape but no model list still renders, with the
    /// fields most models take.
    @Test func aCustomOpenRouterWithoutAModelListStillRenders() throws {
        try withTempDir { dir in
            let session = StubAPI.session([try Self.images([try DrawnPNG.transparent(size: 1254)])])
            let gen = HTTPImageGen(
                provider: .custom, baseURL: URL(string: "https://images.example.com/v1")!, dialect: .openrouter, key: "k",
                session: session, backoff: [0])
            let result = try gen.run(ImageRequest(prompt: "p", model: "house/model", outputDir: dir.appending(path: "out")))
            #expect(result.images.count == 1)
            #expect(StubAPI.seen.first?.url?.absoluteString == "https://images.example.com/v1/images/models")
            let body = try Self.body(try #require(StubAPI.posts.first))
            #expect(body["aspect_ratio"] as? String == "1:1" && body["background"] as? String == "transparent")
        }
    }

    /// A 1024 px render comes back in Rimlight's 1254 px frame, alpha kept.
    @Test func rendersAreNormalizedToTheFrame() throws {
        try withTempDir { dir in
            let session = StubAPI.session([
                try Self.images(
                    [try DrawnPNG.transparent(size: 1024)],
                    usage: ["input_tokens": 50, "output_tokens": 4160, "cost": 0.042])
            ])
            let result = try Self.generator(session: session).run(
                ImageRequest(prompt: "A dial.", outputDir: dir.appending(path: "out")))
            let image = try #require(result.images.first)
            #expect(image.lastPathComponent == "image.png")
            let probe = try #require(ImageProbe.read(image))
            #expect(probe.header.width == 1254 && probe.header.height == 1254)
            #expect(probe.isTransparent)
            #expect(result.model == "gpt-image-2.5-flare")
            #expect(result.usage == ImageUsage(input: 50, cached: 0, output: 4160))
            #expect(result.cost == 0.042)
        }
    }

    @Test func aRenderFarFromSquareIsRefused() throws {
        let context = try #require(CGContext(
            data: nil, width: 128, height: 64, bitsPerComponent: 8, bytesPerRow: 512,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        try withTempDir { dir in
            #expect {
                try RenderNormalizer.write(data as Data, to: dir.appending(path: "x.png"))
            } throws: { "\($0)".contains("128x64") }
        }
    }

    @Test func aRejectedKeySaysSo() throws {
        let session = StubAPI.session([Self.error(401, code: "invalid_api_key", message: "Incorrect API key")])
        #expect {
            try Self.generator(session: session).run(ImageRequest(prompt: "p"))
        } throws: { "\($0)" == "OpenAI rejected the key. Check it in Rimlight's settings." }
        #expect(StubAPI.seen.count == 1)
    }

    /// A good key that isn't allowed this: the API's message says what to do, not "check the key".
    @Test func aForbiddenRenderShowsTheAPIsReason() throws {
        let reason = "Your organization must be verified to use the model gpt-image-2.5-flare."
        // OpenAI sends this one with a null code, so only the type and message are strings.
        let body = try JSONSerialization.data(withJSONObject: [
            "error": ["message": reason, "type": "invalid_request_error", "param": NSNull(), "code": NSNull()]
        ])
        let session = StubAPI.session([StubAPI.Reply(status: 403, body: body)])
        #expect {
            try Self.generator(session: session).run(ImageRequest(prompt: "p"))
        } throws: { "\($0)" == "OpenAI refused this request: \(reason)" }
        #expect(StubAPI.seen.count == 1)
    }

    @Test func aKeyCheckTellsA401FromA403() async throws {
        let rejected = StubAPI.session([Self.error(401, code: "invalid_api_key", message: "Incorrect API key")])
        await #expect {
            try await ImageModels.verifyKey(.openai, key: "k", session: rejected)
        } throws: { "\($0)" == "OpenAI rejected the key" }
        let forbidden = StubAPI.session([Self.error(403, code: "missing_scope", message: "Missing scope: model.read")])
        await #expect {
            try await ImageModels.verifyKey(.openai, key: "k", session: forbidden)
        } throws: { "\($0)" == "OpenAI refused this request: Missing scope: model.read" }
    }

    /// No credit is a limit: recorded for the app's banner, and no retry spent on it.
    @Test func anEmptyAccountIsALimit() throws {
        try withTempDir { dir in
            let env = ["RIMLIGHT_STATE_DIR": dir.path]
            let session = StubAPI.session([
                Self.error(429, code: "insufficient_quota", message: "You exceeded your current quota.")
            ])
            #expect {
                try Self.generator(session: session, env: env).run(ImageRequest(prompt: "p"))
            } throws: { error in
                guard case ImageFailure.limit(let limit) = error else { return false }
                return limit.provider == "openai" && limit.note == "You exceeded your current quota."
            }
            #expect(StubAPI.seen.count == 1)
            #expect(RenderLimit.current(environment: env)?.provider == "openai")
        }
    }

    @Test func aRateLimitIsTriedAgain() throws {
        try withTempDir { dir in
            let session = StubAPI.session([
                Self.error(429, code: "rate_limit_exceeded", message: "Slow down."),
                StubAPI.Reply(status: 503, body: Data()),
                try Self.images([try DrawnPNG.transparent(size: 1254)]),
            ])
            let result = try Self.generator(session: session).run(
                ImageRequest(prompt: "p", outputDir: dir.appending(path: "out")))
            #expect(result.images.count == 1)
            #expect(StubAPI.seen.count == 3)
        }
    }

    @Test func aRefusedPromptIsNotRetried() throws {
        let session = StubAPI.session([Self.error(400, code: "moderation_blocked", message: "Your request was rejected.")])
        #expect {
            try Self.generator(session: session).run(ImageRequest(prompt: "p"))
        } throws: { "\($0)" == "OpenAI refused the prompt: Your request was rejected." }
        #expect(StubAPI.seen.count == 1)
    }

    @Test func openRouterNeedsAPickedModel() throws {
        let gen = Self.generator(.openrouter, session: StubAPI.session([]))
        #expect { try gen.run(ImageRequest(prompt: "p")) } throws: { "\($0)".contains("No OpenRouter model is picked") }
    }
}
