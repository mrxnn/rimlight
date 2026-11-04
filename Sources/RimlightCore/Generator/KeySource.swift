import Foundation

/// Where a render's API key comes from. The app keeps keys in its own Keychain item, which
/// nothing else can read, and hands one to this CLI over a Unix socket after checking the
/// caller's code signature. So the key is never in an environment variable, an argument or
/// a file the chat agent could read. With the app closed, a terminal can set the provider's
/// `RIMLIGHT_<PROVIDER>_API_KEY` instead.
public enum KeySource {
    /// One line of JSON each way, then the app closes the connection.
    public struct Request: Codable, Sendable {
        public var provider: String
        public init(provider: String) { self.provider = provider }
    }

    public struct Response: Codable, Sendable {
        /// The key, when the app has one for the provider and trusts the caller.
        public var key: String?
        /// Why not, otherwise.
        public var error: String?
        public init(key: String? = nil, error: String? = nil) {
            self.key = key
            self.error = error
        }
    }

    /// `$RIMLIGHT_KEY_SOCKET`, else `~/Library/Application Support/Rimlight/keys.sock`.
    public static func socketURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let custom = environment["RIMLIGHT_KEY_SOCKET"], !custom.isEmpty {
            return URL(filePath: (custom as NSString).expandingTildeInPath, directoryHint: .notDirectory)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Rimlight/keys.sock", directoryHint: .notDirectory)
    }

    public enum Origin: String, Sendable {
        case app
        case environment
    }

    /// The key for `provider`: the app's, else the provider's variable. nil when neither has one.
    public static func key(
        for provider: ImageProvider, environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> (key: String, origin: Origin)? {
        if case .found(let key, let origin) = lookup(provider, environment: environment) { return (key, origin) }
        return nil
    }

    public enum Lookup: Equatable, Sendable {
        case found(String, Origin)
        /// Why there's no key, in words for the person.
        case missing(String)
    }

    /// The key for `provider`, or why there is none. The app may be behind a dialog, such as
    /// the Keychain asking for the login password, so this waits up to `patience` seconds for
    /// its answer, calling `onWait` once when it is slow.
    public static func lookup(
        _ provider: ImageProvider, environment: [String: String] = ProcessInfo.processInfo.environment,
        patience: TimeInterval = 180, slowAfter: TimeInterval = 5, onWait: () -> Void = {}
    ) -> Lookup {
        let answer = askApp(
            provider: provider, environment: environment, patience: patience, slowAfter: slowAfter, onWait: onWait)
        if case .key(let key)? = answer { return .found(key, .app) }
        if let name = provider.keyVariable, let key = environment[name].nonEmpty { return .found(key, .environment) }
        let terminal = provider.keyVariable.map { ", or set \($0) in a terminal" } ?? ""
        switch answer {
        case .refused(let why)?:
            return .missing("\(why). Add one in Rimlight's settings\(terminal).")
        case .noAnswer?:
            return .missing(
                "Rimlight didn't hand over the \(provider.displayName) key within \(Int(patience / 60)) minutes. If it "
                    + "shows a dialog, answer it, then try again\(terminal).")
        case .key?, nil:
            return .missing(
                "No \(provider.displayName) key reaches rimlight. Add one in Rimlight's settings, with the app open\(terminal).")
        }
    }

    public enum AppAnswer: Equatable, Sendable {
        case key(String)
        case refused(String)
        /// The app took the request and didn't answer in time.
        case noAnswer
    }

    /// The running app's answer, or nil when no app is listening.
    public static func askApp(
        provider: ImageProvider, environment: [String: String] = ProcessInfo.processInfo.environment,
        patience: TimeInterval = 180, slowAfter: TimeInterval = 5, onWait: () -> Void = {}
    ) -> AppAnswer? {
        let path = socketURL(environment: environment).path
        guard FileManager.default.fileExists(atPath: path),
            let line = try? JSONEncoder().encode(Request(provider: provider.rawValue))
        else { return nil }
        switch exchange(path: path, line: line + Data("\n".utf8), patience: patience, slowAfter: slowAfter, onWait: onWait) {
        case .noApp: return nil
        case .timedOut: return .noAnswer
        case .reply(let reply):
            guard let response = try? JSONDecoder().decode(Response.self, from: reply) else { return nil }
            if let key = response.key, !key.isEmpty { return .key(key) }
            return .refused(response.error ?? "the app has no key for \(provider.displayName)")
        }
    }

    enum Exchange: Equatable {
        case noApp
        case reply(Data)
        case timedOut
    }

    /// Writes `line` to the socket at `path` and reads until the app closes it, for up to
    /// `patience` seconds; `onWait` hears once, after `slowAfter`, that the app is slow.
    static func exchange(
        path: String, line: Data, patience: TimeInterval, slowAfter: TimeInterval, onWait: () -> Void
    ) -> Exchange {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return .noApp }
        defer { close(fd) }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        let step = min(slowAfter, patience)
        var wait = timeval(tv_sec: Int(step), tv_usec: Int32((step - step.rounded(.down)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return .noApp }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return .noApp }
        let sent = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard sent == line.count else { return .noApp }
        let deadline = Date().addingTimeInterval(patience)
        var told = false
        var reply = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while reply.count < 65536 {
            let n = read(fd, &buffer, buffer.count)
            if n > 0 {
                reply.append(contentsOf: buffer[..<n])
                continue
            }
            // A read that timed out: the app is busy, often behind a dialog. Keep waiting.
            if n < 0, errno == EAGAIN || errno == EWOULDBLOCK, reply.isEmpty {
                guard Date() < deadline else { return .timedOut }
                if !told {
                    told = true
                    onWait()
                }
                continue
            }
            break
        }
        return reply.isEmpty ? .timedOut : .reply(reply)
    }
}
