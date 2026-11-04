import Foundation
import Testing

@testable import RimlightCore

/// What the app reads of a build: `run.json` while it runs, `build.json` once it packed, and the builds of an icon
/// a viewer shows. Also the whole-folder swap pack puts its outputs in place with.
@Suite struct BuildStateTests {
    static let set = "set-001"
    static let slug = "dial"

    static func project(_ dir: URL) throws -> ProjectStore {
        let store = ProjectStore(projectRoot: dir)
        try store.create()
        let png = dir.appending(path: "render.png")
        try TinyPNG.make(.rgba).write(to: png)
        try store.addIcon(
            set: set, slug: slug, title: "Dial", prompt: "a dial", by: "claude-code", image: png,
            imageInfo: ImageInfo(width: 3, height: 2, alpha: true))
        return store
    }

    static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// A packed direction as 0.6.0 leaves it: the package, the hero and a record that names them.
    static func packed(_ store: ProjectStore, direction: String, host: Int32? = 7) throws -> URL {
        let folder = store.buildFolder(set: set, slug: slug, direction: direction)
        let package = folder.appending(path: "out/Dial.icon", directoryHint: .isDirectory)
        let png = TinyPNG.make(.rgba)
        let sources = folder.appending(path: "layers", directoryHint: .isDirectory)
        var assets: [String: URL] = [:]
        for name in ["ground.png", "ground-dark.png", "needle.png", "needle-mono.png", "face.png"] {
            try write(png, to: sources.appending(path: name))
            assets[name] = sources.appending(path: name)
        }
        try IconPackage.write(
            to: package, layers: [IconPackage.Layer(name: "face"), IconPackage.Layer(name: "needle", hero: true)],
            assets: assets)
        try write(png, to: folder.appending(path: "out/hero.png"))
        let layers = try #require(IconPackage.layers(of: package, relativeTo: folder))
        let record = BuildRecord(
            pick: "abc", rimlight: "0.6.0", engine: "layers 1", stages: ["draw", "fit", "pack", "sheet"], failed: nil,
            built: Date(timeIntervalSince1970: 1_800_000_000),
            made: BuildRecord.Made(
                host: host, round: 2, package: "out/Dial.icon", hero: "out/hero.png", renders: [:], ground: layers.ground,
                layers: layers.layers))
        try store.writeBuildRecord(record, set: set, slug: slug, direction: direction)
        return folder
    }

    @Test func anOldRecordStillReadsAndWritesBackAsItWas() throws {
        let old = """
            {"built":"2026-10-23T15:13:09Z","engine":"layers 1","failed":null,"pick":"abc","rimlight":"0.5.2","stages":["pack"]}
            """
        let record = try StateCoding.decoder().decode(BuildRecord.self, from: Data(old.utf8))
        #expect(record.schema == nil && record.hero == nil && record.layers == nil)
        let written = try JSONSerialization.jsonObject(with: StateCoding.encode(record)) as? [String: Any]
        #expect(Set(written?.keys.map { $0 } ?? []) == ["built", "engine", "failed", "pick", "rimlight", "stages"])
    }

    @Test func aNewRecordNamesWhatItMadeAndKeepsItThroughAFailedRound() throws {
        try withTempDir { dir in
            let store = try Self.project(dir)
            _ = try Self.packed(store, direction: "flipped")
            let last = try #require(store.readBuildRecord(set: Self.set, slug: Self.slug, direction: "flipped"))
            #expect(last.schema == BuildRun.currentSchema)
            #expect(last.package == "out/Dial.icon" && last.hero == "out/hero.png" && last.round == 2 && last.host == 7)
            // top first, the ground apart, the hero's Tinted image beside it
            #expect(last.layers?.map(\.name) == ["needle", "face"])
            #expect(last.layers?.first?.tinted == "out/Dial.icon/Assets/needle-mono.png")
            #expect(last.ground?.dark == "out/Dial.icon/Assets/ground-dark.png")

            var failed = BuildRecord(
                pick: "abc", rimlight: "0.6.0", engine: "layers 1", stages: ["fit"], failed: "pack", built: .now)
            failed.keepMade(from: last)
            #expect(failed.failed == "pack" && failed.package == last.package && failed.layers == last.layers)
        }
    }

    @Test func aRunReadsBackAndADeadOneIsNotLive() throws {
        let run = BuildRun(stage: "draw", stages: ["preview"], host: nil, round: 3, started: .now)
        let back = try StateCoding.decoder().decode(BuildRun.self, from: StateCoding.encode(run))
        #expect(back == run)
        #expect(back.isLive)
        let text = String(decoding: try StateCoding.encode(run), as: UTF8.self)
        #expect(text.contains("\"schema\" : 1") && text.contains("\"host\" : null"))
        // a pid no process has, and a finished run, are not running
        #expect(!BuildRun(stage: "fit", pid: 999_999, host: nil, round: 1, started: .now).isLive)
        #expect(!BuildRun(state: .done, stage: nil, host: nil, round: 1, started: .now).isLive)
        // a newer format is skipped, not misread
        let newer = text.replacingOccurrences(of: "\"schema\" : 1", with: "\"schema\" : 9")
        #expect(throws: StoreError.newerSchema(9)) { try StateCoding.decoder().decode(BuildRun.self, from: Data(newer.utf8)) }
    }

    @Test func theRoundCountsThePlans() throws {
        try withTempDir { dir in
            #expect(BuildRun.round(in: dir) == 0)
            try Self.write(Data("{}".utf8), to: dir.appending(path: "plan.json"))
            #expect(BuildRun.round(in: dir) == 1)
            try Self.write(Data("{}".utf8), to: dir.appending(path: "rounds/plan-1.json"))
            try Self.write(Data("{}".utf8), to: dir.appending(path: "rounds/plan-2.json"))
            try Self.write(Data("x".utf8), to: dir.appending(path: "rounds/notes.txt"))
            #expect(BuildRun.round(in: dir) == 3)
        }
    }

    @Test func aViewerSeesBuildsWithAnImageOrALiveRun() throws {
        try withTempDir { dir in
            let store = try Self.project(dir)
            // main only previewed: nothing to show
            try Self.write(TinyPNG.make(.rgba), to: store.buildFolder(set: Self.set, slug: Self.slug).appending(path: "src/tile.png"))
            #expect(store.readBuilds(set: Self.set, slug: Self.slug).isEmpty)

            let folder = try Self.packed(store, direction: "flipped")
            // a run killed before it made anything stays hidden; a live one shows with no image yet
            let fresh = store.buildFolder(set: Self.set, slug: Self.slug, direction: "keep-black")
            try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
            try store.writeBuildRun(
                BuildRun(stage: "draw", pid: 999_999, host: 7, round: 1, started: .now),
                set: Self.set, slug: Self.slug, direction: "keep-black")
            #expect(store.readBuilds(set: Self.set, slug: Self.slug).map(\.direction) == ["flipped"])
            try store.writeBuildRun(
                BuildRun(stage: "draw", host: 7, round: 1, started: .now), set: Self.set, slug: Self.slug, direction: "keep-black")
            let builds = store.readBuilds(set: Self.set, slug: Self.slug)
            #expect(builds.map(\.direction) == ["flipped", "keep-black"])
            #expect(builds[1].running?.stage == "draw" && builds[1].hero == nil)

            let flipped = builds[0]
            #expect(flipped.running == nil)
            #expect(flipped.hero?.url == folder.appending(path: "out/hero.png"))
            #expect(flipped.package?.lastPathComponent == "Dial.icon")
            #expect(flipped.layers.map(\.name) == ["needle", "face"])
            #expect(flipped.layers[0].tinted != nil && flipped.layers[1].tinted == nil)
            #expect(flipped.ground?.dark != nil)
        }
    }

    @Test func aBuildFromBeforeTheRecordShowsDefaultAndReadsItsLayersFromThePackage() throws {
        try withTempDir { dir in
            let store = try Self.project(dir)
            let folder = try Self.packed(store, direction: "main")
            // as 0.5.2 left it: the old record, no hero.png, the renders
            try FileManager.default.removeItem(at: folder.appending(path: "out/hero.png"))
            let old = BuildRecord(pick: "abc", rimlight: "0.5.2", engine: "layers 1", stages: ["pack"], failed: nil, built: .now)
            try store.writeBuildRecord(old, set: Self.set, slug: Self.slug)
            #expect(store.readBuilds(set: Self.set, slug: Self.slug).isEmpty)
            try Self.write(TinyPNG.make(.rgba), to: folder.appending(path: "out/renders/Default.png"))
            let build = try #require(store.readBuilds(set: Self.set, slug: Self.slug).first)
            #expect(build.hero?.url.lastPathComponent == "Default.png")
            #expect(build.package?.lastPathComponent == "Dial.icon")
            #expect(build.layers.map(\.name) == ["needle", "face"])
        }
    }

    @Test func aBuildCannotBringBackADeletedIcon() throws {
        try withTempDir { dir in
            let store = try Self.project(dir)
            try FileManager.default.removeItem(at: store.iconRecordURL(set: Self.set, slug: Self.slug))
            let run = BuildRun(stage: "fit", host: nil, round: 1, started: .now)
            #expect(throws: StoreError.self) { try store.writeBuildRun(run, set: Self.set, slug: Self.slug) }
            let record = BuildRecord(pick: "", rimlight: "0.6.0", engine: "layers 1", stages: [], failed: nil, built: .now)
            #expect(throws: StoreError.self) { try store.writeBuildRecord(record, set: Self.set, slug: Self.slug) }
            #expect(!FileManager.default.fileExists(atPath: store.buildsFolder(set: Self.set, slug: Self.slug).path))
        }
    }

    /// Discards for real in a temp folder, where the Trash would keep test litter.
    static func remove(_ url: URL) throws { try FileManager.default.removeItem(at: url) }

    @Test func removingABuildTakesItsWholeFolderAndLeavesTheOthers() throws {
        try withTempDir { dir in
            let store = try Self.project(dir)
            let main = try Self.packed(store, direction: BuildDirection.main)
            _ = try Self.packed(store, direction: "flipped")
            try Self.write(TinyPNG.make(.rgba), to: main.appending(path: "gen/ground.png"))
            var discarded: [String] = []
            try store.removeBuild(set: Self.set, slug: Self.slug, direction: BuildDirection.main) { url in
                discarded.append(url.lastPathComponent)
                try Self.remove(url)
            }
            // a name no reader takes, so a reader never sees the build half gone
            #expect(discarded == ["\(Self.slug) main build"])
            #expect(!FileManager.default.fileExists(atPath: main.path))
            #expect(store.readBuilds(set: Self.set, slug: Self.slug).map(\.direction) == ["flipped"])

            try store.removeBuild(set: Self.set, slug: Self.slug, direction: "flipped", discard: Self.remove)
            #expect(store.readBuilds(set: Self.set, slug: Self.slug).isEmpty)
            #expect(!FileManager.default.fileExists(atPath: store.buildsFolder(set: Self.set, slug: Self.slug).path))
            #expect(throws: StoreError.self) {
                try store.removeBuild(set: Self.set, slug: Self.slug, direction: "flipped", discard: Self.remove)
            }
        }
    }

    @Test func aDuplicateCopiesTheRenderAndEveryBuildWithAFreshChat() throws {
        try withTempDir { dir in
            let store = try Self.project(dir)
            _ = try Self.packed(store, direction: BuildDirection.main)
            _ = try Self.packed(store, direction: "flipped")
            try store.setIconChat(set: Self.set, slug: Self.slug, harness: "claude", session: "s1")
            try store.setFavorite(set: Self.set, slug: Self.slug, true)
            let original = try store.readIcon(set: Self.set, slug: Self.slug)
            let now = Date(timeIntervalSince1970: 1_900_000_000)

            let copy = try store.duplicateIcon(set: Self.set, slug: Self.slug, now: now)
            #expect(copy.icon.slug == "dial-copy")
            #expect(copy.icon.title == original.icon.title + " copy")
            #expect(copy.icon.created == now)
            #expect(copy.icon.chat.isEmpty && copy.icon.chatHistory.isEmpty)
            #expect(copy.icon.prompt == original.icon.prompt && copy.icon.parent == original.icon.parent)
            #expect(copy.icon.favorite)
            #expect(try Data(contentsOf: copy.imageURL) == Data(contentsOf: original.imageURL))
            // the builds read as the original's, from the copy's own folder
            let builds = store.readBuilds(set: Self.set, slug: "dial-copy")
            #expect(builds.map(\.direction) == [BuildDirection.main, "flipped"])
            #expect(builds.allSatisfy { $0.hero != nil && $0.folder.path.contains("/dial-copy/") })
            // the original is as it was, and no staging folder is left
            #expect(try store.readIcon(set: Self.set, slug: Self.slug) == original)
            let names = try FileManager.default.contentsOfDirectory(atPath: store.setDir(Self.set).path)
            #expect(!names.contains { $0.hasPrefix(".") })

            // a copy of a copy is the next copy, not a copy of "copy"
            let second = try store.duplicateIcon(set: Self.set, slug: "dial-copy", now: now)
            #expect(second.icon.slug == "dial-copy-2")
            #expect(second.icon.title == original.icon.title + " copy 2")
            let results = try store.duplicateIcons([(Self.set, Self.slug), (Self.set, "missing")], now: now)
            #expect((try? results[0].get())?.icon.slug == "dial-copy-3")
            #expect((try? results[1].get()) == nil)
        }
    }

    @Test func aRunningBuildIsNotDuplicated() throws {
        try withTempDir { dir in
            let store = try Self.project(dir)
            let folder = try Self.packed(store, direction: "flipped")
            let fd = open(folder.appending(path: ".lock").path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
            defer { close(fd) }
            #expect(flock(fd, LOCK_EX | LOCK_NB) == 0)
            #expect(throws: StoreError.self) { try store.duplicateIcon(set: Self.set, slug: Self.slug) }
            #expect(!FileManager.default.fileExists(atPath: store.iconFolder(set: Self.set, slug: "dial-copy").path))
            flock(fd, LOCK_UN)
            #expect(try store.duplicateIcon(set: Self.set, slug: Self.slug).icon.slug == "dial-copy")
        }
    }

    @Test func aRunningBuildIsNotRemovedAndAFailedDiscardPutsItBack() throws {
        try withTempDir { dir in
            let store = try Self.project(dir)
            let folder = try Self.packed(store, direction: "flipped")
            let lock = folder.appending(path: ".lock")
            let fd = open(lock.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
            defer { close(fd) }
            #expect(flock(fd, LOCK_EX | LOCK_NB) == 0)
            #expect(throws: StoreError.self) {
                try store.removeBuild(set: Self.set, slug: Self.slug, direction: "flipped", discard: Self.remove)
            }
            #expect(FileManager.default.fileExists(atPath: folder.path))
            flock(fd, LOCK_UN)

            struct Refused: Error {}
            #expect(throws: Refused.self) {
                try store.removeBuild(set: Self.set, slug: Self.slug, direction: "flipped") { _ in throw Refused() }
            }
            #expect(store.readBuilds(set: Self.set, slug: Self.slug).map(\.direction) == ["flipped"])
        }
    }

    @Test func anUnmovedOldBuildIsRemovedAsMain() throws {
        try withTempDir { dir in
            let store = try Self.project(dir)
            let legacy = store.legacyBuildFolder(set: Self.set, slug: Self.slug)
            try Self.write(TinyPNG.make(.rgba), to: legacy.appending(path: "out/renders/Default.png"))
            #expect(store.readBuilds(set: Self.set, slug: Self.slug).map(\.direction) == [BuildDirection.main])
            try store.removeBuild(set: Self.set, slug: Self.slug, direction: BuildDirection.main, discard: Self.remove)
            #expect(!FileManager.default.fileExists(atPath: legacy.path))
            #expect(store.readBuilds(set: Self.set, slug: Self.slug).isEmpty)
        }
    }

    @Test func aFolderIsReplacedWhole() throws {
        try withTempDir { dir in
            let fm = FileManager.default
            func folder(_ name: String, holding file: String) throws -> URL {
                let url = dir.appending(path: name, directoryHint: .isDirectory)
                try Self.write(Data(file.utf8), to: url.appending(path: file))
                return url
            }
            let dest = dir.appending(path: "Dial.icon", directoryHint: .isDirectory)
            // nothing there yet: a plain move
            try AtomicFolder.replace(dest, with: try folder(".staged-1", holding: "one"))
            #expect(fm.fileExists(atPath: dest.appending(path: "one").path))
            // there already: the old one goes whole, nothing of it stays
            try AtomicFolder.replace(dest, with: try folder(".staged-2", holding: "two"))
            #expect(try fm.contentsOfDirectory(atPath: dest.path) == ["two"])
            // the fallback for a volume that cannot swap does the same
            try AtomicFolder.swapByMoving(dest, with: try folder(".staged-3", holding: "three"))
            #expect(try fm.contentsOfDirectory(atPath: dest.path) == ["three"])
            #expect(try fm.contentsOfDirectory(atPath: dir.path) == ["Dial.icon"])
        }
    }

    @Test func aHeroWithoutIctoolIsCutToTheTile() throws {
        let square = LayerImage(side: 64, fill: SIMD4(0.5, 0.5, 0.5, 1))
        let tile = try square.maskedToTile()
        #expect(tile[0, 0].w == 0 && tile[63, 63].w == 0)
        #expect(tile[32, 32].w == 1 && tile[32, 32].x == 0.5)
        // the tile fills the frame, as Icon Composer's render does: an edge's middle is inside
        #expect(tile[32, 1].w > 0.5)
    }
}
