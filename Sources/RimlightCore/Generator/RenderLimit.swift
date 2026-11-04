import Foundation

/// A refusal that holds for every render until something changes: Codex's image limit on
/// the person's ChatGPT plan, which Codex reports with `429 Too Many Requests` and
/// `usage_limit_reached`, or an image API account out of credit. A render that meets one
/// stops at once instead of spending its fix attempts, and the limit is kept in a small file
/// the app reads for its banner.
public struct RenderLimit: Codable, Hashable, Sendable {
    /// The `ImageProvider` raw value that refused. Records from before providers say Codex.
    public var provider: String
    /// When the limit lifts; nil when the provider did not say.
    public var resetsAt: Date?
    /// Codex's `plan_type`, such as `plus`.
    public var plan: String?
    /// The provider's own words, for a refusal that isn't Codex's plan limit.
    public var note: String?
    public var recorded: Date

    public init(
        provider: String = ImageProvider.codex.rawValue, resetsAt: Date?, plan: String?, note: String? = nil,
        recorded: Date
    ) {
        self.provider = provider
        self.resetsAt = resetsAt
        self.plan = plan
        self.note = note
        self.recorded = recorded
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? ImageProvider.codex.rawValue
        resetsAt = try c.decodeIfPresent(Date.self, forKey: .resetsAt)
        plan = try c.decodeIfPresent(String.self, forKey: .plan)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        recorded = try c.decode(Date.self, forKey: .recorded)
    }

    /// Codex's limit in its error text, or nil when the text is not one. Codex prints the
    /// response body inside a debug string, so the quotes may come escaped.
    public static func parseCodex(_ text: String, now: Date = Date()) -> RenderLimit? {
        guard text.contains("usage_limit_reached") else { return nil }
        func field(_ name: String, _ value: String) -> String? {
            guard let regex = try? Regex(name + #"\\?"\s*:\s*\\?"?"# + value) else { return nil }
            return text.firstMatch(of: regex).flatMap { $0.output.count > 1 ? $0.output[1].substring.map(String.init) : nil }
        }
        var resetsAt = field("resets_at", #"(\d+)"#).flatMap(TimeInterval.init).map { Date(timeIntervalSince1970: $0) }
        if resetsAt == nil, let seconds = field("resets_in_seconds", #"(\d+)"#).flatMap(TimeInterval.init) {
            resetsAt = now.addingTimeInterval(seconds)
        }
        return RenderLimit(resetsAt: resetsAt, plan: field("plan_type", #"([A-Za-z_]+)"#), recorded: now)
    }

    /// What the CLI prints after `LIMIT` and the app shows: which limit, and when it lifts.
    public func message(now: Date = Date(), timeZone: TimeZone = .current) -> String {
        let resets = resetsAt.flatMap { Self.when($0, now: now, timeZone: timeZone) }
        guard provider == ImageProvider.codex.rawValue else {
            let name = ImageProvider(rawValue: provider)?.displayName ?? provider
            var text = "\(name) refused the render"
            if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                text += ": " + note + (note.last.map { ".!?".contains($0) } == true ? "" : ".")
            } else {
                text += "."
            }
            guard let resets else { return text + " Renders fail until the account is sorted out." }
            return text + " It resets at \(resets). Renders fail until then."
        }
        let plan = plan.map { "ChatGPT \($0.prefix(1).uppercased() + $0.dropFirst()) plan" } ?? "ChatGPT plan"
        let text = "Codex's image limit on your \(plan) is reached."
        guard let resets else { return text + " Renders fail until it resets." }
        return text + " It resets at \(resets). Renders fail until then."
    }

    /// "21:04, in 7 h 8 min", with the weekday when it isn't today; nil once it has passed.
    static func when(_ date: Date, now: Date, timeZone: TimeZone) -> String? {
        guard date > now else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone))
        let day =
            calendar.isDate(date, inSameDayAs: now)
            ? "" : " on " + date.formatted(Date.FormatStyle(timeZone: timeZone).weekday(.wide))
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded(.up))
        let left = minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
        return "\(time)\(day), in \(left)"
    }

    // MARK: The shared record

    /// `$RIMLIGHT_STATE_DIR`, else `$XDG_STATE_HOME/rimlight`, else `~/.local/state/rimlight`.
    public static func stateDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let custom = environment["RIMLIGHT_STATE_DIR"], !custom.isEmpty {
            return URL(filePath: (custom as NSString).expandingTildeInPath, directoryHint: .isDirectory)
        }
        if let xdg = environment["XDG_STATE_HOME"], !xdg.isEmpty {
            return URL(filePath: (xdg as NSString).expandingTildeInPath, directoryHint: .isDirectory)
                .appending(path: "rimlight", directoryHint: .isDirectory)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".local/state/rimlight", directoryHint: .isDirectory)
    }

    /// `limit.json` in the state directory.
    public static func stateURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        stateDirectory(environment: environment).appending(path: "limit.json", directoryHint: .notDirectory)
    }

    /// Where 0.7 kept Codex's limit. Still read, so a limit recorded before the update holds.
    static func legacyURL(environment: [String: String]) -> URL {
        stateDirectory(environment: environment).appending(path: "codex-limit.json", directoryHint: .notDirectory)
    }

    /// Keeps `limit` for the app. A failure to write is ignored: the CLI still reports it.
    public static func record(_ limit: RenderLimit, environment: [String: String] = ProcessInfo.processInfo.environment) {
        let url = stateURL(environment: environment)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? StateCoding.encoder().encode(limit) else { return }
        try? AtomicFile.write(data, to: url)
    }

    /// Forgets the limit, after a render went through. One `stat` each when there is none.
    public static func clear(environment: [String: String] = ProcessInfo.processInfo.environment) {
        for url in [stateURL(environment: environment), legacyURL(environment: environment)]
        where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// The recorded limit while it holds: nil when there is none, or its reset time has passed.
    /// A record without a reset time holds for a day.
    public static func current(
        environment: [String: String] = ProcessInfo.processInfo.environment, now: Date = Date()
    ) -> RenderLimit? {
        let data =
            (try? Data(contentsOf: stateURL(environment: environment)))
            ?? (try? Data(contentsOf: legacyURL(environment: environment)))
        guard let data, let limit = try? StateCoding.decoder().decode(RenderLimit.self, from: data) else { return nil }
        let until = limit.resetsAt ?? limit.recorded.addingTimeInterval(24 * 3600)
        return until > now ? limit : nil
    }
}
