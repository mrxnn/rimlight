import Foundation

/// Runs a program to completion with stdout and stderr captured in files, so a chatty child
/// can never fill a pipe and stall, and kills it at the timeout.
enum Subprocess {
    struct Output {
        /// The exit status, or minus the signal number when a signal ended the process.
        var status: Int32
        var stdout: Data
        var stderr: Data
        var timedOut: Bool
    }

    /// With `every`, `tick` runs on this thread each time that many seconds pass while the child runs: setup's
    /// progress lines.
    static func run(
        _ executable: URL,
        _ arguments: [String],
        environment: [String: String],
        timeout: TimeInterval,
        every: TimeInterval? = nil,
        tick: () -> Void = {}
    ) throws -> Output {
        let scratch = try makeTempDirectory(prefix: "rimlight-run-")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let outURL = scratch.appending(path: "stdout", directoryHint: .notDirectory)
        let errURL = scratch.appending(path: "stderr", directoryHint: .notDirectory)
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        let out = try FileHandle(forWritingTo: outURL)
        let err = try FileHandle(forWritingTo: errURL)

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        // stdin must be /dev/null or codex waits for EOF on an inherited terminal or pipe.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = out
        process.standardError = err
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch {
            try? out.close()
            try? err.close()
            throw error
        }

        var timedOut = false
        let deadline = DispatchTime.now() + timeout
        var finished = false
        if let every {
            while DispatchTime.now() < deadline {
                if exited.wait(timeout: min(.now() + every, deadline)) == .success {
                    finished = true
                    break
                }
                tick()
            }
        }
        if !finished, exited.wait(timeout: deadline) == .timedOut {
            timedOut = true
            process.terminate()
            if exited.wait(timeout: .now() + 3) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                exited.wait()
            }
        }
        try? out.close()
        try? err.close()
        let status = process.terminationReason == .uncaughtSignal ? -process.terminationStatus : process.terminationStatus
        return Output(
            status: status,
            stdout: (try? Data(contentsOf: outURL)) ?? Data(),
            stderr: (try? Data(contentsOf: errURL)) ?? Data(),
            timedOut: timedOut)
    }

    /// Runs a program to completion with its stdout and stderr handed over as they come, in the order each pipe
    /// delivers them, for a child whose lines must show while it works. stdin is /dev/null. Returns the exit
    /// status, or minus the signal number.
    static func stream(
        _ executable: URL,
        _ arguments: [String],
        environment: [String: String],
        stdout: @escaping @Sendable (Data) -> Void,
        stderr: @escaping @Sendable (Data) -> Void
    ) throws -> Int32 {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        let done = DispatchGroup()
        for (pipe, sink) in [(outPipe, stdout), (errPipe, stderr)] {
            done.enter()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    done.leave()
                } else {
                    sink(data)
                }
            }
        }
        done.enter()
        process.terminationHandler = { _ in done.leave() }
        do { try process.run() } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }
        // Process closes the parent's write ends after the launch, so each pipe ends with the child
        done.wait()
        return process.terminationReason == .uncaughtSignal ? -process.terminationStatus : process.terminationStatus
    }

    static func makeTempDirectory(prefix: String, in parent: URL = FileManager.default.temporaryDirectory) throws -> URL {
        var template = Array(parent.appending(path: "\(prefix)XXXXXX").path.utf8CString)
        guard let made = template.withUnsafeMutableBufferPointer({ mkdtemp($0.baseAddress) }) else {
            throw StoreError.io("Cannot create a temp folder in \(parent.path) (errno \(errno))")
        }
        return URL(filePath: String(cString: made), directoryHint: .isDirectory)
    }
}

/// Finds programs the way a shell would, falling back to the user's login shell PATH: an
/// app launched from Finder gets a bare PATH that misses Homebrew, nvm and npm globals.
enum ExecutableSearch {
    static func find(_ name: String, in path: String) -> String? {
        for dir in path.split(separator: ":") where !dir.isEmpty {
            let candidate = "\(dir)/\(name)"
            var st = stat()
            if access(candidate, X_OK) == 0, stat(candidate, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG {
                return candidate
            }
        }
        return nil
    }

    /// `$PATH` as the user's interactive login shell sets it, or nil when the shell fails or
    /// takes over five seconds. Markers fence the value off from anything rc files print.
    static func loginShellPATH(environment: [String: String]) -> String? {
        let shell = environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        let marker = "__RIMLIGHT_PATH__"
        guard let output = try? Subprocess.run(
            URL(filePath: shell), ["-l", "-i", "-c", "printf '\(marker)%s\(marker)' \"$PATH\""],
            environment: environment, timeout: 5),
            !output.timedOut
        else { return nil }
        let text = String(decoding: output.stdout, as: UTF8.self)
        let parts = text.components(separatedBy: marker)
        guard parts.count >= 3, !parts[1].isEmpty else { return nil }
        return parts[1]
    }
}
