import Darwin
import Foundation

/// What render jobs need to know about other processes, from `sysctl` and `libproc`.
public enum ProcessTree {
    /// An agent a `rimlight` can run under.
    public enum Agent: String, Sendable {
        case claude
        case codex

        /// What a render records as `by` when it names no one.
        public var by: String {
            switch self {
            case .claude: "claude-code"
            case .codex: "codex"
            }
        }
    }

    /// The nearest process above this one that is an agent: its pid and which agent it is, or
    /// nil (a `rimlight` run from a plain terminal). Claude Code and Codex end their shells, and
    /// every render under them, when they exit. A few `sysctl` calls; the CLI makes them once.
    public static func host() -> (pid: Int32, agent: Agent)? {
        nearest(from: getpid()) { pid in
            guard let info = info(pid) else { return nil }
            return (info.parent, agent(pid, comm: info.comm), info.comm == "node" || info.comm == "bun")
        }
    }

    /// Walks up from `pid`'s parent to the first process `lookup` names an agent. `lookup`
    /// gives a process's parent, which agent it is and whether it is node or bun running the
    /// agent's script, nil for one that is gone. An agent started by its own script, as npm's
    /// `codex` starts the native binary, is reported as the script: that is the process the app
    /// launched and compares a job's host with.
    static func nearest(
        from pid: Int32, lookup: (Int32) -> (parent: Int32, agent: Agent?, script: Bool)?
    ) -> (pid: Int32, agent: Agent)? {
        guard var current = lookup(pid)?.parent else { return nil }
        // launchd (1) and the kernel (0) end the walk; the bound guards against a cycle.
        for _ in 0..<64 {
            guard current > 1, let entry = lookup(current) else { return nil }
            if let agent = entry.agent {
                if entry.parent > 1, let above = lookup(entry.parent), above.agent == agent, above.script {
                    return (entry.parent, agent)
                }
                return (current, agent)
            }
            current = entry.parent
        }
        return nil
    }

    /// `pid` runs and is not a later process that reused it: one that started more than a
    /// second or two after `started` is not the process that wrote the marker. A zombie is gone.
    public static func isAlive(_ pid: Int32, startedBy started: Date) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) != 0, errno == ESRCH { return false }
        // Another user's process answers EPERM and still reads here.
        guard let info = info(pid) else { return true }
        return !info.zombie && info.started <= started.addingTimeInterval(2)
    }

    struct Info {
        var parent: Int32
        /// The kernel's name for it: the executable's file name, at most 16 bytes.
        var comm: String
        var started: Date
        var zombie: Bool
    }

    static func info(_ pid: Int32) -> Info? {
        var kp = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &kp, &size, nil, 0) == 0, size > 0 else { return nil }
        let comm = withUnsafeBytes(of: kp.kp_proc.p_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let tv = kp.kp_proc.p_un.__p_starttime
        return Info(
            parent: kp.kp_eproc.e_ppid, comm: comm,
            started: Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1e6),
            zombie: kp.kp_proc.p_stat == SZOMB)
    }

    static func agent(_ pid: Int32, comm: String) -> Agent? {
        if isClaude(pid, comm: comm) { return .claude }
        if isCodex(pid, comm: comm) { return .codex }
        return nil
    }

    /// Claude Code by its name, by its native install's path (`…/claude/versions/<version>`,
    /// a file named for the version), or as node or bun running its `claude` script.
    static func isClaude(_ pid: Int32, comm: String) -> Bool {
        if comm == "claude" { return true }
        if comm == "node" || comm == "bun" {
            guard let script = arguments(pid, count: 2).dropFirst().first else { return false }
            return (script as NSString).lastPathComponent == "claude" || script.contains("/@anthropic-ai/claude-code/")
        }
        guard let path = executablePath(pid) else { return false }
        return (path as NSString).lastPathComponent == "claude" || path.contains("/claude/versions/")
    }

    /// Codex by its name: the native binary npm, Homebrew and ChatGPT.app all run is `codex`.
    /// npm's `codex` on PATH is node running its `codex` script, which starts that binary.
    /// The `codex exec` a render starts sits below `rimlight`, so the walk up never meets it.
    static func isCodex(_ pid: Int32, comm: String) -> Bool {
        if comm == "codex" { return true }
        if comm == "node" || comm == "bun" {
            guard let script = arguments(pid, count: 2).dropFirst().first else { return false }
            return (script as NSString).lastPathComponent == "codex" || script.contains("/@openai/codex/")
        }
        return false
    }

    static func executablePath(_ pid: Int32) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let n = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard n > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(n)), as: UTF8.self)
    }

    /// The first `count` arguments `pid` was started with, from `KERN_PROCARGS2`: argc, the
    /// exec path and its padding, then argv.
    static func arguments(_ pid: Int32, count: Int) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        let argc = Int(buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
        var i = MemoryLayout<Int32>.size
        while i < size, buffer[i] != 0 { i += 1 }
        while i < size, buffer[i] == 0 { i += 1 }
        var args: [String] = []
        while args.count < min(argc, count), i < size {
            let start = i
            while i < size, buffer[i] != 0 { i += 1 }
            args.append(String(decoding: buffer[start..<i], as: UTF8.self))
            i += 1
        }
        return args
    }
}
