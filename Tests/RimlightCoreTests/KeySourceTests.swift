import Foundation
import Testing

@testable import RimlightCore

@Suite struct KeySourceTests {
    /// A one-shot stand-in for the app: answers one connection with `reply` and records the
    /// request line it read.
    final class FakeApp: @unchecked Sendable {
        let path: String
        private let fd: Int32
        private(set) var request = Data()
        private let done = DispatchSemaphore(value: 0)

        init(_ dir: URL, reply: KeySource.Response, delay: TimeInterval = 0) throws {
            // A socket path is capped at 104 bytes, which a temp folder can pass.
            path = "/tmp/rl-\(UUID().uuidString.prefix(8)).sock"
            fd = socket(AF_UNIX, SOCK_STREAM, 0)
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let bytes = Array(path.utf8)
            withUnsafeMutableBytes(of: &address.sun_path) { raw in
                raw.copyBytes(from: bytes)
                raw[bytes.count] = 0
            }
            address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            try #require(bound == 0 && listen(fd, 1) == 0)
            let answer = try JSONEncoder().encode(reply) + Data("\n".utf8)
            Thread.detachNewThread { [self] in
                let client = accept(fd, nil, nil)
                // The caller may have given up; a write then must not kill the test run.
                var on: Int32 = 1
                setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
                var buffer = [UInt8](repeating: 0, count: 256)
                while !request.contains(UInt8(ascii: "\n")) {
                    let n = read(client, &buffer, buffer.count)
                    if n <= 0 { break }
                    request.append(contentsOf: buffer[..<n])
                }
                // An app behind a dialog answers late.
                Thread.sleep(forTimeInterval: delay)
                _ = answer.withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
                close(client)
                done.signal()
            }
        }

        func finish() {
            _ = done.wait(timeout: .now() + 5)
            close(fd)
            unlink(path)
        }
    }

    @Test func theAppsKeyComesFirst() throws {
        try withTempDir { dir in
            let app = try FakeApp(dir, reply: .init(key: "sk-app"))
            let env = ["RIMLIGHT_KEY_SOCKET": app.path, "RIMLIGHT_OPENAI_API_KEY": "sk-env"]
            let found = try #require(KeySource.key(for: .openai, environment: env))
            app.finish()
            #expect(found.key == "sk-app" && found.origin == .app)
            let sent = try JSONDecoder().decode(KeySource.Request.self, from: app.request.prefix { $0 != 10 })
            #expect(sent.provider == "openai")
        }
    }

    @Test func aRefusalFallsBackToTheVariable() throws {
        try withTempDir { dir in
            let app = try FakeApp(dir, reply: .init(error: "no OpenAI key in Rimlight"))
            let env = ["RIMLIGHT_KEY_SOCKET": app.path, "RIMLIGHT_OPENAI_API_KEY": "sk-env"]
            let found = try #require(KeySource.key(for: .openai, environment: env))
            app.finish()
            #expect(found.key == "sk-env" && found.origin == .environment)
        }
    }

    @Test func noAppAndNoVariableIsNoKey() {
        let env = ["RIMLIGHT_KEY_SOCKET": "/nonexistent/k.sock", "OPENAI_API_KEY": "sk-not-ours"]
        #expect(KeySource.key(for: .openai, environment: env) == nil)
        #expect(KeySource.askApp(provider: .openai, environment: env) == nil)
    }

    /// An app behind a Keychain dialog answers late; the render waits instead of giving up.
    @Test func aSlowAppIsWaitedFor() throws {
        try withTempDir { dir in
            let app = try FakeApp(dir, reply: .init(key: "sk-late"), delay: 0.6)
            var told = 0
            let found = KeySource.lookup(
                .openrouter, environment: ["RIMLIGHT_KEY_SOCKET": app.path], patience: 5, slowAfter: 0.2, onWait: { told += 1 })
            app.finish()
            #expect(found == .found("sk-late", .app))
            #expect(told == 1)
        }
    }

    /// An app that never answers is named as the reason, not a missing key.
    @Test func anAppThatNeverAnswersSaysSo() throws {
        try withTempDir { dir in
            let app = try FakeApp(dir, reply: .init(key: "sk-too-late"), delay: 2)
            let found = KeySource.lookup(
                .openrouter, environment: ["RIMLIGHT_KEY_SOCKET": app.path], patience: 0.5, slowAfter: 0.2)
            app.finish()
            guard case .missing(let why) = found else { Issue.record("expected no key"); return }
            #expect(why.hasPrefix("Rimlight didn't hand over the OpenRouter key"))
        }
    }

    @Test func aRefusalSaysWhy() throws {
        try withTempDir { dir in
            let app = try FakeApp(dir, reply: .init(error: "No OpenRouter key in Rimlight's settings"))
            let found = KeySource.lookup(.openrouter, environment: ["RIMLIGHT_KEY_SOCKET": app.path])
            app.finish()
            #expect(found == .missing(
                "No OpenRouter key in Rimlight's settings. Add one in Rimlight's settings, or set RIMLIGHT_OPENROUTER_API_KEY in a terminal."))
        }
    }
}
