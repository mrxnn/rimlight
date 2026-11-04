import Foundation
import Testing

@testable import RimlightCore

@Suite struct RenderLimitTests {
    /// The line Codex printed on 2026-10-13 when the Plus plan's image limit was reached.
    static let refusal = #"""
        2026-10-13T08:06:27.721362Z ERROR codex_core::tools::router: error=image generation failed: http 429 Too Many Requests: Some("{\"error\":{\"type\":\"usage_limit_reached\",\"message\":\"The usage limit has been reached\",\"plan_type\":\"plus\",\"resets_at\":1791905662,\"eligible_promo\":null,\"limit_window_minutes\":1440,\"resets_in_seconds\":26875}}")
        """#

    @Test func parsesCodexsRefusal() throws {
        let now = Date(timeIntervalSince1970: 1_791_905_662 - 26_875)
        let limit = try #require(RenderLimit.parseCodex(Self.refusal, now: now))
        #expect(limit.resetsAt == Date(timeIntervalSince1970: 1_791_905_662))
        #expect(limit.plan == "plus")
        let message = limit.message(now: now, timeZone: try #require(TimeZone(identifier: "Asia/Colombo")))
        #expect(message.hasPrefix("Codex's image limit on your ChatGPT Plus plan is reached. It resets at "))
        #expect(message.hasSuffix(", in 7 h 28 min. Renders fail until then."))
        // The same day, so no weekday between the time and "in".
        let time = message.split(separator: "It resets at ").last?.split(separator: ", in").first ?? ""
        #expect(!time.contains(" on "))
        let tomorrow = limit.message(
            now: now.addingTimeInterval(-24 * 3600), timeZone: try #require(TimeZone(identifier: "Asia/Colombo")))
        #expect(tomorrow.contains(" on Tuesday, in 31 h 28 min"))
    }

    @Test func unescapedJSONAndASecondsOnlyResetParseToo() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let plain = #"{"error":{"type":"usage_limit_reached","plan_type":"pro","resets_in_seconds":90}}"#
        let limit = try #require(RenderLimit.parseCodex(plain, now: now))
        #expect(limit.plan == "pro")
        #expect(limit.resetsAt == now.addingTimeInterval(90))
        #expect(limit.message(now: now).contains("in 2 min"))
        // No reset time: the message says so without a time.
        let bare = try #require(RenderLimit.parseCodex("error: usage_limit_reached", now: now))
        #expect(bare.resetsAt == nil && bare.plan == nil)
        #expect(bare.message(now: now) == "Codex's image limit on your ChatGPT plan is reached. Renders fail until it resets.")
    }

    @Test func otherErrorsAreNotALimit() {
        #expect(RenderLimit.parseCodex("unexpected status 401 Unauthorized") == nil)
        #expect(RenderLimit.parseCodex("http 429 Too Many Requests: rate_limit_exceeded") == nil)
        #expect(RenderLimit.parseCodex("") == nil)
    }

    @Test func theRecordHoldsUntilTheReset() throws {
        try withTempDir { dir in
            let env = ["RIMLIGHT_STATE_DIR": dir.appending(path: "state").path]
            let now = Date(timeIntervalSince1970: 2_000_000)
            #expect(RenderLimit.current(environment: env, now: now) == nil)
            RenderLimit.record(RenderLimit(resetsAt: now.addingTimeInterval(60), plan: "plus", recorded: now), environment: env)
            #expect(RenderLimit.current(environment: env, now: now)?.plan == "plus")
            #expect(RenderLimit.current(environment: env, now: now.addingTimeInterval(61)) == nil)
            // Without a reset time it holds a day.
            RenderLimit.record(RenderLimit(resetsAt: nil, plan: nil, recorded: now), environment: env)
            #expect(RenderLimit.current(environment: env, now: now.addingTimeInterval(23 * 3600)) != nil)
            #expect(RenderLimit.current(environment: env, now: now.addingTimeInterval(25 * 3600)) == nil)
            RenderLimit.clear(environment: env)
            #expect(!FileManager.default.fileExists(atPath: RenderLimit.stateURL(environment: env).path))
        }
    }

    @Test func stateFollowsXDGThenHome() {
        #expect(RenderLimit.stateURL(environment: ["XDG_STATE_HOME": "/x/state"]).path == "/x/state/rimlight/limit.json")
        #expect(RenderLimit.stateURL(environment: [:]).path.hasSuffix("/.local/state/rimlight/limit.json"))
    }

    /// A limit 0.7 recorded under its old name still holds, and decodes as Codex's.
    @Test func aLegacyRecordStillHolds() throws {
        try withTempDir { dir in
            let env = ["RIMLIGHT_STATE_DIR": dir.path]
            let now = Date(timeIntervalSince1970: 2_000_000)
            // 0.7's record had no provider.
            let limit = RenderLimit(resetsAt: now.addingTimeInterval(600), plan: "plus", recorded: now)
            var old = try #require(
                JSONSerialization.jsonObject(with: StateCoding.encoder().encode(limit)) as? [String: Any])
            old["provider"] = nil
            try JSONSerialization.data(withJSONObject: old).write(to: dir.appending(path: "codex-limit.json"))
            let read = try #require(RenderLimit.current(environment: env, now: now))
            #expect(read.provider == "codex" && read.plan == "plus")
            RenderLimit.clear(environment: env)
            #expect(RenderLimit.current(environment: env, now: now) == nil)
        }
    }

    @Test func anAPIRefusalNamesItsProvider() {
        let limit = RenderLimit(provider: "openai", resetsAt: nil, plan: nil, note: "You exceeded your current quota.", recorded: Date())
        #expect(limit.message() == "OpenAI refused the render: You exceeded your current quota. Renders fail until the account is sorted out.")
    }

    /// A refused render throws the limit and records it; the next render that works clears it.
    @Test func theGeneratorThrowsRecordsAndClearsTheLimit() throws {
        try withTempDir { dir in
            let fake = try CodexImageGenTests.FakeCodex(dir)
            let out = dir.appending(path: "out", directoryHint: .isDirectory)
            let limited = CodexImageGen(environment: fake.environment("limit"))
            #expect {
                _ = try limited.run(.init(prompt: "A dial.", outputDir: out))
            } throws: { error in
                guard case ImageFailure.limit(let limit) = error else { return false }
                return limit.plan == "plus" && limit.resetsAt == Date(timeIntervalSince1970: 1_791_905_662)
            }
            // No model retry is spent on a refusal.
            #expect(try fake.arguments(call: 1).isEmpty == false)
            #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "calls/2").path))
            let env = fake.environment("ok")
            #expect(FileManager.default.fileExists(atPath: RenderLimit.stateURL(environment: env).path))

            _ = try CodexImageGen(environment: env).run(.init(prompt: "A dial.", outputDir: out))
            #expect(!FileManager.default.fileExists(atPath: RenderLimit.stateURL(environment: env).path))
        }
    }

    /// A fix attempt Codex refuses ends the fix: no attempt after it is spent.
    @Test func aRefusedFixAttemptEndsTheFix() throws {
        try withTempDir { dir in
            let opaque = dir.appending(path: "opaque.png")
            try DrawnPNG.checkerboard().write(to: opaque)
            let probe = try #require(ImageProbe.read(opaque))
            let limit = RenderLimit(resetsAt: Date().addingTimeInterval(600), plan: "plus", recorded: Date())
            var calls = 0
            let outcome = TransparencyFix.run(
                opaque, probe: probe, original: ImageRequest(prompt: "A dial."), attempts: 3,
                render: { _, _ in
                    calls += 1
                    throw ImageFailure.limit(limit)
                })
            #expect(calls == 1)
            #expect(outcome.limit == limit)
            #expect(outcome.attempts.count == 1)
            #expect(!outcome.isFixed && outcome.image == opaque)
        }
    }
}
