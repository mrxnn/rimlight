import CryptoKit
import Foundation

/// Where one run's icons build. The root layout, `--root DIR`, is for research and tests: `DIR/<id>/` with the pick
/// at `src/render.png`. The store layout is `.rimlight/sets/<set>/<slug>/builds/<direction>/`, whose pick is the
/// icon's own `icon.png`, and whose package carries the icon's title.
public struct BuildLayout: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable { case root, store }

    public let kind: Kind
    /// The root folder, or the project's `sets/`.
    public let root: URL
    /// The package's name, `out/<package>.icon`.
    public let package: String
    /// The direction the store layout builds, `main` unless `--direction` names another. The root layout has one.
    public let direction: String

    public init(kind: Kind, root: URL, package: String, direction: String = BuildDirection.main) {
        self.kind = kind
        self.root = root
        self.package = package
        self.direction = direction
    }

    public static func root(_ dir: URL) -> BuildLayout { BuildLayout(kind: .root, root: dir, package: "build") }

    /// An icon's folder: `<root>/<id>/`, or `<sets>/<set>/<slug>/builds/<direction>/`.
    public func folder(_ id: String) -> URL { folder(id, direction: direction) }

    /// The folder of another direction of the same icon; the root layout has only the one.
    public func folder(_ id: String, direction: String) -> URL {
        let base = root.appending(path: id, directoryHint: .isDirectory)
        guard kind == .store else { return base }
        return base.appending(path: BuildDirection.folderName, directoryHint: .isDirectory)
            .appending(path: direction, directoryHint: .isDirectory)
    }

    /// The directions an icon has folders for, `main` first; none in the root layout.
    public func directions(_ id: String) -> [String] {
        guard kind == .store else { return [] }
        let builds = root.appending(path: id, directoryHint: .isDirectory)
            .appending(path: BuildDirection.folderName, directoryHint: .isDirectory)
        return BuildDirection.names(in: builds)
    }

    public func file(_ id: String, _ path: String) -> URL {
        folder(id).appending(path: path, directoryHint: .notDirectory)
    }

    /// The pick the build starts from.
    public func pick(_ id: String) -> URL {
        kind == .store
            ? root.appending(path: "\(id)/\(ProjectStore.imageName)", directoryHint: .notDirectory)
            : file(id, "src/render.png")
    }

    public func packageURL(_ id: String) -> URL {
        folder(id).appending(path: "out/\(package).icon", directoryHint: .isDirectory)
    }
}

extension BuildLayout {
    /// The store layout of a project: ids are `<set>/<slug>`, each icon's package is named by `title`.
    public static func store(_ store: ProjectStore, direction: String = BuildDirection.main) -> BuildLayout {
        BuildLayout(kind: .store, root: store.setsDir, package: "build", direction: direction)
    }

    /// The same layout with the package named `title` and the direction, made safe as a file name.
    public func named(_ title: String) -> BuildLayout {
        BuildLayout(kind: kind, root: root, package: Self.packageName(title, direction: direction), direction: direction)
    }

    /// A title as a package's file name: `/` and `:` become `-`, leading dots and spaces go, and an empty one is
    /// `build`.
    public static func packageName(_ title: String) -> String {
        var name = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }
        name = name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "build" : name
    }

    /// One direction's package name: the title's for `main`, `<Title>, <direction>` for any other, so two
    /// directions' packages opened side by side tell themselves apart.
    public static func packageName(_ title: String, direction: String) -> String {
        let name = packageName(title)
        return direction == BuildDirection.main ? name : packageName("\(name), \(direction)")
    }
}

/// One direction of an icon's build, `builds/<name>/`. Some picks have more than one good build, such as a black
/// mark whose Dark could keep it black, turn it white or lighten the ground; each builds in its own folder.
public struct BuildDirection: Sendable, Hashable {
    /// The direction a build without `--direction` makes.
    public static let main = "main"
    /// The folder of an icon's directions, beside `icon.png`.
    public static let folderName = "builds"
    /// Where 0.4.2 and earlier built, the one direction there was; a build moves it to `builds/main/`.
    public static let legacyFolderName = "build"

    public let name: String
    public let folder: URL

    public init(name: String, folder: URL) {
        self.name = name
        self.folder = folder
    }

    /// 1 to 32 of `a-z`, `0-9` and `-`, as a layer's name.
    public static func isValid(_ name: String) -> Bool { PlanFile.validName(name) }

    /// `main` first, then by name.
    public static func ordered(_ names: [String]) -> [String] {
        names.sorted { a, b in a == main ? b != main : b == main ? false : a < b }
    }

    /// The valid direction names among `builds`' folders, `main` first.
    static func names(in builds: URL) -> [String] {
        let all = (try? FileManager.default.contentsOfDirectory(atPath: builds.path)) ?? []
        return ordered(all.filter { isValid($0) && ProjectStore.isDirectory(builds.appending(path: $0).path) })
    }
}

/// Icon Composer's command-line renderer. It ships inside Icon Composer in Xcode 26 and later.
public enum ICTool {
    static let bundlePath = "Applications/Icon Composer.app/Contents/Executables/ictool"

    /// The ictool of the Xcode `xcode-select -p` names, else of `/Applications/Xcode.app`; nil when neither has one.
    public static func locate(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        var candidates: [URL] = []
        if let out = try? Subprocess.run(URL(filePath: "/usr/bin/xcode-select"), ["-p"], environment: environment, timeout: 10),
            out.status == 0
        {
            let developer = String(decoding: out.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if !developer.isEmpty {
                candidates.append(URL(filePath: developer, directoryHint: .isDirectory).deletingLastPathComponent()
                    .appending(path: bundlePath, directoryHint: .notDirectory))
            }
        }
        candidates.append(URL(filePath: "/Applications/Xcode.app/Contents", directoryHint: .isDirectory)
            .appending(path: bundlePath, directoryHint: .notDirectory))
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

/// `builds/<direction>/build.json`, written by each run in the store that includes the `pack` stage, so the app can
/// tell a package that is stale: the pick it was made from, by which rimlight and pipeline, and the stages of that
/// run. Since 0.6.0 it also names what that run made, so a reader finds the package, the image to show and the
/// layers without listing `out/`. Those keys are nil in an older record.
public struct BuildRecord: Codable, Equatable, Sendable {
    /// SHA-256 of the pick, `icon.png`, when the run started.
    public var pick: String
    public var rimlight: String
    /// The pipeline that made the package: `layers` and its prompts' version. The key keeps its old name, `engine`,
    /// so a build.json from 0.3.0 still reads.
    public var engine: String
    /// The stages that ran, in order, and the one that failed, if any.
    public var stages: [String]
    public var failed: String?
    public var built: Date
    /// The rest is nil in a record from 0.5.2 or earlier. `schema` is `BuildRun.currentSchema` when written.
    public var schema: Int?
    /// The agent process the run ran under (`ProcessTree.host`); nil from a terminal.
    public var host: Int32?
    /// The plan's round: the plans kept in `rounds/` plus the current one.
    public var round: Int?
    /// Paths relative to the direction's folder: the package, `out/<Title>.icon`; the image to show, `out/hero.png`;
    /// the six renders by rendition, empty without ictool.
    public var package: String?
    public var hero: String?
    public var renders: [String: String]?
    /// The ground, and the layers above it top first, as files in the package's `Assets/`.
    public var ground: BuildLayer?
    public var layers: [BuildLayer]?

    public init(
        pick: String, rimlight: String, engine: String, stages: [String], failed: String?, built: Date,
        made: Made? = nil
    ) {
        self.pick = pick
        self.rimlight = rimlight
        self.engine = engine
        self.stages = stages
        self.failed = failed
        self.built = StateCoding.wholeSeconds(built)
        if let made {
            schema = BuildRun.currentSchema
            host = made.host
            round = made.round
            package = made.package
            hero = made.hero
            renders = made.renders
            ground = made.ground
            layers = made.layers
        }
    }

    /// What a run made, for the keys 0.6.0 added.
    public struct Made: Sendable, Equatable {
        public var host: Int32?
        public var round: Int
        public var package: String
        public var hero: String?
        public var renders: [String: String]
        public var ground: BuildLayer?
        public var layers: [BuildLayer]

        public init(
            host: Int32?, round: Int, package: String, hero: String?, renders: [String: String], ground: BuildLayer?,
            layers: [BuildLayer]
        ) {
            self.host = host
            self.round = round
            self.package = package
            self.hero = hero
            self.renders = renders
            self.ground = ground
            self.layers = layers
        }
    }

    private enum CodingKeys: String, CodingKey {
        case pick, rimlight, engine, stages, failed, built, schema, host, round, package, hero, renders, ground, layers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pick = try c.decode(String.self, forKey: .pick)
        rimlight = try c.decode(String.self, forKey: .rimlight)
        engine = try c.decode(String.self, forKey: .engine)
        stages = try c.decode([String].self, forKey: .stages)
        failed = try c.decodeIfPresent(String.self, forKey: .failed)
        built = try c.decode(Date.self, forKey: .built)
        schema = try c.decodeIfPresent(Int.self, forKey: .schema)
        host = try c.decodeIfPresent(Int32.self, forKey: .host)
        round = try c.decodeIfPresent(Int.self, forKey: .round)
        package = try c.decodeIfPresent(String.self, forKey: .package)
        hero = try c.decodeIfPresent(String.self, forKey: .hero)
        renders = try c.decodeIfPresent([String: String].self, forKey: .renders)
        ground = try c.decodeIfPresent(BuildLayer.self, forKey: .ground)
        layers = try c.decodeIfPresent([BuildLayer].self, forKey: .layers)
    }

    /// Every key is written, `failed` as null when the run finished. A record without `schema` keeps 0.5.2's keys
    /// only, so a round trip leaves an old record as it was.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pick, forKey: .pick)
        try c.encode(rimlight, forKey: .rimlight)
        try c.encode(engine, forKey: .engine)
        try c.encode(stages, forKey: .stages)
        try c.encode(failed, forKey: .failed)
        try c.encode(built, forKey: .built)
        guard let schema else { return }
        try c.encode(schema, forKey: .schema)
        try c.encode(host, forKey: .host)
        try c.encode(round, forKey: .round)
        try c.encode(package, forKey: .package)
        try c.encode(hero, forKey: .hero)
        try c.encode(renders, forKey: .renders)
        try c.encode(ground, forKey: .ground)
        try c.encode(layers, forKey: .layers)
    }

    /// Takes `last`'s account of the package when this run made none, so a round that failed before pack still
    /// names the package that is there.
    public mutating func keepMade(from last: BuildRecord) {
        guard last.schema != nil else { return }
        schema = last.schema
        host = last.host
        round = last.round
        package = last.package
        hero = last.hero
        renders = last.renders
        ground = last.ground
        layers = last.layers
    }

    public static func sha256(of url: URL) throws -> String { try sha256Hex(of: url) }
}

extension ProjectStore {
    /// `<set>/<slug>/builds/`, the folder of the icon's build directions, beside its record.
    public func buildsFolder(set: String, slug: String) -> URL {
        iconFolder(set: set, slug: slug).appending(path: BuildDirection.folderName, directoryHint: .isDirectory)
    }

    /// `<set>/<slug>/builds/<direction>/`, where `rimlight build` writes that direction. A path only: it may not
    /// exist yet.
    public func buildFolder(set: String, slug: String, direction: String = BuildDirection.main) -> URL {
        buildsFolder(set: set, slug: slug).appending(path: direction, directoryHint: .isDirectory)
    }

    /// The icon's directions that have a folder, `main` first, then by name. An unmoved `build/` from 0.4.2 or
    /// earlier stands for `main` until a build moves it. One listing and a stat.
    public func buildDirections(set: String, slug: String) -> [BuildDirection] {
        var names = BuildDirection.names(in: buildsFolder(set: set, slug: slug))
        if !names.contains(BuildDirection.main), Self.isDirectory(legacyBuildFolder(set: set, slug: slug).path) {
            names.insert(BuildDirection.main, at: 0)
        }
        return names.map { BuildDirection(name: $0, folder: existingBuildFolder(set: set, slug: slug, direction: $0)) }
    }

    /// The icon has a finished build: a direction with the record a packing run writes. A listing and a stat per
    /// direction, no read, so a grid's filter can ask it of every icon.
    public func hasBuild(set: String, slug: String) -> Bool {
        buildDirections(set: set, slug: slug).contains {
            Self.fileExists($0.folder.appending(path: "build.json", directoryHint: .notDirectory).path)
        }
    }

    /// `<set>/<slug>/build/`, the one build folder of 0.4.2 and earlier.
    public func legacyBuildFolder(set: String, slug: String) -> URL {
        iconFolder(set: set, slug: slug).appending(path: BuildDirection.legacyFolderName, directoryHint: .isDirectory)
    }

    /// What `moveLegacyBuild` did.
    public enum LegacyBuildMove: Sendable, Equatable {
        /// There was no `build/`.
        case none
        /// `build/` is now `builds/main/`.
        case moved
        /// `build/` stays where it is, since `builds/main/` exists already.
        case kept
    }

    /// Moves 0.4.2's `build/` to `builds/main/` under the project's lock, unless `builds/main/` exists. A stat when
    /// there is nothing to move.
    @discardableResult
    public func moveLegacyBuild(set: String, slug: String) throws -> LegacyBuildMove {
        let legacy = legacyBuildFolder(set: set, slug: slug)
        guard Self.isDirectory(legacy.path) else { return .none }
        return try exclusive {
            guard Self.isDirectory(legacy.path) else { return .none }
            let main = buildFolder(set: set, slug: slug)
            if Self.fileExists(main.path) { return .kept }
            try FileManager.default.createDirectory(at: buildsFolder(set: set, slug: slug), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: legacy, to: main)
            return .moved
        }
    }

    /// Removes one direction of the icon's build: its plan and rounds, what the image model drew, the package, the renders and
    /// the review, everything in its folder. Another direction keeps its own copies of any drawings they shared.
    /// Refused while a build of the direction runs, which holds its `.lock`. Under the project's lock the folder is
    /// first renamed to `<slug> <direction> build`, a name no reader takes, so a reader sees the build or nothing;
    /// `discard` then takes it, to the Trash by default. When `discard` fails the folder goes back. An emptied
    /// `builds/` goes too. `main` from an unmoved 0.4.2 `build/` is removed the same way.
    public func removeBuild(
        set: String, slug: String, direction: String, discard: (URL) throws -> Void = ProjectStore.moveToTrash
    ) throws {
        try validateSetID(set)
        try Slug.validate(slug)
        guard BuildDirection.isValid(direction) else { throw StoreError.invalidID("Invalid direction \(direction)") }
        try exclusive {
            let folder = existingBuildFolder(set: set, slug: slug, direction: direction)
            guard Self.isDirectory(folder.path) else {
                throw StoreError.notFound("No \(direction) build of \(set)/\(slug)")
            }
            // a running build holds `.lock` for its whole run; holding it here keeps one from starting meanwhile
            let fd = open(folder.appending(path: ".lock", directoryHint: .notDirectory).path, O_RDWR | O_CLOEXEC)
            defer { if fd >= 0 { close(fd) } }
            if fd >= 0, flock(fd, LOCK_EX | LOCK_NB) != 0 {
                throw StoreError.invalidArgument("The \(direction) build of \(set)/\(slug) is running")
            }
            let parent = folder.deletingLastPathComponent()
            var name = "\(slug) \(direction) build"
            if Self.fileExists(parent.appending(path: name).path) { name += " \(UUID().uuidString.prefix(8))" }
            let aside = parent.appending(path: name, directoryHint: .isDirectory)
            guard rename(folder.path, aside.path) == 0 else {
                throw StoreError.io("Cannot move \(folder.path) aside (errno \(errno))")
            }
            do {
                try discard(aside)
            } catch {
                _ = rename(aside.path, folder.path)
                throw error
            }
            _ = rmdir(buildsFolder(set: set, slug: slug).path)
        }
    }

    /// `removeBuild`'s default: the Trash, so a removed build can still be put back from Finder.
    public static func moveToTrash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    /// Writes the direction's `build.json` under the project's lock, atomically.
    public func writeBuildRecord(
        _ record: BuildRecord, set: String, slug: String, direction: String = BuildDirection.main
    ) throws {
        let url = buildFolder(set: set, slug: slug, direction: direction)
            .appending(path: "build.json", directoryHint: .notDirectory)
        try exclusive {
            try requireIcon(set: set, slug: slug)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try AtomicFile.write(try StateCoding.encode(record), to: url)
        }
    }

    /// The direction's `build.json`; `main`'s is read from an unmoved `build/` too.
    public func readBuildRecord(set: String, slug: String, direction: String = BuildDirection.main) -> BuildRecord? {
        let url = existingBuildFolder(set: set, slug: slug, direction: direction)
            .appending(path: "build.json", directoryHint: .notDirectory)
        guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
        return try? StateCoding.decoder().decode(BuildRecord.self, from: data)
    }

    /// The direction's folder, or for `main` an unmoved `build/` when `builds/main/` is not there.
    func existingBuildFolder(set: String, slug: String, direction: String) -> URL {
        let folder = buildFolder(set: set, slug: slug, direction: direction)
        guard direction == BuildDirection.main, !Self.fileExists(folder.path) else { return folder }
        let legacy = legacyBuildFolder(set: set, slug: slug)
        return Self.isDirectory(legacy.path) ? legacy : folder
    }
}

/// `--prune`: what a later run from `fit` makes again for free: the fitted layers, the renders and the zoom
/// crops. The plan, its rounds, what the image model drew in `gen/`, the package and the review sheet stay.
public enum BuildPrune {
    /// The paths it removes from `folder`, relative, in order; with `dryRun`, only lists them.
    @discardableResult
    public static func prune(_ folder: URL, dryRun: Bool = false) throws -> (removed: [String], bytes: Int64) {
        let fm = FileManager.default
        var paths: [String] = []
        for dir in ["layers", "out/renders"] where fm.fileExists(atPath: folder.appending(path: dir).path) {
            paths.append(dir)
        }
        let out = folder.appending(path: "out", directoryHint: .isDirectory)
        for name in ((try? fm.contentsOfDirectory(atPath: out.path)) ?? []).sorted()
        where name.hasPrefix("zoom-") && name.hasSuffix(".png") {
            paths.append("out/\(name)")
        }
        var bytes: Int64 = 0
        for path in paths { bytes += size(folder.appending(path: path)) }
        if !dryRun { for path in paths { try fm.removeItem(at: folder.appending(path: path)) } }
        return (paths, bytes)
    }

    static func size(_ url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
        if let v = try? url.resourceValues(forKeys: keys), v.isRegularFile == true { return Int64(v.fileSize ?? 0) }
        var total: Int64 = 0
        for case let f as URL in FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) ?? .init() {
            if let v = try? f.resourceValues(forKeys: keys), v.isRegularFile == true { total += Int64(v.fileSize ?? 0) }
        }
        return total
    }
}

/// SHA-256 of a file as lowercase hex, read in 1 MB chunks.
func sha256Hex(of url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hash = SHA256()
    while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hash.update(data: chunk) }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}
