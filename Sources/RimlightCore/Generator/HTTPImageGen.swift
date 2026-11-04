import Foundation
import Synchronization

/// Renders through an image API on the person's own key: OpenAI's Images API, OpenRouter's,
/// or any service that copies one of them at another address. OpenAI gets one JSON request
/// with every variant in it; OpenRouter one request per variant, since many of its models
/// draw one image a call. The images come back as base64 and are normalized to Rimlight's
/// frame.
public struct HTTPImageGen: ImageGenerator {
    public var provider: ImageProvider
    /// The API root, such as `https://api.openai.com/v1`.
    public var baseURL: URL
    public var dialect: ImageAPIDialect
    public var key: String
    /// The model when the request names none.
    public var defaultModel: String?
    /// The API's quality setting, such as `medium`; nil leaves it to the API.
    public var quality: String?
    public var environment: [String: String]
    public var session: URLSession
    public var onNote: @Sendable (String) -> Void
    /// Seconds before each retry of a rate-limited or failed request.
    public var backoff: [TimeInterval]
    /// OpenRouter models' capabilities, looked up once per model and shared by every copy of
    /// this generator, so a build's layers ask once.
    let capabilityCache = CapabilityCache()

    public var tool: String { provider.tool }

    /// OpenRouter says per model; OpenAI's models all can but gpt-image-2. A model nothing
    /// is known about is given the benefit of the doubt.
    public func drawsTransparency(model: String?) -> Bool {
        guard let model = model.nonEmpty ?? defaultModel else { return true }
        switch dialect {
        case .openai: return ImageModels.openAIDrawsTransparency(model)
        case .openrouter: return capabilities(of: model)?.drawsTransparency ?? true
        }
    }

    /// OpenRouter variants in flight at once, as many as a build draws.
    public static let parallelRequests = 4

    public init(
        provider: ImageProvider, baseURL: URL, dialect: ImageAPIDialect, key: String, defaultModel: String? = nil,
        quality: String? = nil, environment: [String: String] = ProcessInfo.processInfo.environment,
        session: URLSession = .shared, onNote: @escaping @Sendable (String) -> Void = { _ in },
        backoff: [TimeInterval] = [3, 10]
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.dialect = dialect
        self.key = key
        self.defaultModel = defaultModel
        self.quality = quality
        self.environment = environment
        self.session = session
        self.onNote = onNote
        self.backoff = backoff
    }

    public func run(_ request: ImageRequest) throws -> ImageResult {
        try request.validate()
        guard let model = request.model.nonEmpty ?? defaultModel else {
            throw ImageFailure.unavailable("No \(provider.displayName) model is picked: choose one in Rimlight's settings")
        }
        let capabilities = dialect == .openrouter ? capabilities(of: model) : nil
        if let capabilities { try Self.check(request, model: model, against: capabilities) }
        let clock = ContinuousClock()
        let started = clock.now
        let replies: [Reply]
        if dialect == .openrouter, request.count > 1 {
            replies = try variants(request, model: model, capabilities: capabilities)
        } else {
            replies = [try fetch(urlRequest(for: request, model: model, capabilities: capabilities), model: model)]
        }

        let outputDir = try request.outputDir ?? Subprocess.makeTempDirectory(prefix: "rimlight-gen-")
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        var images: [URL] = []
        for bytes in replies.flatMap(\.images) {
            let url = outputDir.appending(
                path: ImageNames.output(index: images.count, count: request.count, ext: "png"), directoryHint: .notDirectory)
            try RenderNormalizer.write(bytes, to: url)
            images.append(url)
        }
        // An image went through, so any recorded limit has lifted.
        RenderLimit.clear(environment: environment)
        let elapsed = started.duration(to: clock.now)
        return ImageResult(
            images: images, outputDir: outputDir,
            seconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18,
            model: model, usage: Reply.total(replies.compactMap(\.usage)),
            cost: replies.contains { $0.cost != nil } ? replies.reduce(0) { $0 + ($1.cost ?? 0) } : nil)
    }

    /// `request.count` single-image requests, `parallelRequests` at a time, in order. A failed
    /// one leaves the others' images; all failing throws the first failure, and a limit
    /// anywhere throws the limit and starts no more.
    func variants(_ request: ImageRequest, model: String, capabilities: OpenRouterCapabilities?) throws -> [Reply] {
        var single = request
        single.count = 1
        let http = try urlRequest(for: single, model: model, capabilities: capabilities)
        let outcomes = Mutex([Result<Reply, ImageFailure>?](repeating: nil, count: request.count))
        let next = Mutex(0)
        let limited = Mutex(false)
        DispatchQueue.concurrentPerform(iterations: min(Self.parallelRequests, request.count)) { _ in
            while true {
                let index: Int? = next.withLock { n in
                    guard n < request.count, !limited.withLock({ $0 }) else { return nil }
                    defer { n += 1 }
                    return n
                }
                guard let index else { return }
                let outcome: Result<Reply, ImageFailure>
                do { outcome = .success(try fetch(http, model: model)) } catch let failure as ImageFailure {
                    outcome = .failure(failure)
                    if case .limit = failure { limited.withLock { $0 = true } }
                } catch {
                    outcome = .failure(.noImage("\(error)"))
                }
                outcomes.withLock { $0[index] = outcome }
            }
        }
        let results = outcomes.withLock { $0 }.compactMap { $0 }
        var failures: [(Int, ImageFailure)] = []
        for (index, result) in results.enumerated() {
            guard case .failure(let failure) = result else { continue }
            if case .limit = failure { throw failure }
            failures.append((index, failure))
        }
        let replies = results.compactMap { try? $0.get() }
        guard !replies.isEmpty else { throw failures.first?.1 ?? ImageFailure.noImage("\(provider.displayName) made no image") }
        for (index, failure) in failures {
            onNote("NOTE: \(provider.displayName)'s image \(index + 1) of \(request.count) failed: \(failure)")
        }
        return replies
    }

    /// One request's images, or the failure it answered with: an empty 2xx answer can still
    /// carry an error, which OpenRouter sends when the model failed after accepting the call.
    func fetch(_ http: URLRequest, model: String) throws -> Reply {
        let data = try send(http, model: model)
        let reply = try Reply(data, provider: provider, model: model)
        guard reply.images.isEmpty else { return reply }
        if let status = Self.errorStatus(in: data) {
            throw Self.failure(status: status, body: data, provider: provider, dialect: dialect, model: model)
                ?? .noImage("\(provider.displayName) answered \(status): \(Self.message(in: data) ?? "no reason given")")
        }
        throw ImageFailure.noImage("\(provider.displayName) answered without an image")
    }

    /// The checks a model's capabilities allow before spending a render.
    static func check(_ request: ImageRequest, model: String, against capabilities: OpenRouterCapabilities) throws {
        guard capabilities.drawsRaster else {
            throw ImageFailure.invalidRequest("\(model) draws vector images only, which Rimlight can't use; pick another model")
        }
        if let refs = capabilities.ranges["input_references"] {
            // A fresh render's tile template is one of them.
            if request.refs.count > refs.upperBound {
                throw ImageFailure.invalidRequest(
                    "\(model) takes at most \(refs.upperBound) reference images and this render has \(request.refs.count), the tile template included; pick another model")
            }
            if request.refs.count < refs.lowerBound {
                throw ImageFailure.invalidRequest(
                    "\(model) needs at least \(refs.lowerBound) reference images and this render has \(request.refs.count)")
            }
        }
    }

    /// The model's capabilities from OpenRouter's `/images/models`, or nil when the list can't
    /// be read or doesn't name the model, as at an address that only copies the API. Then the
    /// request sends the fields most models take.
    func capabilities(of model: String) -> OpenRouterCapabilities? {
        // Held across the lookup so parallel renders wait for the one answer.
        capabilityCache.table.withLock { table in
            if let known = table[model] { return known }
            var http = URLRequest(url: baseURL.appending(path: "images/models"), timeoutInterval: 15)
            http.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            var found: OpenRouterCapabilities?
            if case .success(let (data, response)) = Self.blocking(http, session: session),
                (200..<300).contains(response.statusCode)
            {
                found = OpenRouterCapabilities.find(model, in: data)
            }
            table[model] = .some(found)
            return found
        }
    }

    final class CapabilityCache: Sendable {
        let table = Mutex<[String: OpenRouterCapabilities?]>([:])
    }

    // MARK: The request

    /// The POST for `request`, in this generator's dialect. Public for tests.
    public func urlRequest(
        for request: ImageRequest, model: String, capabilities: OpenRouterCapabilities? = nil
    ) throws -> URLRequest {
        var body: [String: Any] = ["model": model, "prompt": request.prompt]
        let refs = try request.refs.map(Self.dataURL)
        let path: String
        switch dialect {
        case .openai:
            body["n"] = request.count
            body["output_format"] = "png"
            if request.background != .auto { body["background"] = request.background.rawValue }
            if let quality { body["quality"] = quality }
            body["size"] = Self.openAISize(model)
            if refs.isEmpty {
                path = "images/generations"
                body["moderation"] = "low"
            } else {
                path = "images/edits"
                body["images"] = refs.map { ["image_url": $0] }
            }
        case .openrouter:
            path = "images"
            Self.openRouterFields(&body, request, quality: quality, capabilities: capabilities)
            if !refs.isEmpty { body["input_references"] = refs.map { ["type": "image_url", "image_url": ["url": $0]] } }
        }
        var http = URLRequest(url: baseURL.appending(path: path), timeoutInterval: request.timeout)
        http.httpMethod = "POST"
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        if dialect == .openrouter {
            // OpenRouter's app attribution.
            http.setValue("https://rimlightapp.com", forHTTPHeaderField: "HTTP-Referer")
            http.setValue("Rimlight", forHTTPHeaderField: "X-Title")
        }
        http.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return http
    }

    /// OpenRouter's size and format fields, each only when the model takes it, or when its
    /// capabilities are unknown and most models do. No `n`: one image per request. No `size`:
    /// xAI and others reject pixel sizes, and a square ratio with a tier works everywhere.
    static func openRouterFields(
        _ body: inout [String: Any], _ request: ImageRequest, quality: String?, capabilities: OpenRouterCapabilities?
    ) {
        func takes(_ field: String, _ value: String? = nil) -> Bool {
            capabilities?.accepts(field, value) ?? true
        }
        if takes("aspect_ratio") { body["aspect_ratio"] = "1:1" }
        if let tier = capabilities?.resolution { body["resolution"] = tier }
        if let quality, takes("quality", quality) { body["quality"] = quality }
        // A model without transparency gets the prompt's words alone, and the fix after.
        if request.background != .auto, takes("background", request.background.rawValue) {
            body["background"] = request.background.rawValue
        }
        if takes("output_format", "png") { body["output_format"] = "png" }
    }

    /// The size to ask OpenAI for: 1248 px, the step of 16 nearest Rimlight's 1254 px frame,
    /// from the models that take any size; 1024 px from the older ones.
    public static func openAISize(_ model: String) -> String {
        model.hasPrefix("gpt-image-2") || model.hasPrefix("chatgpt-image") ? "1248x1248" : "1024x1024"
    }

    static func dataURL(_ file: URL) throws -> String {
        let data: Data
        do { data = try Data(contentsOf: file) } catch {
            throw ImageFailure.invalidRequest("cannot read reference image \(file.path)")
        }
        let type: String
        switch file.pathExtension.lowercased() {
        case "jpg", "jpeg": type = "image/jpeg"
        case "webp": type = "image/webp"
        default: type = "image/png"
        }
        return "data:\(type);base64,\(data.base64EncodedString())"
    }

    // MARK: Sending

    /// The reply body of a 2xx answer, after retrying rate limits, server errors and dropped
    /// connections; every other answer becomes the `ImageFailure` it means.
    func send(_ request: URLRequest, model: String) throws -> Data {
        var attempt = 0
        while true {
            let reason: String
            var wait = attempt < backoff.count ? backoff[attempt] : 0
            switch Self.blocking(request, session: session) {
            case .failure(let error):
                let dropped: [URLError.Code] = [.timedOut, .networkConnectionLost, .cannotConnectToHost]
                guard let code = (error as? URLError)?.code, dropped.contains(code), attempt < backoff.count else {
                    throw ImageFailure.noImage("\(provider.displayName) couldn't be reached: \(error.localizedDescription)")
                }
                reason = error.localizedDescription
            case .success(let (data, response)):
                let status = response.statusCode
                if (200..<300).contains(status) { return data }
                if let failure = Self.failure(status: status, body: data, provider: provider, dialect: dialect, model: model) {
                    if case .limit(let limit) = failure { RenderLimit.record(limit, environment: environment) }
                    throw failure
                }
                guard attempt < backoff.count else {
                    throw ImageFailure.noImage(
                        "\(provider.displayName) answered \(status) after \(attempt + 1) tries: \(Self.reason(in: data))")
                }
                reason = "\(status)"
                // OpenRouter says how long a rate limit lasts; a minute at most is worth waiting.
                if let after = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init), after > wait {
                    wait = min(after, 60)
                }
            }
            onNote("NOTE: \(provider.displayName) answered \(reason), trying again in \(Int(wait.rounded(.up))) s")
            Thread.sleep(forTimeInterval: wait)
            attempt += 1
        }
    }

    /// What an error answer means; nil for the ones worth trying again: rate limits, timeouts
    /// and server errors.
    static func failure(
        status: Int, body: Data, provider: ImageProvider, dialect: ImageAPIDialect, model: String
    ) -> ImageFailure? {
        let name = provider.displayName
        let message = message(in: body)
        let code = errorCode(in: body)
        let metadata = errorMetadata(in: body)
        func limit(resetsAt: Date? = nil) -> ImageFailure {
            .limit(RenderLimit(
                provider: provider.rawValue, resetsAt: resetsAt, plan: nil, note: message ?? "out of credit", recorded: Date()))
        }
        let refusal = "\(name) refused the prompt: \(message ?? "it breaks the content policy")"
        let missing = "\(name) has no image model \(model): \(message ?? "not found"). Pick another in Rimlight's settings."
        switch dialect {
        case .openai:
            switch status {
            case 401:
                return .unavailable("\(name) rejected the key. Check it in Rimlight's settings.")
            case 403:
                // The key is good but not allowed this: an unverified organization, say. Only
                // the API's own message tells the person what to do.
                return .unavailable("\(name) refused this request: \(message ?? "no reason given")")
            case 402:
                return limit()
            case 429 where code == "insufficient_quota" || code == "billing_hard_limit_reached":
                return limit()
            case 429, 500..<600:
                return nil
            default:
                if code == "moderation_blocked" || code == "content_policy_violation" { return .noImage(refusal) }
                return .noImage("\(name) answered \(status): \(message ?? "no reason given")")
            }
        case .openrouter:
            // OpenRouter's `error.code` is the status; `metadata.error_type` says what failed.
            let type = metadata["error_type"] as? String
            let limitSource = metadata["limit_source"] as? String
            switch status {
            case 401:
                return .unavailable("\(name) rejected the key. Check it in Rimlight's settings.")
            case 402 where limitSource == "openrouter_in_flight_budget":
                // Spending already in flight holds the budget; it frees as those renders finish.
                return nil
            case 402:
                return limit()
            case 403 where limitSource != nil:
                // A guardrail, workspace or key budget, until its window rolls over.
                return limit(resetsAt: (metadata["resets_at"] as? String).flatMap(Self.isoDate))
            case 403 where type == "content_policy_violation" || type == "refusal" || metadata["reasons"] != nil:
                var text = refusal
                if let reasons = metadata["reasons"] as? [String], !reasons.isEmpty {
                    text += " (flagged for \(reasons.joined(separator: ", ")))"
                }
                return .noImage(text)
            case 403:
                return .noImage("\(name) blocked the request: \(message ?? "no reason given")")
            case 404:
                return .noImage(missing)
            case 400 where type == "not_found" || message?.localizedCaseInsensitiveContains("not a valid model") == true:
                return .noImage(missing)
            case 408, 429, 500..<600:
                return nil
            default:
                return .noImage("\(name) answered \(status): \(message ?? "no reason given")")
            }
        }
    }

    /// The error's message, with the upstream provider OpenRouter names, for the line after
    /// the last retry.
    static func reason(in body: Data) -> String {
        let message = message(in: body) ?? "no reason given"
        guard let upstream = errorMetadata(in: body)["provider_name"] as? String else { return message }
        return "\(message) (\(upstream))"
    }

    static func errorObject(in body: Data) -> [String: Any]? {
        ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["error"] as? [String: Any]
    }

    static func message(in body: Data) -> String? {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let error = json?["error"]
        if let error = error as? [String: Any], let message = error["message"] as? String { return message }
        if let error = error as? String { return error }
        return json?["message"] as? String
    }

    /// OpenAI's `error.code` or `error.type`, both strings. OpenRouter's code is a number.
    static func errorCode(in body: Data) -> String? {
        guard let error = errorObject(in: body) else { return nil }
        return (error["code"] as? String) ?? (error["type"] as? String)
    }

    /// OpenRouter's numeric `error.code`, which is the HTTP status the error means.
    static func errorStatus(in body: Data) -> Int? {
        (errorObject(in: body)?["code"] as? NSNumber)?.intValue
    }

    static func errorMetadata(in body: Data) -> [String: Any] {
        errorObject(in: body)?["metadata"] as? [String: Any] ?? [:]
    }

    static func isoDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    /// `URLSession`'s answer, waited for: the commands run synchronously.
    static func blocking(_ request: URLRequest, session: URLSession) -> Result<(Data, HTTPURLResponse), any Error> {
        let result = Mutex<Result<(Data, HTTPURLResponse), any Error>?>(nil)
        let done = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: request) { data, response, error in
            let outcome: Result<(Data, HTTPURLResponse), any Error>
            if let error {
                outcome = .failure(error)
            } else if let response = response as? HTTPURLResponse {
                outcome = .success((data ?? Data(), response))
            } else {
                outcome = .failure(URLError(.badServerResponse))
            }
            result.withLock { $0 = outcome }
            done.signal()
        }
        task.resume()
        done.wait()
        return result.withLock { $0 } ?? .failure(URLError(.unknown))
    }

    // MARK: The reply

    /// The images and what they cost, from either dialect: both answer `data[].b64_json`.
    /// OpenAI counts `input_tokens` and `output_tokens`, OpenRouter `prompt_tokens` and
    /// `completion_tokens` with `cost` in US dollars.
    struct Reply {
        var images: [Data]
        var usage: ImageUsage?
        var cost: Double?

        init(_ body: Data, provider: ImageProvider = .openai, model: String = "") throws {
            guard let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
                throw ImageFailure.noImage("the image API answered with something that isn't JSON")
            }
            let items = json["data"] as? [[String: Any]] ?? []
            if items.contains(where: { ($0["media_type"] as? String)?.hasPrefix("image/svg") == true }) {
                throw ImageFailure.noImage("\(provider.displayName)'s \(model) answered with a vector image, which Rimlight can't use")
            }
            images = items.compactMap { ($0["b64_json"] as? String).flatMap { Data(base64Encoded: $0) } }
            let usage = json["usage"] as? [String: Any]
            if let usage {
                func int(_ key: String) -> Int? { (usage[key] as? NSNumber)?.intValue }
                func details(_ key: String) -> Int {
                    ((usage[key] as? [String: Any])?["cached_tokens"] as? NSNumber)?.intValue ?? 0
                }
                let input = int("input_tokens") ?? int("prompt_tokens")
                let output = int("output_tokens") ?? int("completion_tokens")
                if input != nil || output != nil {
                    self.usage = ImageUsage(
                        input: input ?? 0, cached: max(details("input_tokens_details"), details("prompt_tokens_details")),
                        output: output ?? 0)
                }
                cost = (usage["cost"] as? NSNumber)?.doubleValue
            }
        }

        /// The usage of several replies added up; nil when none has any.
        static func total(_ usages: [ImageUsage]) -> ImageUsage? {
            guard !usages.isEmpty else { return nil }
            return usages.dropFirst().reduce(usages[0]) {
                ImageUsage(input: $0.input + $1.input, cached: $0.cached + $1.cached, output: $0.output + $1.output)
            }
        }
    }
}
