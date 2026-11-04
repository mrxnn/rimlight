import Darwin
import Foundation

/// `builds/<direction>/run.json`, what a build of that direction is doing now, so the app can show a build while it
/// runs. The CLI writes it when a run that draws, fits or packs starts, as each stage starts, and when the run
/// ends; preview, sheet and the aids alone leave it as it was. One writer at a time, the run holding `.lock`, so
/// no project lock.
public struct BuildRun: Codable, Equatable, Sendable {
    /// The `schema` of `run.json` and of `build.json` from 0.6.0 on. A reader skips a build that carries a higher
    /// one; it does not refuse the project.
    public static let currentSchema = 1

    public enum State: String, Codable, Sendable {
        case running, done, failed
    }

    public var state: State
    /// The stage running; nil once the run ended.
    public var stage: String?
    /// The stages that finished, in order, and the one that failed.
    public var stages: [String]
    public var failed: String?
    /// The `rimlight` process. A `running` record whose process is gone was killed: read it as stopped.
    public var pid: Int32
    /// The agent process it runs under, Claude Code or Codex; nil from a terminal.
    public var host: Int32?
    public var round: Int
    public var started: Date
    public var updated: Date

    public init(
        state: State = .running, stage: String?, stages: [String] = [], failed: String? = nil, pid: Int32 = getpid(),
        host: Int32?, round: Int, started: Date, updated: Date = .now
    ) {
        self.state = state
        self.stage = stage
        self.stages = stages
        self.failed = failed
        self.pid = pid
        self.host = host
        self.round = round
        self.started = StateCoding.wholeSeconds(started)
        self.updated = StateCoding.wholeSeconds(updated)
    }

    /// Running, and its process still is.
    public var isLive: Bool { state == .running && ProcessTree.isAlive(pid, startedBy: started) }

    private enum CodingKeys: String, CodingKey {
        case schema, state, stage, stages, failed, pid, host, round, started, updated
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try c.decodeIfPresent(Int.self, forKey: .schema) ?? Self.currentSchema
        guard schema <= Self.currentSchema else { throw StoreError.newerSchema(schema) }
        state = try c.decode(State.self, forKey: .state)
        stage = try c.decodeIfPresent(String.self, forKey: .stage)
        stages = try c.decode([String].self, forKey: .stages)
        failed = try c.decodeIfPresent(String.self, forKey: .failed)
        pid = try c.decode(Int32.self, forKey: .pid)
        host = try c.decodeIfPresent(Int32.self, forKey: .host)
        round = try c.decode(Int.self, forKey: .round)
        started = try c.decode(Date.self, forKey: .started)
        updated = try c.decode(Date.self, forKey: .updated)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentSchema, forKey: .schema)
        try c.encode(state, forKey: .state)
        try c.encode(stage, forKey: .stage)
        try c.encode(stages, forKey: .stages)
        try c.encode(failed, forKey: .failed)
        try c.encode(pid, forKey: .pid)
        try c.encode(host, forKey: .host)
        try c.encode(round, forKey: .round)
        try c.encode(started, forKey: .started)
        try c.encode(updated, forKey: .updated)
    }

    /// The round a folder's plan is on: the plans kept in `rounds/`, plus `plan.json`. 0 before the first plan.
    public static func round(in folder: URL) -> Int {
        let rounds = (try? FileManager.default.contentsOfDirectory(atPath: folder.appending(path: "rounds").path)) ?? []
        let kept = rounds.count { $0.hasPrefix("plan-") && $0.hasSuffix(".json") }
        return kept + (ProjectStore.fileExists(folder.appending(path: "plan.json").path) ? 1 : 0)
    }
}

/// One layer of a built package as its files: the image, and the Dark and Tinted ones when it has them. Paths are
/// relative to the direction's folder.
public struct BuildLayer: Codable, Equatable, Sendable {
    public var name: String
    public var image: String
    public var dark: String?
    public var tinted: String?
    /// `light` or `dark` for a layer hidden in the other appearance, so a viewer leaves it out there; nil for a
    /// layer in every appearance, and in records from before it.
    public var only: String?

    public init(name: String, image: String, dark: String? = nil, tinted: String? = nil, only: String? = nil) {
        self.name = name
        self.image = image
        self.dark = dark
        self.tinted = tinted
        self.only = only
    }

    private enum CodingKeys: String, CodingKey { case name, image, dark, tinted, only }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(image, forKey: .image)
        try c.encode(dark, forKey: .dark)
        try c.encode(tinted, forKey: .tinted)
        try c.encodeIfPresent(only, forKey: .only)
    }
}

extension IconPackage {
    /// The ground and the layers above it, top first, as `package`'s `icon.json` names them, with paths relative to
    /// `base`. Reads a package written by any version, so a build from before 0.6.0 lists its layers too. nil when
    /// the package or its `icon.json` is missing or unreadable.
    public static func layers(of package: URL, relativeTo base: URL) -> (ground: BuildLayer?, layers: [BuildLayer])? {
        guard let data = FileManager.default.contents(atPath: package.appending(path: "icon.json").path),
            let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let groups = document["groups"] as? [[String: Any]]
        else { return nil }
        let assets = relative(package, to: base) + "/Assets/"
        var ground: BuildLayer?
        var layers: [BuildLayer] = []
        for group in groups {
            for entry in group["layers"] as? [[String: Any]] ?? [] {
                guard let name = entry["name"] as? String else { continue }
                var image = entry["image-name"] as? String
                var dark: String?
                var tinted: String?
                for special in entry["image-name-specializations"] as? [[String: String]] ?? [] {
                    switch special["appearance"] {
                    case nil: image = special["value"]
                    case "dark": dark = special["value"]
                    case "tinted": tinted = special["value"]
                    default: break
                    }
                }
                guard let image else { continue }
                var hidden: [String: Bool] = [:]
                for special in entry["hidden-specializations"] as? [[String: Any]] ?? [] {
                    if let value = special["value"] as? Bool { hidden[special["appearance"] as? String ?? "light"] = value }
                }
                let only: String? =
                    switch (hidden["light"] ?? false, hidden["dark"] ?? false) {
                    case (true, false): "dark"
                    case (false, true): "light"
                    default: nil
                    }
                let layer = BuildLayer(
                    name: name, image: assets + image, dark: dark.map { assets + $0 }, tinted: tinted.map { assets + $0 },
                    only: only)
                if group["name"] as? String == "ground" { ground = layer } else { layers.append(layer) }
            }
        }
        return (ground, layers)
    }

    public static func relative(_ url: URL, to base: URL) -> String {
        let path = url.standardizedFileURL.path
        let prefix = base.standardizedFileURL.path + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }
}

/// One direction of an icon's build as a viewer shows it: what is running, and the last package and its files.
public struct BuildEntry: Sendable, Equatable, Identifiable {
    /// A file of the build, where it is and its stamp, the image cache's key.
    public struct File: Sendable, Equatable {
        public var url: URL
        public var stamp: FileStamp

        public init(url: URL, stamp: FileStamp) {
            self.url = url
            self.stamp = stamp
        }
    }

    /// A layer with its files resolved; a file that is missing is nil.
    public struct Layer: Sendable, Equatable {
        public var name: String
        public var image: File?
        public var dark: File?
        public var tinted: File?
        /// `light` or `dark` for a layer only that appearance shows; nil for one every appearance shows.
        public var only: String?

        public init(name: String, image: File?, dark: File? = nil, tinted: File? = nil, only: String? = nil) {
            self.name = name
            self.image = image
            self.dark = dark
            self.tinted = tinted
            self.only = only
        }
    }

    public var direction: String
    public var folder: URL
    /// The run in progress, nil when none is: its record says `running` and its process lives.
    public var running: BuildRun?
    /// The record of the run that made the package, nil before the first.
    public var record: BuildRecord?
    /// What the last package looks like, `out/hero.png`, or `out/renders/Default.png` for a build before 0.6.0.
    public var hero: File?
    public var package: URL?
    public var ground: Layer?
    /// Top first.
    public var layers: [Layer]

    public var id: String { direction }

    public init(
        direction: String, folder: URL, running: BuildRun?, record: BuildRecord?, hero: File?, package: URL?,
        ground: Layer?, layers: [Layer]
    ) {
        self.direction = direction
        self.folder = folder
        self.running = running
        self.record = record
        self.hero = hero
        self.package = package
        self.ground = ground
        self.layers = layers
    }
}

extension ProjectStore {
    /// Fails when the icon's record is gone: a build must not bring back a folder the app deleted.
    func requireIcon(set: String, slug: String) throws {
        guard Self.fileExists(iconRecordURL(set: set, slug: slug).path) else {
            throw StoreError.notFound("the icon \(set)/\(slug) was deleted")
        }
    }

    /// Writes the direction's `run.json` atomically, into a folder the build made already. Fails when the icon was
    /// deleted.
    public func writeBuildRun(_ run: BuildRun, set: String, slug: String, direction: String = BuildDirection.main) throws {
        try requireIcon(set: set, slug: slug)
        let folder = buildFolder(set: set, slug: slug, direction: direction)
        try AtomicFile.write(try StateCoding.encode(run), to: folder.appending(path: "run.json", directoryHint: .notDirectory))
    }

    public func readBuildRun(set: String, slug: String, direction: String = BuildDirection.main) -> BuildRun? {
        let url = existingBuildFolder(set: set, slug: slug, direction: direction)
            .appending(path: "run.json", directoryHint: .notDirectory)
        guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
        return try? StateCoding.decoder().decode(BuildRun.self, from: data)
    }

    /// The icon's builds a viewer shows, `main` first: each direction with a package to show or a run in progress.
    /// A direction with neither, such as a `main` that only previewed, is left out. One listing, then per
    /// direction two small reads, a few stats, and for a build before 0.6.0 its package's `icon.json`.
    public func readBuilds(set: String, slug: String) -> [BuildEntry] {
        buildDirections(set: set, slug: slug).compactMap { direction in
            readBuild(direction, set: set, slug: slug)
        }
    }

    /// One direction as `readBuilds` reads it; nil when it has nothing to show.
    public func readBuild(_ direction: BuildDirection, set: String, slug: String) -> BuildEntry? {
        let folder = direction.folder
        let run = readBuildRun(set: set, slug: slug, direction: direction.name)
        let running = run.flatMap { $0.isLive ? $0 : nil }
        let record = readBuildRecord(set: set, slug: slug, direction: direction.name)
        func file(_ path: String?) -> BuildEntry.File? {
            guard let path else { return nil }
            let url = folder.appending(path: path, directoryHint: .notDirectory)
            return FileStamp.of(url).map { BuildEntry.File(url: url, stamp: $0) }
        }
        var hero: BuildEntry.File?
        var package: URL?
        if let record, record.schema != nil {
            guard record.schema! <= BuildRun.currentSchema else { return nil }
            hero = file(record.hero)
            package = record.package.map { folder.appending(path: $0, directoryHint: .isDirectory) }
        } else {
            // before 0.6.0: Default's render, never the assembly, which is an unmasked square
            hero = file("out/renders/Default.png")
            let out = folder.appending(path: "out", directoryHint: .isDirectory)
            let name = ((try? FileManager.default.contentsOfDirectory(atPath: out.path)) ?? []).sorted()
                .first { $0.hasSuffix(".icon") && !$0.hasPrefix(".") }
            package = name.map { out.appending(path: $0, directoryHint: .isDirectory) }
        }
        if let found = package, !Self.isDirectory(found.path) { package = nil }
        guard hero != nil || running != nil else { return nil }
        var ground = record?.ground
        var layers = record?.layers
        if layers == nil, let package, let read = IconPackage.layers(of: package, relativeTo: folder) {
            (ground, layers) = (read.ground, read.layers)
        }
        func resolve(_ layer: BuildLayer) -> BuildEntry.Layer {
            BuildEntry.Layer(
                name: layer.name, image: file(layer.image), dark: file(layer.dark), tinted: file(layer.tinted), only: layer.only)
        }
        return BuildEntry(
            direction: direction.name, folder: folder, running: running, record: record, hero: hero, package: package,
            ground: ground.map(resolve), layers: (layers ?? []).map(resolve))
    }
}

/// Puts a whole folder in place in one step, so a reader sees the old folder or the new one and never half of one.
public enum AtomicFolder {
    /// Moves `staged` to `dest`. When `dest` exists the two swap in one rename and the old one is removed; on a
    /// volume that cannot swap (SMB, exFAT) the old one moves aside first, which leaves a moment with neither.
    public static func replace(_ dest: URL, with staged: URL) throws {
        let fm = FileManager.default
        if !ProjectStore.fileExists(dest.path) {
            guard rename(staged.path, dest.path) == 0 else { throw failure("move", staged, dest, errno) }
            return
        }
        if renamex_np(staged.path, dest.path, UInt32(RENAME_SWAP)) == 0 {
            try? fm.removeItem(at: staged)
            return
        }
        let err = errno
        guard err == ENOTSUP || err == EINVAL || err == ENOTTY else { throw failure("swap", staged, dest, err) }
        try swapByMoving(dest, with: staged)
    }

    /// The fallback: the old folder aside under a hidden name, the new one in, the old one removed.
    static func swapByMoving(_ dest: URL, with staged: URL) throws {
        let aside = dest.deletingLastPathComponent()
            .appending(path: ".\(dest.lastPathComponent).\(UUID().uuidString).old", directoryHint: .isDirectory)
        guard rename(dest.path, aside.path) == 0 else { throw failure("move aside", dest, aside, errno) }
        guard rename(staged.path, dest.path) == 0 else {
            let err = errno
            _ = rename(aside.path, dest.path)
            throw failure("move", staged, dest, err)
        }
        try? FileManager.default.removeItem(at: aside)
    }

    private static func failure(_ what: String, _ from: URL, _ to: URL, _ err: Int32) -> StoreError {
        .io("Cannot \(what) \(from.path) to \(to.path) (errno \(err))")
    }
}
