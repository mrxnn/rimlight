import Foundation

/// `.rimlight/.jobs/<id>.json`: one image a `rimlight generate`, `rimlight fix` or `rimlight build` is rendering.
/// The CLI keeps it from before the render until the image lands or the process ends, so the
/// app can show the render and keep alive the agent process it runs under.
public struct JobMarker: Codable, Hashable, Sendable, Identifiable {
    public enum Mode: String, Codable, Hashable, Sendable {
        case generate
        case fix
        /// An image `rimlight build` makes for the layered build: a subject or key cut-out. An app older than
        /// this case cannot decode the marker and skips it.
        case build
    }

    /// Also the file's name, without `.json`.
    public var id: String
    /// The `rimlight` process doing the render.
    public var pid: Int32
    /// The nearest agent above `pid` (`ProcessTree.host`), Claude Code or Codex, whose exit would
    /// kill the render. nil outside both.
    public var hostPID: Int32?
    public var set: String
    public var slug: String
    /// The title the icon will have.
    public var title: String
    public var mode: Mode
    public var started: Date

    public init(
        id: String = UUID().uuidString.lowercased(), pid: Int32 = getpid(), hostPID: Int32?, set: String,
        slug: String, title: String, mode: Mode, started: Date = .now
    ) {
        self.id = id
        self.pid = pid
        self.hostPID = hostPID
        self.set = set
        self.slug = slug
        self.title = title
        self.mode = mode
        self.started = StateCoding.wholeSeconds(started)
    }

    /// `<set>/<slug>`: the icon the render makes or replaces.
    public var iconID: String { "\(set)/\(slug)" }

    private enum CodingKeys: String, CodingKey { case id, pid, hostPID, set, slug, title, mode, started }

    /// Every key is written, `hostPID` as null when absent.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(pid, forKey: .pid)
        try c.encode(hostPID, forKey: .hostPID)
        try c.encode(set, forKey: .set)
        try c.encode(slug, forKey: .slug)
        try c.encode(title, forKey: .title)
        try c.encode(mode, forKey: .mode)
        try c.encode(started, forKey: .started)
    }
}

/// A marker read back, and whether its process still runs. A process killed with SIGKILL
/// leaves its marker behind, so `alive` is the truth, not the file.
@dynamicMemberLookup
public struct RenderJob: Hashable, Sendable, Identifiable {
    public var marker: JobMarker
    /// `kill(pid, 0)` finds the process (any errno but ESRCH) and it is not a later process
    /// that reused the pid.
    public var alive: Bool

    public init(marker: JobMarker, alive: Bool) {
        self.marker = marker
        self.alive = alive
    }

    public var id: String { marker.id }

    public subscript<T>(dynamicMember path: KeyPath<JobMarker, T>) -> T { marker[keyPath: path] }
}

extension ProjectStore {
    public static let jobsFolderName = ".jobs"

    /// `<project>/.rimlight/.jobs`, made on the first marker.
    public var jobsDir: URL { stateRoot.appending(path: Self.jobsFolderName, directoryHint: .isDirectory) }

    public func jobURL(_ id: String) -> URL { jobsDir.appending(path: "\(id).json", directoryHint: .notDirectory) }

    /// Writes the marker as a temp file and a rename. No lock: each marker has one writer.
    public func writeJob(_ marker: JobMarker) throws {
        guard !marker.id.isEmpty, !marker.id.hasPrefix("."), !marker.id.contains("/") else {
            throw StoreError.invalidID("\"\(marker.id)\" is not a job id")
        }
        do { try FileManager.default.createDirectory(at: jobsDir, withIntermediateDirectories: true) } catch {
            throw StoreError.io("Cannot create \(jobsDir.path): \(error.localizedDescription)")
        }
        try AtomicFile.write(try StateCoding.encode(marker), to: jobURL(marker.id))
    }

    /// Removes the marker. One already gone is no error.
    public func removeJob(_ id: String) {
        guard !id.isEmpty, !id.contains("/") else { return }
        unlink(jobURL(id).path)
    }

    /// Every marker, oldest first, with whether its process still runs. A missing `.jobs/`
    /// reads as none and a marker that does not decode is skipped. Costs one listing, and per
    /// marker one small read, one `kill` and one `sysctl`.
    public func readJobs() -> [RenderJob] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: jobsDir.path) else { return [] }
        let decoder = StateCoding.decoder()
        var jobs: [RenderJob] = []
        for name in names where name.hasSuffix(".json") && !name.hasPrefix(".") {
            let url = jobsDir.appending(path: name, directoryHint: .notDirectory)
            guard let data = try? Data(contentsOf: url), var marker = try? decoder.decode(JobMarker.self, from: data)
            else { continue }
            // The file's name is the id removeJob uses.
            marker.id = String(name.dropLast(5))
            jobs.append(RenderJob(marker: marker, alive: ProcessTree.isAlive(marker.pid, startedBy: marker.started)))
        }
        jobs.sort {
            $0.started != $1.started
                ? $0.started < $1.started : $0.iconID.compare($1.iconID, options: .numeric) == .orderedAscending
        }
        return jobs
    }

    /// Removes the markers whose process is gone, and returns them.
    @discardableResult
    public func pruneDeadJobs() -> [JobMarker] {
        let dead = readJobs().filter { !$0.alive }.map(\.marker)
        for marker in dead { removeJob(marker.id) }
        return dead
    }

    /// Whether the icon the marker names was stored after its render started: its record was
    /// written since. False for a render that died before storing anything.
    public func jobLanded(_ marker: JobMarker) -> Bool {
        guard let stamp = FileStamp.of(iconRecordURL(set: marker.set, slug: marker.slug)) else { return false }
        return stamp.mtimeNS >= UInt64(max(0, marker.started.timeIntervalSince1970)) * 1_000_000_000
    }
}
