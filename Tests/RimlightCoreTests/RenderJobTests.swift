import Foundation
import Testing

@testable import RimlightCore

@Suite struct RenderJobTests {
    private func marker(
        pid: Int32 = getpid(), hostPID: Int32? = nil, slug: String = "olive", mode: JobMarker.Mode = .generate,
        started: Date = .now
    ) -> JobMarker {
        JobMarker(pid: pid, hostPID: hostPID, set: "set-001", slug: slug, title: "Olive", mode: mode, started: started)
    }

    /// The pid of a process that has exited and been reaped.
    private func deadPID() throws -> Int32 {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        return process.processIdentifier
    }

    @Test func writeReadRemove() throws {
        try withTempDir { dir in
            let store = ProjectStore(projectRoot: dir)
            try store.create()
            #expect(store.readJobs().isEmpty)
            #expect(!FileManager.default.fileExists(atPath: store.jobsDir.path))

            let job = marker(hostPID: 4242, mode: .fix)
            try store.writeJob(job)
            let text = try String(contentsOf: store.jobURL(job.id), encoding: .utf8)
            #expect(text.contains("\"hostPID\" : 4242"))
            let read = store.readJobs()
            #expect(read.count == 1)
            #expect(read.first?.marker == job)
            #expect(read.first?.alive == true)
            #expect(read.first?.iconID == "set-001/olive")

            try store.writeJob(marker(slug: "plain"))
            #expect(try String(contentsOf: store.jobURL(store.readJobs()[1].id), encoding: .utf8).contains("\"hostPID\" : null"))
            #expect(store.readJobs().map(\.slug) == ["olive", "plain"])

            store.removeJob(job.id)
            store.removeJob(job.id)
            #expect(store.readJobs().map(\.slug) == ["plain"])
            #expect(store.pruneDeadJobs().isEmpty)
            // No temp file is left beside the markers.
            #expect(try FileManager.default.contentsOfDirectory(atPath: store.jobsDir.path).count == 1)
        }
    }

    @Test func deadPIDIsPruned() throws {
        try withTempDir { dir in
            let store = ProjectStore(projectRoot: dir)
            try store.create()
            let dead = marker(pid: try deadPID(), slug: "dead")
            let live = marker(slug: "live")
            try store.writeJob(dead)
            try store.writeJob(live)
            let read = Dictionary(uniqueKeysWithValues: store.readJobs().map { ($0.slug, $0.alive) })
            #expect(read == ["dead": false, "live": true])

            #expect(store.pruneDeadJobs() == [dead])
            #expect(store.readJobs().map(\.marker) == [live])
        }
    }

    @Test func livenessChecksThePID() throws {
        #expect(ProcessTree.isAlive(getpid(), startedBy: .now))
        #expect(!ProcessTree.isAlive(try deadPID(), startedBy: .now))
        #expect(!ProcessTree.isAlive(0, startedBy: .now))
        // The test process started long after this marker would have: a reused pid.
        #expect(!ProcessTree.isAlive(getpid(), startedBy: Date(timeIntervalSince1970: 1_000_000)))
    }

    @Test func landedComparesTheRecordWithTheStart() throws {
        try withTempDir { dir in
            let fixture = try StoreTests.Fixture(dir)
            let job = marker(slug: "olive")
            #expect(!fixture.store.jobLanded(job))
            try fixture.add("olive")
            #expect(fixture.store.jobLanded(job))
            #expect(!fixture.store.jobLanded(marker(slug: "olive", started: .now.addingTimeInterval(60))))
        }
    }

    @Test func walkFindsTheNearestAgent() {
        // pid -> (parent, agent, node or bun running a script)
        let table: [Int32: (parent: Int32, agent: ProcessTree.Agent?, script: Bool)] = [
            50: (40, nil, false), 40: (30, nil, false), 30: (20, .claude, false), 20: (10, .claude, false), 10: (1, nil, false),
            60: (55, nil, false), 55: (1, nil, false),
            70: (70, nil, false),
            // A render under npm's Codex: rimlight, zsh, the native app-server, npm's node script, the app.
            95: (94, nil, false), 94: (93, .codex, false), 93: (92, .codex, true), 92: (1, nil, false),
            // Under a native Codex (Homebrew, ChatGPT.app): nothing above it is a script.
            85: (84, nil, false), 84: (83, .codex, false), 83: (1, nil, false),
            // Claude Code run from Claude Code's shell: the nearer session, not its parent's.
            75: (74, nil, false), 74: (73, .claude, true), 73: (72, nil, false), 72: (1, .claude, true),
        ]
        let lookup = { (pid: Int32) in table[pid] }
        #expect(ProcessTree.nearest(from: 50, lookup: lookup)?.pid == 30)
        #expect(ProcessTree.nearest(from: 50, lookup: lookup)?.agent == .claude)
        #expect(ProcessTree.nearest(from: 30, lookup: lookup)?.pid == 20)
        // The process the app launched, npm's script, not the binary it started.
        #expect(ProcessTree.nearest(from: 95, lookup: lookup)?.pid == 93)
        #expect(ProcessTree.nearest(from: 95, lookup: lookup)?.agent == .codex)
        #expect(ProcessTree.nearest(from: 85, lookup: lookup)?.pid == 84)
        #expect(ProcessTree.nearest(from: 75, lookup: lookup)?.pid == 74)
        #expect(ProcessTree.nearest(from: 60, lookup: lookup) == nil)
        #expect(ProcessTree.nearest(from: 99, lookup: lookup) == nil)
        // A cycle ends.
        #expect(ProcessTree.nearest(from: 70, lookup: lookup) == nil)
    }

    @Test func agentsRecordTheirName() {
        #expect(ProcessTree.Agent.claude.by == "claude-code")
        #expect(ProcessTree.Agent.codex.by == "codex")
    }

    /// The real walk from the test process: Claude Code's Bash tool sets CLAUDECODE=1 for what
    /// it runs, so `swift test` from Claude Code finds the live `claude`. From a terminal or
    /// Xcode it finds nothing, and from Codex it finds `codex`, which sets no marker of its own.
    @Test func walkFromThisProcess() {
        let host = ProcessTree.host()
        if ProcessInfo.processInfo.environment["CLAUDECODE"] == "1" {
            #expect(host?.agent == .claude, "host() = \(String(describing: host))")
        }
        if let host {
            #expect(ProcessTree.isAlive(host.pid, startedBy: .now))
            #expect(host.pid != getpid())
        }
    }
}
