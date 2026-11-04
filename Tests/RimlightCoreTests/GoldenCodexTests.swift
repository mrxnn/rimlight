import Foundation
import Testing

@testable import RimlightCore

/// What Codex receives, as literals, so provider work cannot change it silently. A deliberate
/// change updates these literals in the same commit.
@Suite struct GoldenCodexTests {
    static let instruction = """
        Call your image generation tool 2 times, passing the prompt below verbatim and \
        referenced_image_paths=["/refs/a.png", "/refs/b.png"] (Image 1 is the first path). \
        Do not read skill files, run shell commands, or save, copy or move anything; \
        the caller collects the output. Reply DONE when the last call returns.

        Prompt:
        P
        """

    static let arguments = [
        "exec", "--ignore-user-config", "--skip-git-repo-check", "--ephemeral", "--sandbox", "read-only",
        "-c", #"approval_policy="never""#, "--json", "-m", "gpt-6-luna", "-c", #"model_reasoning_effort="low""#,
        "-C", "/w", "--", instruction,
    ]

    @Test func templateNote() {
        #expect(TileShape.templateNote(image: 3) == """
            Image 3 is the tile template: a flat grey silhouette of the icon tile's exact outline, \
            corner curve, size and position in the frame. The icon's tile fills that silhouette exactly, \
            edge to edge, with the same outline, corner curve, size and position. Do not copy the \
            template's grey, do not draw its outline, and do not draw a smaller tile inside it. \
            Everything outside the silhouette is fully transparent.
            """)
    }

    @Test func transparencyFixPrompt() {
        #expect(TransparencyFix.prompt == """
            Edit Image 1. Remove the backdrop, the checkerboard and any cast shadow so that everything \
            outside the icon tile is fully transparent: a real alpha channel, no painted background of any \
            kind. Keep the icon tile itself and everything on it identical: its shape, size, position, \
            materials, colours, lighting, camera angle, framing and the image size. Output a PNG with \
            transparency.
            """)
    }

    /// The request's instruction and argv, built the way `run` builds them, with the default
    /// model and effort and `/w` as the workdir.
    @Test func requestInstructionAndArguments() {
        let refs = ["/refs/a.png", "/refs/b.png"].map { URL(filePath: $0, directoryHint: .notDirectory) }
        let request = ImageRequest(prompt: "P", refs: refs, count: 2)
        let settings = CodexImageGen(environment: [:]).settings(for: request)
        let instruction = CodexImageGen.instruction(
            prompt: request.prompt, count: request.count, refs: request.refs.map(\.path))
        #expect(instruction == Self.instruction)
        #expect(
            CodexImageGen.arguments(instruction: instruction, model: settings.model, effort: settings.effort, workdir: "/w")
                == Self.arguments)
    }

    /// The same request run against the fake codex: its recorded argv, with the temp folder
    /// cut from the ref paths and the workdir read as `/w`, is the literal.
    @Test func runSendsTheArguments() throws {
        try withTempDir { dir in
            let fake = try CodexImageGenTests.FakeCodex(dir)
            let refsDir = dir.appending(path: "refs", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: refsDir, withIntermediateDirectories: true)
            let refs = ["a.png", "b.png"].map { refsDir.appending(path: $0, directoryHint: .notDirectory) }
            for ref in refs { try TinyPNG.make(.rgba).write(to: ref) }
            let gen = CodexImageGen(environment: fake.environment("ok", images: 2))
            let out = dir.appending(path: "out", directoryHint: .isDirectory)
            _ = try gen.run(.init(prompt: "P", refs: refs, count: 2, outputDir: out))

            var args = try fake.arguments(call: 1).map { $0.replacingOccurrences(of: dir.path, with: "") }
            let workdir = try #require(args.firstIndex(of: "-C")) + 1
            try #require(workdir < args.count)
            args[workdir] = "/w"
            #expect(args == Self.arguments)
        }
    }
}
