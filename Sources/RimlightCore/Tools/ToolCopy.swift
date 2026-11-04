import Foundation

/// One `rimlight` on disk, as a shell finds it on PATH, and who installed it. The app and
/// `rimlight doctor` use these to tell which copy runs and which one an update may touch.
public struct ToolCopy: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Under Homebrew's Cellar. Only `brew` may replace or remove it.
        case homebrew
        /// The layout `rimlight self-install` makes: `<prefix>/bin/rimlight` pointing into
        /// `<prefix>/share/rimlight/<version>/`. The app installs this one, and may replace or
        /// remove it.
        case standalone
        /// Anything else, such as a binary copied by hand or a build folder.
        case other
    }

    /// The path as found on PATH, before symlinks are resolved.
    public var path: String
    /// The same file with every symlink resolved.
    public var resolved: String
    public var kind: Kind

    public init(path: String, resolved: String) {
        self.path = path
        self.resolved = resolved
        kind = Self.kind(ofResolved: resolved)
    }

    /// The kind a resolved path belongs to, from the path alone.
    public static func kind(ofResolved path: String) -> Kind {
        let parts = path.split(separator: "/")
        if let i = parts.firstIndex(of: "Cellar"), i + 1 < parts.count, parts[i + 1] == "rimlight" {
            return .homebrew
        }
        // .../share/rimlight/<version>/rimlight
        if parts.count >= 4, parts[parts.count - 1] == "rimlight", RimlightVersion(String(parts[parts.count - 2])) != nil,
            parts[parts.count - 3] == "rimlight", parts[parts.count - 4] == "share"
        {
            return .standalone
        }
        return .other
    }

    /// The version this copy reports, from running `<resolved> version` with a short timeout.
    /// Nil when it does not run or its answer does not parse. One process launch, about 20 ms.
    public func probeVersion(environment: [String: String] = ProcessInfo.processInfo.environment) -> RimlightVersion? {
        guard let output = try? Subprocess.run(
            URL(filePath: resolved, directoryHint: .notDirectory), ["version"], environment: environment, timeout: 10),
            output.status == 0
        else { return nil }
        // "rimlight 0.2.0"
        let text = String(decoding: output.stdout, as: UTF8.self)
        return text.split(whereSeparator: \.isWhitespace).last.flatMap { RimlightVersion(String($0)) }
    }

    /// Every executable `rimlight` in `searchPath`'s absolute entries, in PATH order, the first
    /// being the one a shell runs. A file reached twice, through a folder listed twice or two
    /// links to one file, is listed once, where PATH first reaches it.
    public static func all(searchPath: String?) -> [ToolCopy] {
        CurrentProcess.lookupAll(SkillText.commandName, searchPath: searchPath).map {
            ToolCopy(path: $0.path, resolved: $0.resolved)
        }
    }
}

extension CurrentProcess {
    /// Every executable regular file called `name` in `searchPath`'s absolute entries, in order,
    /// with its resolved path; the first is what `lookup` returns. Duplicates by resolved path
    /// are dropped. One `stat` and one `access` per entry.
    public static func lookupAll(_ name: String, searchPath: String?) -> [(path: String, resolved: String)] {
        guard let searchPath, !name.isEmpty, !name.contains("/") else { return [] }
        var found: [(path: String, resolved: String)] = []
        var seen: Set<String> = []
        for dir in searchPath.split(separator: ":") where dir.hasPrefix("/") {
            let candidate = (String(dir) as NSString).appendingPathComponent(name)
            var st = stat()
            guard stat(candidate, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, access(candidate, X_OK) == 0,
                let resolved = realPath(candidate), seen.insert(resolved).inserted
            else { continue }
            found.append((candidate, resolved))
        }
        return found
    }
}
