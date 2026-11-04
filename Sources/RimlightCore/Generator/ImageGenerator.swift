import Foundation

/// Something that renders images from a prompt and reference images: Codex on the person's
/// ChatGPT plan, or an image API on their own key. `generate`, `fix` and `build` hold one of
/// these and never name a provider.
public protocol ImageGenerator: Sendable {
    /// What `icon.json` records as `generator.tool`.
    var tool: String { get }
    /// Blocks for the whole render. Throws `ImageFailure`.
    func run(_ request: ImageRequest) throws -> ImageResult
    /// Whether `model` (nil for the generator's default) can draw on real transparency. When
    /// it can't, asking it again to remove a ground is money spent on a refusal.
    func drawsTransparency(model: String?) -> Bool
}

extension ImageGenerator {
    public func drawsTransparency(model: String?) -> Bool { true }
}

/// What a render asks for, the same for every provider.
public struct ImageRequest: Sendable {
    /// Passed to the model verbatim.
    public var prompt: String
    /// Reference or edit-target images, in order: the first is Image 1. At most `maxRefs`.
    public var refs: [URL]
    /// Variants of the same prompt.
    public var count: Int
    /// The generator's model; nil leaves it to the generator's own default.
    public var model: String?
    /// Codex's reasoning effort; an image API ignores it.
    public var effort: String?
    /// Seconds before the render is given up.
    public var timeout: TimeInterval
    /// Where the images land. nil makes a fresh temp folder. Either way the caller owns it.
    public var outputDir: URL?
    /// What to ask for outside the drawing. Codex is told in the prompt instead and ignores it.
    public var background: Background

    public enum Background: String, Sendable {
        /// A real alpha channel: icon renders and their fixes.
        case transparent
        /// A painted ground: build layers keyed on magenta or black.
        case opaque
        /// The model's own choice.
        case auto
    }

    /// Codex's image_gen takes five references, and the skill's four-plus-template rule
    /// rests on it, so every provider keeps the same cap.
    public static let maxRefs = 5

    public init(
        prompt: String,
        refs: [URL] = [],
        count: Int = 1,
        model: String? = nil,
        effort: String? = nil,
        timeout: TimeInterval = 540,
        outputDir: URL? = nil,
        background: Background = .transparent
    ) {
        self.prompt = prompt
        self.refs = refs
        self.count = count
        self.model = model
        self.effort = effort
        self.timeout = timeout
        self.outputDir = outputDir
        self.background = background
    }

    /// The checks every generator makes before spending a render.
    public func validate() throws {
        guard count >= 1 else { throw ImageFailure.invalidRequest("--count must be at least 1") }
        guard refs.count <= Self.maxRefs else {
            throw ImageFailure.invalidRequest("a render takes at most \(Self.maxRefs) reference images")
        }
        for ref in refs where !ProjectStore.isRegularFile(ref.path) {
            throw ImageFailure.invalidRequest("reference image not found: \(ref.path)")
        }
    }
}

/// Tokens a render spent, as the provider counts them.
public struct ImageUsage: Hashable, Sendable {
    public var input: Int
    public var cached: Int
    public var output: Int

    public init(input: Int, cached: Int, output: Int) {
        self.input = input
        self.cached = cached
        self.output = output
    }

    init(json: [String: Any]) {
        func int(_ key: String) -> Int { (json[key] as? NSNumber)?.intValue ?? 0 }
        self.init(input: int("input_tokens"), cached: int("cached_input_tokens"), output: int("output_tokens"))
    }
}

public struct ImageResult: Sendable {
    /// The images in the order they were made, in `outputDir`. Can be more than asked.
    public var images: [URL]
    public var outputDir: URL
    /// Wall time of the whole render, retries included.
    public var seconds: Double
    /// The model that made the images.
    public var model: String
    public var usage: ImageUsage?
    /// What the provider charged, in US dollars, when it says.
    public var cost: Double?
    /// Codex's thread, for its log.
    public var threadID: String?
    /// Codex's agent messages, usually just "DONE".
    public var messages: [String]

    public init(
        images: [URL], outputDir: URL, seconds: Double, model: String, usage: ImageUsage? = nil,
        cost: Double? = nil, threadID: String? = nil, messages: [String] = []
    ) {
        self.images = images
        self.outputDir = outputDir
        self.seconds = seconds
        self.model = model
        self.usage = usage
        self.cost = cost
        self.threadID = threadID
        self.messages = messages
    }
}

public enum ImageFailure: Error, CustomStringConvertible, LocalizedError {
    /// The generator can't start: Codex isn't installed, or no key reaches the API.
    case unavailable(String)
    case invalidRequest(String)
    /// The render ran and made no image; the text says why.
    case noImage(String)
    /// The provider refuses every render until something changes: a plan's image limit, or
    /// an account out of credit. Ends a run at once, with exit status 3.
    case limit(RenderLimit)

    public var description: String {
        switch self {
        case .unavailable(let message), .invalidRequest(let message), .noImage(let message): message
        case .limit(let limit): limit.message()
        }
    }

    public var errorDescription: String? { description }
}

/// Copies `staged` into `outputDir` (a fresh temp folder when nil) as `image.png` or
/// `image-1.png` … , cloning on APFS. Shared by the generators that stage files elsewhere.
func collect(_ staged: [URL], count: Int, into outputDir: URL?) throws -> (dir: URL, images: [URL]) {
    let dir = try outputDir ?? Subprocess.makeTempDirectory(prefix: "rimlight-gen-")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var images: [URL] = []
    for (index, source) in staged.enumerated() {
        let dest = dir.appending(
            path: ImageNames.output(index: index, count: count, ext: source.pathExtension.lowercased()),
            directoryHint: .notDirectory)
        try? FileManager.default.removeItem(at: dest)
        do { try FileManager.default.copyItem(at: source, to: dest) } catch {
            throw StoreError.io("Cannot copy \(source.path) to \(dest.path): \(error.localizedDescription)")
        }
        images.append(dest)
    }
    return (dir, images)
}

/// How renders and their variants are named.
public enum ImageNames {
    /// `image.png` for a single image, `image-1.png` … `image-N.png` for variants; extras keep
    /// counting past the request.
    public static func output(index: Int, count: Int, ext: String) -> String {
        let ext = ext.isEmpty ? "png" : ext
        return count == 1 && index == 0 ? "image.\(ext)" : "image-\(index + 1).\(ext)"
    }

    /// The slug of variant `index` (0-based) of `count`: the base for one, `<base>-N` for several.
    public static func variantSlug(_ base: String, index: Int, count: Int) -> String {
        count == 1 ? base : "\(base)-\(index + 1)"
    }

    /// The title of variant `index` (0-based) of `count`: the base for one, `<base> N` for several.
    public static func variantTitle(_ base: String, index: Int, count: Int) -> String {
        count == 1 ? base : "\(base) \(index + 1)"
    }
}
