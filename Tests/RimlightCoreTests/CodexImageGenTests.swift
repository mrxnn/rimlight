import Foundation
import Synchronization
import Testing

@testable import RimlightCore

@Suite struct CodexImageGenTests {
    @Test func instructionMatchesTheScript() {
        #expect(CodexImageGen.instruction(prompt: "A red circle.", count: 1, refs: []) == """
            Call your image generation tool exactly once, passing the prompt below verbatim. \
            Do not read skill files, run shell commands, or save, copy or move anything; \
            the caller collects the output. Reply DONE when the last call returns.

            Prompt:
            A red circle.
            """)
        let withRefs = CodexImageGen.instruction(prompt: "P", count: 3, refs: ["/a/icon.png", "/b/Café \"x\".png"])
        #expect(withRefs.hasPrefix(
            #"Call your image generation tool 3 times, passing the prompt below verbatim and referenced_image_paths=["/a/icon.png", "/b/Caf\u00e9 \"x\".png"] (Image 1 is the first path). "#
        ))
        #expect(withRefs.hasSuffix("\n\nPrompt:\nP"))
    }

    @Test func argumentsMatchTheScript() {
        #expect(CodexImageGen.arguments(instruction: "I", model: "gpt-6-luna", effort: "low", workdir: "/w") == [
            "exec", "--ignore-user-config", "--skip-git-repo-check", "--ephemeral", "--sandbox", "read-only",
            "-c", #"approval_policy="never""#, "--json", "-m", "gpt-6-luna", "-c", #"model_reasoning_effort="low""#,
            "-C", "/w", "--", "I",
        ])
        #expect(CodexImageGen.arguments(instruction: "I", model: "default", effort: "low", workdir: "/w") == [
            "exec", "--ignore-user-config", "--skip-git-repo-check", "--ephemeral", "--sandbox", "read-only",
            "-c", #"approval_policy="never""#, "--json", "-C", "/w", "--", "I",
        ])
    }

    @Test func modelAndEffortDefaultsComeFromTheEnvironment() {
        let plain = CodexImageGen(environment: [:]).settings(for: ImageRequest(prompt: "p"))
        #expect(plain.model == "gpt-6-luna")
        #expect(plain.effort == "low")
        #expect(ImageRequest(prompt: "p").timeout == 540)
        let gen = CodexImageGen(environment: ["CODEX_IMAGEGEN_MODEL": "gpt-x", "CODEX_IMAGEGEN_EFFORT": "medium"])
        #expect(gen.settings(for: ImageRequest(prompt: "p")) == ("gpt-x", "medium"))
        #expect(gen.settings(for: ImageRequest(prompt: "p", model: "m")).model == "m")
    }

    @Test func parsesTheRecordedRun() throws {
        let url = try #require(Bundle.module.url(forResource: "codex-exec", withExtension: "jsonl", subdirectory: "Fixtures"))
        let events = CodexEvent.parseAll(try Data(contentsOf: url))
        #expect(events == [
            .threadStarted("01a1257b-8ad5-7670-afe0-981edadd4c82"),
            .other("turn.started"),
            .agentMessage("DONE"),
            .turnCompleted(ImageUsage(input: 30511, cached: 25088, output: 93)),
        ])
        let transcript = CodexTranscript(events)
        #expect(transcript.threadID == "01a1257b-8ad5-7670-afe0-981edadd4c82")
        #expect(transcript.messages == ["DONE"])
        #expect(transcript.errors.isEmpty)
    }

    @Test func parsesFailures() {
        #expect(CodexEvent.parse(#"{"type":"turn.failed","error":{"message":"401 Unauthorized"}}"#)
            == .failure(#"{"message":"401 Unauthorized"}"#))
        #expect(CodexEvent.parse(#"{"type":"error","message":"boom"}"#) == .failure(#""boom""#))
        #expect(CodexEvent.parse(#"{"type":"error","error":null,"message":""}"#)
            == .failure(#"{"error":null,"message":"","type":"error"}"#))
        #expect(CodexEvent.parse("Reading additional input from stdin...") == nil)
        #expect(CodexEvent.parse(#"{"no":"type"}"#) == nil)
        #expect(CodexEvent.parse(#"{"type":"item.completed","item":{"type":"reasoning"}}"#) == .other("item.completed"))
    }

    @Test func outputNames() {
        #expect(ImageNames.output(index: 0, count: 1, ext: "png") == "image.png")
        #expect(ImageNames.output(index: 1, count: 1, ext: "png") == "image-2.png")
        #expect((0..<3).map { ImageNames.output(index: $0, count: 3, ext: "png") }
            == ["image-1.png", "image-2.png", "image-3.png"])
        #expect(ImageNames.output(index: 3, count: 3, ext: "webp") == "image-4.webp")
        #expect(ImageNames.variantSlug("counter", index: 0, count: 1) == "counter")
        #expect((0..<3).map { ImageNames.variantSlug("counter", index: $0, count: 3) }
            == ["counter-1", "counter-2", "counter-3"])
        #expect(ImageNames.variantTitle("Counter", index: 1, count: 2) == "Counter 2")
        #expect(ImageNames.variantTitle("Counter", index: 0, count: 1) == "Counter")
    }

    @Test func modelRejection() {
        #expect(CodexImageGen.isModelRejection(#""The model gpt-6-luna does not exist or you do not have access""#))
        #expect(CodexImageGen.isModelRejection("Model 'x' is not supported when using Codex with a ChatGPT account"))
        #expect(!CodexImageGen.isModelRejection("unexpected status 401 Unauthorized"))
        #expect(!CodexImageGen.isModelRejection("model\nnot found"))
    }

    @Test func failureText() {
        let failure = ImageFailure.noImage(CodexImageGen.noImageText(
            exitCode: 1, seconds: 12.4, lastMessage: "I could not", errorText: #"{"message":"401 Unauthorized"}"#))
        #expect(failure.description == """
            no image was generated (codex exit 1, 12s)
            Codex said: I could not
            {"message":"401 Unauthorized"}
            HINT: check https://status.openai.com before debugging auth
            """)
    }

    @Test func stagedImagesOldestFirst() throws {
        try withTempDir { dir in
            let folder = dir.appending(path: "generated_images/t1", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (name, age) in [("b.png", 10.0), ("a.webp", 20.0), ("notes.txt", 30.0), ("c.PNG", 5.0)] {
                let url = folder.appending(path: name)
                try Data([1]).write(to: url)
                try FileManager.default.setAttributes(
                    [.modificationDate: Date(timeIntervalSinceNow: -age)], ofItemAtPath: url.path)
            }
            let gen = CodexImageGen(environment: ["CODEX_HOME": dir.path])
            #expect(gen.stagedImages(thread: "t1").map(\.lastPathComponent) == ["a.webp", "b.png", "c.PNG"])
            #expect(gen.stagedImages(thread: "nope").isEmpty)
            #expect(gen.stagedImages(thread: nil).isEmpty)
        }
    }

    // MARK: End to end against a fake codex

    /// A `codex` shell script that records each call's argv and plays one scenario.
    struct FakeCodex {
        let dir: URL
        var home: URL { dir.appending(path: "codex-home", directoryHint: .isDirectory) }

        init(_ dir: URL) throws {
            self.dir = dir
            let bin = dir.appending(path: "bin", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            try TinyPNG.make(.rgba).write(to: dir.appending(path: "render.png"))
            let script = bin.appending(path: "codex")
            try Data(Self.script.utf8).write(to: script)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        }

        func environment(_ mode: String, images: Int = 1) -> [String: String] {
            [
                "PATH": dir.appending(path: "bin").path + ":/usr/bin:/bin", "CODEX_HOME": home.path,
                "FAKE_DIR": dir.path, "FAKE_MODE": mode, "FAKE_IMAGES": String(images),
                // The limit record goes here, never to the real ~/.local/state.
                "RIMLIGHT_STATE_DIR": dir.appending(path: "state").path,
            ]
        }

        /// The argv of call `n` (1-based), after `codex`.
        func arguments(call n: Int) throws -> [String] {
            let data = try Data(contentsOf: dir.appending(path: "calls/\(n)"))
            return data.split(separator: 0, omittingEmptySubsequences: false).dropLast().map {
                String(decoding: $0, as: UTF8.self)
            }
        }

        static let script = #"""
            #!/bin/sh
            mkdir -p "$FAKE_DIR/calls"
            n=$(( $(ls "$FAKE_DIR/calls" | wc -l) + 1 ))
            printf '%s\0' "$@" > "$FAKE_DIR/calls/$n"
            echo "Reading additional input from stdin..." >&2
            ok() {
              thread="thread-$n"
              mkdir -p "$CODEX_HOME/generated_images/$thread"
              i=1
              while [ "$i" -le "$FAKE_IMAGES" ]; do
                cp "$FAKE_DIR/render.png" "$CODEX_HOME/generated_images/$thread/exec-$i.png"
                i=$((i + 1))
              done
              echo '{"type":"thread.started","thread_id":"'"$thread"'"}'
              echo '{"type":"turn.started"}'
              echo '{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"DONE"}}'
              echo '{"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":4,"output_tokens":2}}'
            }
            case "$FAKE_MODE" in
              ok) ok ;;
              reject-then-ok)
                if [ "$n" = 1 ]; then
                  echo '{"type":"thread.started","thread_id":"rejected"}'
                  echo '{"type":"error","message":"The model gpt-6-luna does not exist or you do not have access to it."}'
                  exit 1
                fi
                ok ;;
              unauthorized)
                echo '{"type":"thread.started","thread_id":"denied"}'
                echo '{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"I could not."}}'
                echo '{"type":"turn.failed","error":{"message":"unexpected status 401 Unauthorized"}}'
                exit 1 ;;
              limit)
                echo '{"type":"thread.started","thread_id":"limited"}'
                echo '{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"DONE"}}'
                echo '2026-10-13T08:06:27.721362Z ERROR codex_core::tools::router: error=image generation failed: http 429 Too Many Requests: Some("{\"error\":{\"type\":\"usage_limit_reached\",\"message\":\"The usage limit has been reached\",\"plan_type\":\"plus\",\"resets_at\":1791905662,\"eligible_promo\":null,\"limit_window_minutes\":1440,\"resets_in_seconds\":26875}}")' >&2
                exit 0 ;;
              sleep) exec sleep 30 ;;
            esac
            """#
    }

    @Test func runCollectsImagesIntoTheOutputFolder() throws {
        try withTempDir { dir in
            let fake = try FakeCodex(dir)
            let ref = dir.appending(path: "render.png")
            let out = dir.appending(path: "out", directoryHint: .isDirectory)
            let gen = CodexImageGen(environment: fake.environment("ok", images: 2))
            let result = try gen.run(.init(prompt: "Two dials.", refs: [ref], count: 2, outputDir: out))

            #expect(result.images.map(\.lastPathComponent) == ["image-1.png", "image-2.png"])
            #expect(result.images.allSatisfy { $0.deletingLastPathComponent().path == out.path })
            #expect(try Data(contentsOf: result.images[0]) == TinyPNG.make(.rgba))
            #expect(result.threadID == "thread-1")
            #expect(result.usage == ImageUsage(input: 10, cached: 4, output: 2))
            #expect(result.messages == ["DONE"])
            #expect(result.model == "gpt-6-luna")

            let args = try fake.arguments(call: 1)
            let workdir = try #require(args.firstIndex(of: "-C").map { args[$0 + 1] })
            #expect(args == CodexImageGen.arguments(
                instruction: CodexImageGen.instruction(prompt: "Two dials.", count: 2, refs: [ref.path]),
                model: "gpt-6-luna", effort: "low", workdir: workdir))
            #expect(!FileManager.default.fileExists(atPath: workdir), "the codex workdir is removed")
        }
    }

    @Test func retriesOnceOnARejectedModel() throws {
        try withTempDir { dir in
            let fake = try FakeCodex(dir)
            let notes = Mutex<[String]>([])
            let gen = CodexImageGen(environment: fake.environment("reject-then-ok")) { note in
                notes.withLock { $0.append(note) }
            }
            let result = try gen.run(.init(prompt: "p"))
            #expect(result.images.map(\.lastPathComponent) == ["image.png"])
            #expect(result.model == "default")
            #expect(try fake.arguments(call: 1).contains("-m"))
            #expect(try !fake.arguments(call: 2).contains("-m"))
            #expect(notes.withLock { $0 } == ["NOTE: model gpt-6-luna rejected, retrying with the Codex default model"])
            try FileManager.default.removeItem(at: result.outputDir)
        }
    }

    @Test func reportsWhyNoImageCame() throws {
        try withTempDir { dir in
            let fake = try FakeCodex(dir)
            let gen = CodexImageGen(environment: fake.environment("unauthorized"))
            do {
                _ = try gen.run(.init(prompt: "p"))
                Issue.record("expected a failure")
            } catch let ImageFailure.noImage(text) {
                #expect(text.hasPrefix("no image was generated (codex exit 1, "))
                #expect(text.hasSuffix("""
                    s)
                    Codex said: I could not.
                    {"message":"unexpected status 401 Unauthorized"}
                    Reading additional input from stdin...
                    HINT: check https://status.openai.com before debugging auth
                    """))
            }
            #expect(try fake.arguments(call: 1).contains("-m"))
            #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "calls/2").path), "no retry on a 401")
        }
    }

    @Test func killsCodexAtTheTimeout() throws {
        try withTempDir { dir in
            let fake = try FakeCodex(dir)
            let gen = CodexImageGen(environment: fake.environment("sleep"))
            let started = Date()
            #expect {
                _ = try gen.run(.init(prompt: "p", timeout: 1))
            } throws: { error in
                guard case let ImageFailure.noImage(text) = error else { return false }
                return text.contains("\ntimed out after 1s")
            }
            #expect(Date().timeIntervalSince(started) < 10)
        }
    }

    @Test func missingCodex() throws {
        let gen = CodexImageGen(environment: ["PATH": "/nonexistent", "SHELL": "/usr/bin/false"])
        #expect(throws: ImageFailure.self) { try gen.run(.init(prompt: "p")) }
        #expect {
            try gen.run(.init(prompt: "p"))
        } throws: { "\($0)" == "codex CLI not found on PATH (npm i -g @openai/codex, then codex login)" }
    }

    @Test func rejectsBadRequests() throws {
        let gen = CodexImageGen(environment: ["PATH": "/nonexistent", "SHELL": "/usr/bin/false"])
        #expect(throws: ImageFailure.self) { try gen.run(.init(prompt: "p", count: 0)) }
        let six = (0..<6).map { URL(filePath: "/tmp/\($0).png") }
        #expect(throws: ImageFailure.self) { try gen.run(.init(prompt: "p", refs: six)) }
        #expect(throws: ImageFailure.self) {
            try gen.run(.init(prompt: "p", refs: [URL(filePath: "/nonexistent.png")]))
        }
    }
}
