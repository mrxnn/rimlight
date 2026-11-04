import Foundation

/// Generates or edits images through the Codex CLI's built-in `image_gen` tool, billed to the
/// user's ChatGPT plan. A port of the codex-imagegen skill's `codex_imagegen.py`.
///
/// Codex writes every image it generates to `$CODEX_HOME/generated_images/<thread_id>/`, and
/// `codex exec --json` announces the thread id in its first event. One headless turn that only
/// calls the image tool runs in a read-only sandbox, then the staged files are copied out.
public struct CodexImageGen: ImageGenerator {
    public static let defaultModel = "gpt-6-luna"
    public static let defaultEffort = "low"
    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp"]
    /// What `icon.json` records as `generator.tool`.
    public static let toolName = ImageProvider.codex.tool
    /// The model name that leaves the choice to Codex.
    public static let codexDefault = "default"

    public var tool: String { Self.toolName }

    public var environment: [String: String]
    /// Progress notes, such as the retry on a rejected model. The CLI prints them to stderr.
    public var onNote: @Sendable (String) -> Void

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        onNote: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.environment = environment
        self.onNote = onNote
    }

    /// `$CODEX_HOME`, else `~/.codex`.
    public var codexHome: URL { Self.codexHome(environment: environment) }

    /// `$CODEX_HOME` in `environment`, else `~/.codex`.
    public static func codexHome(environment: [String: String]) -> URL {
        if let home = environment["CODEX_HOME"].nonEmpty {
            return URL(filePath: (home as NSString).expandingTildeInPath, directoryHint: .isDirectory)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex", directoryHint: .isDirectory)
    }

    /// The orchestrator model and effort for `request`: its own, else `CODEX_IMAGEGEN_MODEL`
    /// and `CODEX_IMAGEGEN_EFFORT`, else gpt-6-luna and low.
    public func settings(for request: ImageRequest) -> (model: String, effort: String) {
        (
            request.model.nonEmpty ?? environment["CODEX_IMAGEGEN_MODEL"].nonEmpty ?? Self.defaultModel,
            request.effort.nonEmpty ?? environment["CODEX_IMAGEGEN_EFFORT"].nonEmpty ?? Self.defaultEffort
        )
    }

    // MARK: Run

    /// Blocks for the whole Codex turn, typically 40 to 60 seconds. Throws `ImageFailure`.
    public func run(_ request: ImageRequest) throws -> ImageResult {
        try request.validate()
        guard let path = codexPATH() else {
            throw ImageFailure.unavailable("codex CLI not found on PATH (npm i -g @openai/codex, then codex login)")
        }
        var env = environment
        env["PATH"] = path

        let instruction = Self.instruction(prompt: request.prompt, count: request.count, refs: request.refs.map(\.path))
        let clock = ContinuousClock()
        let started = clock.now
        let resolved = settings(for: request)
        var model = resolved.model
        let effort = resolved.effort
        var attempt = try runCodex(instruction, model: model, effort: effort, timeout: request.timeout, env: env)
        var staged = stagedImages(thread: attempt.transcript.threadID)
        try checkLimit(staged, attempt)

        // A retired or unavailable orchestrator model fails before any image is made; retry
        // once on Codex's own default model instead of failing the request.
        if staged.isEmpty, model != Self.codexDefault, Self.isModelRejection(attempt.errorText) {
            onNote("NOTE: model \(model) rejected, retrying with the Codex default model")
            model = Self.codexDefault
            attempt = try runCodex(instruction, model: model, effort: effort, timeout: request.timeout, env: env)
            staged = stagedImages(thread: attempt.transcript.threadID)
            try checkLimit(staged, attempt)
        }

        let elapsed = started.duration(to: clock.now)
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        guard !staged.isEmpty else {
            throw ImageFailure.noImage(
                Self.noImageText(
                    exitCode: attempt.status, seconds: seconds, lastMessage: attempt.transcript.messages.last,
                    errorText: attempt.errorText))
        }

        // An image went through, so any recorded limit has lifted.
        RenderLimit.clear(environment: environment)

        let (outputDir, images) = try collect(staged, count: request.count, into: request.outputDir)
        return ImageResult(
            images: images, outputDir: outputDir, seconds: seconds, model: model, usage: attempt.transcript.usage,
            threadID: attempt.transcript.threadID, messages: attempt.transcript.messages)
    }

    /// Why a Codex turn made no image, with the hint for a 401.
    static func noImageText(exitCode: Int32, seconds: Double, lastMessage: String?, errorText: String) -> String {
        var lines = ["no image was generated (codex exit \(exitCode), \(String(format: "%.0f", seconds))s)"]
        if let lastMessage { lines.append("Codex said: " + lastMessage) }
        if !errorText.isEmpty { lines.append(errorText) }
        if errorText.contains("401") { lines.append("HINT: check https://status.openai.com before debugging auth") }
        return lines.joined(separator: "\n")
    }

    // MARK: Pieces, public for tests

    /// The instruction for the Codex agent, word for word the script's `build_instruction`.
    public static func instruction(prompt: String, count: Int, refs: [String]) -> String {
        let calls = count == 1 ? "exactly once" : "\(count) times"
        var refClause = ""
        if !refs.isEmpty {
            let list = "[" + refs.map(pythonJSONString).joined(separator: ", ") + "]"
            refClause = " and referenced_image_paths=\(list) (Image 1 is the first path)"
        }
        return "Call your image generation tool \(calls), passing the prompt below verbatim\(refClause). "
            + "Do not read skill files, run shell commands, or save, copy or move anything; "
            + "the caller collects the output. Reply DONE when the last call returns.\n\n"
            + "Prompt:\n\(prompt)"
    }

    /// The arguments after `codex`.
    public static func arguments(instruction: String, model: String, effort: String, workdir: String) -> [String] {
        var args = [
            "exec",
            "--ignore-user-config",  // skip plugins and MCP servers from config.toml; auth still loads
            "--skip-git-repo-check",
            "--ephemeral",
            "--sandbox", "read-only",
            "-c", "approval_policy=\"never\"",
            "--json",
        ]
        if !model.isEmpty, model != codexDefault {
            args += ["-m", model, "-c", "model_reasoning_effort=\"\(effort)\""]
        }
        args += ["-C", workdir, "--", instruction]
        return args
    }

    /// Codex's way of saying the orchestrator model is gone or unknown.
    public static func isModelRejection(_ text: String) -> Bool {
        guard let regex = try? Regex(
            #"model.{0,80}(not supported|does not exist|not found|unknown|requires a newer|invalid)"#)
        else { return false }
        return text.contains(regex.ignoresCase())
    }

    // MARK: Private

    /// No image and Codex's usage-limit error: records the limit for the app and throws it,
    /// so no retry is spent on a refusal.
    private func checkLimit(_ staged: [URL], _ attempt: Attempt) throws {
        guard staged.isEmpty, let limit = RenderLimit.parseCodex(attempt.errorText) else { return }
        RenderLimit.record(limit, environment: environment)
        throw ImageFailure.limit(limit)
    }

    private struct Attempt {
        var transcript: CodexTranscript
        var status: Int32
        var errorText: String
    }

    private func runCodex(
        _ instruction: String, model: String, effort: String, timeout: TimeInterval, env: [String: String]
    ) throws -> Attempt {
        let workdir = try Subprocess.makeTempDirectory(prefix: "codex-imagegen-")
        defer { try? FileManager.default.removeItem(at: workdir) }
        let args = ["codex"] + Self.arguments(instruction: instruction, model: model, effort: effort, workdir: workdir.path)
        let output: Subprocess.Output
        do {
            output = try Subprocess.run(URL(filePath: "/usr/bin/env"), args, environment: env, timeout: timeout)
        } catch {
            throw ImageFailure.unavailable("Cannot start codex: \(error.localizedDescription)")
        }
        let transcript = CodexTranscript(CodexEvent.parseAll(output.stdout))
        var errors = transcript.errors
        if output.timedOut { errors.append("timed out after \(Int(timeout))s") }
        let stderrTail = String(String(decoding: output.stderr, as: UTF8.self).suffix(2000))
        let errorText = (errors + [stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)])
            .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return Attempt(transcript: transcript, status: output.status, errorText: errorText)
    }

    /// The images in `generated_images/<thread>/`, oldest first.
    func stagedImages(thread: String?) -> [URL] {
        guard let thread, !thread.isEmpty else { return [] }
        let folder = codexHome.appending(path: "generated_images", directoryHint: .isDirectory)
            .appending(path: thread, directoryHint: .isDirectory)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        return names
            .filter { Self.imageExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .map { folder.appending(path: $0, directoryHint: .notDirectory) }
            .map { (url: $0, mtime: FileStamp.of($0)?.mtimeNS ?? 0) }
            .sorted { ($0.mtime, $0.url.lastPathComponent) < ($1.mtime, $1.url.lastPathComponent) }
            .map(\.url)
    }

    /// A PATH on which `codex` resolves: the environment's own, else the login shell's.
    func codexPATH() -> String? {
        let path = environment["PATH"] ?? ""
        if ExecutableSearch.find("codex", in: path) != nil { return path }
        if let login = ExecutableSearch.loginShellPATH(environment: environment),
            ExecutableSearch.find("codex", in: login) != nil
        {
            return login
        }
        return nil
    }

    /// `json.dumps` of a string with Python's defaults: ASCII only, slashes left alone.
    static func pythonJSONString(_ s: String) -> String {
        var out = "\""
        for unit in s.utf16 {
            switch unit {
            case 0x22: out += "\\\""
            case 0x5C: out += "\\\\"
            case 0x0A: out += "\\n"
            case 0x0D: out += "\\r"
            case 0x09: out += "\\t"
            case 0x08: out += "\\b"
            case 0x0C: out += "\\f"
            case 0x20..<0x7F: out.unicodeScalars.append(Unicode.Scalar(UInt8(unit)))
            default: out += String(format: "\\u%04x", unit)
            }
        }
        return out + "\""
    }
}

extension Optional where Wrapped == String {
    /// nil for nil, empty or whitespace-only strings.
    var nonEmpty: String? {
        guard let s = self?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}
