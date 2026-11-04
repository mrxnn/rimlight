import Foundation
import Synchronization
import Testing

@testable import RimlightCommand
@testable import RimlightCore

/// An icon's build directions: one folder each under `builds/`, their package names, the store's reads and writes,
/// the move of 0.4.2's `build/` to `builds/main/`, and the drawings one direction copies from another. Nothing here
/// draws: every run is a dry run or finds all it needs in another direction.
@Suite struct BuildDirectionTests {
    /// A project with one icon, `set-001/dial` titled "Dial".
    static func project(_ dir: URL) throws -> ProjectStore {
        let store = ProjectStore(projectRoot: dir)
        try store.create()
        let png = dir.appending(path: "render.png")
        try TinyPNG.make(.rgba).write(to: png)
        try store.addIcon(
            set: "set-001", slug: "dial", title: "Dial", prompt: "a dial", by: "claude-code", image: png,
            imageInfo: ImageInfo(width: 3, height: 2, alpha: true))
        return store
    }

    static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    static let record = BuildRecord(
        pick: "abc", rimlight: "0.4.3", engine: "layers 1", stages: ["pack"], failed: nil,
        built: Date(timeIntervalSince1970: 1_800_000_000))

    @Test func eachDirectionHasItsOwnFolderAndPackage() {
        let sets = URL(filePath: "/p/sets", directoryHint: .isDirectory)
        let main = BuildLayout(kind: .store, root: sets, package: "build").named("A/B")
        #expect(main.folder("set-001/x").path == "/p/sets/set-001/x/builds/main")
        #expect(main.packageURL("set-001/x").path == "/p/sets/set-001/x/builds/main/out/A-B.icon")
        let flipped = BuildLayout(kind: .store, root: sets, package: "build", direction: "flipped").named("A/B")
        #expect(flipped.packageURL("set-001/x").path == "/p/sets/set-001/x/builds/flipped/out/A-B, flipped.icon")
        #expect(flipped.folder("set-001/x", direction: "main").path == "/p/sets/set-001/x/builds/main")
        #expect(BuildLayout.packageName("  ", direction: "graphite") == "build, graphite")
        #expect(BuildLayout.packageName(".Dial", direction: "main") == "Dial")
        // the root layout has one build per id, as before
        let root = BuildLayout.root(URL(filePath: "/r", directoryHint: .isDirectory))
        #expect(root.packageURL("keycap").path == "/r/keycap/out/build.icon")
        #expect(root.directions("keycap") == [])

        #expect(BuildDirection.isValid("graphite-2"))
        #expect(!BuildDirection.isValid("Flipped"))
        #expect(!BuildDirection.isValid("a/b"))
        #expect(!BuildDirection.isValid(""))
        #expect(BuildDirection.ordered(["zeta", "flipped", "main"]) == ["main", "flipped", "zeta"])
    }

    @Test func theStoreListsDirectionsMainFirstWithTheirRecords() throws {
        try withTempDir { dir in
            let store = try Self.project(dir)
            #expect(store.buildDirections(set: "set-001", slug: "dial") == [])
            try store.writeBuildRecord(Self.record, set: "set-001", slug: "dial", direction: "flipped")
            try store.writeBuildRecord(Self.record, set: "set-001", slug: "dial")
            let builds = store.buildsFolder(set: "set-001", slug: "dial")
            // a file, and a folder whose name is no direction, are not directions
            try Self.write("x", to: builds.appending(path: "notes.txt"))
            try FileManager.default.createDirectory(at: builds.appending(path: "Old Copy"), withIntermediateDirectories: true)
            #expect(FileManager.default.fileExists(atPath: builds.appending(path: "flipped/build.json").path))
            let directions = store.buildDirections(set: "set-001", slug: "dial")
            #expect(directions.map(\.name) == ["main", "flipped"])
            #expect(directions[1].folder == store.buildFolder(set: "set-001", slug: "dial", direction: "flipped"))
            #expect(store.readBuildRecord(set: "set-001", slug: "dial", direction: "flipped") == Self.record)
            #expect(store.readBuildRecord(set: "set-001", slug: "dial", direction: "graphite") == nil)
            // the layout lists the same
            #expect(BuildLayout.store(store).directions("set-001/dial") == ["main", "flipped"])
        }
    }

    @Test func anIconHasABuildOnceADirectionIsPacked() throws {
        try withTempDir { dir in
            let store = try Self.project(dir)
            #expect(!store.hasBuild(set: "set-001", slug: "dial"))
            // a plan alone is a build started, not one made
            try Self.write("{}", to: store.buildFolder(set: "set-001", slug: "dial", direction: "flipped").appending(path: "plan.json"))
            #expect(!store.hasBuild(set: "set-001", slug: "dial"))
            try store.writeBuildRecord(Self.record, set: "set-001", slug: "dial", direction: "flipped")
            #expect(store.hasBuild(set: "set-001", slug: "dial"))
        }
        try withTempDir { dir in
            // an unmoved 0.4.2 build/ counts as main
            let store = try Self.project(dir)
            let legacy = store.legacyBuildFolder(set: "set-001", slug: "dial")
            try Self.write("{}", to: legacy.appending(path: "build.json"))
            #expect(store.hasBuild(set: "set-001", slug: "dial"))
        }
    }

    @Test func anOldBuildMovesToMain() throws {
        try withTempDir { dir in
            let store = try Self.project(dir)
            let fm = FileManager.default
            let legacy = store.legacyBuildFolder(set: "set-001", slug: "dial")
            #expect(try store.moveLegacyBuild(set: "set-001", slug: "dial") == .none)
            try Self.write("{}", to: legacy.appending(path: "plan.json"))
            try store.exclusive {
                try AtomicFile.write(try StateCoding.encode(Self.record), to: legacy.appending(path: "build.json"))
            }

            // before the move, readers find it as main
            #expect(store.buildDirections(set: "set-001", slug: "dial") == [BuildDirection(name: "main", folder: legacy)])
            #expect(store.readBuildRecord(set: "set-001", slug: "dial") == Self.record)

            #expect(try store.moveLegacyBuild(set: "set-001", slug: "dial") == .moved)
            let main = store.buildFolder(set: "set-001", slug: "dial")
            #expect(!fm.fileExists(atPath: legacy.path))
            #expect(fm.fileExists(atPath: main.appending(path: "plan.json").path))
            #expect(store.buildDirections(set: "set-001", slug: "dial").map(\.folder) == [main])
            #expect(store.readBuildRecord(set: "set-001", slug: "dial") == Self.record)
            #expect(try store.moveLegacyBuild(set: "set-001", slug: "dial") == .none)

            // a build/ beside an existing builds/main/ is left alone
            try Self.write("{\"old\": true}", to: legacy.appending(path: "plan.json"))
            #expect(try store.moveLegacyBuild(set: "set-001", slug: "dial") == .kept)
            #expect(try String(contentsOf: legacy.appending(path: "plan.json"), encoding: .utf8) == "{\"old\": true}")
            #expect(try String(contentsOf: main.appending(path: "plan.json"), encoding: .utf8) == "{}")
        }
    }

    // MARK: the command

    @Test func aDirectionIsAProjectsOnly() throws {
        try withTempDir { dir in
            #expect(throws: UsageError.self) { try Build.run(["--root", dir.path, "keycap", "--direction", "flipped"]) }
            #expect(throws: UsageError.self) { try Build.run(["set-001/dial", "--direction", "Flipped"]) }
            #expect(throws: UsageError.self) { try Build.run(["set-001/dial", "--direction", ""]) }
        }
    }

    @Test func resolvingMovesTheOldBuildAndNamesTheDirection() throws {
        try withTempDir { dir in
            let store = try Self.project(dir)
            try Self.write("{}", to: store.legacyBuildFolder(set: "set-001", slug: "dial").appending(path: "plan.json"))
            let args = try Arguments(
                ["set-001/dial", "--direction", "flipped", "--project", dir.path], options: ["--direction"])
            var lines: [String] = []
            guard case .target(let target) = try Build.resolve(args, say: { lines.append($0) }) else {
                Issue.record("the icon did not resolve")
                return
            }
            #expect(lines == ["MOVED set-001/dial: build/ to builds/main/"])
            #expect(FileManager.default.fileExists(
                atPath: store.buildFolder(set: "set-001", slug: "dial").appending(path: "plan.json").path))
            #expect(target.folder("set-001/dial") == store.buildFolder(set: "set-001", slug: "dial", direction: "flipped"))
            #expect(target.layout(for: "set-001/dial").packageURL("set-001/dial").lastPathComponent == "Dial, flipped.icon")
            #expect(target.command("set-001/dial").hasPrefix("rimlight build set-001/dial --direction flipped --project "))
        }
    }

    // MARK: shared drawings

    final class Lines: Sendable {
        let all = Mutex<[String]>([])
        var said: [String] { all.withLock { $0 } }
        func say(_ line: String) { all.withLock { $0.append(line) } }
    }

    static let mainPlan = #"{"ground": {"keep": "the black field", "remove": "the white eclipse"}, "dark": "generate", "layers": [{"name": "eclipse", "what": "the white eclipse"}, {"name": "flare", "what": "the thin flare"}]}"#
    /// main's ground and eclipse, its own flare and its own Dark.
    static let flippedPlan = #"{"ground": {"keep": "the black field", "remove": "the white eclipse"}, "dark": {"keep": "a white field"}, "layers": [{"name": "eclipse", "what": "the white eclipse"}, {"name": "flare", "what": "a longer flare"}]}"#

    /// One direction's build of `set-001/dial` with `plan` stored, previewed from the icon's pick.
    static func direction(_ store: ProjectStore, _ name: String, plan: String, lines: Lines) throws -> BuildStages {
        let layout = BuildLayout.store(store, direction: name)
        let target = Build.Target(
            layout: layout, ids: ["set-001/dial"], store: store, command: { "rimlight build \($0) --direction \(name)" },
            titles: ["set-001/dial": "Dial"])
        try PlanFile.store(Data(plan.utf8), in: layout.folder("set-001/dial"))
        let work = BuildStages(target: target, say: { lines.say($0) })
        try work.preview()
        return work
    }

    /// Stands in for Codex: writes each drawing of `plan` into the direction's `gen/` with the signature draw keeps.
    static func drawn(_ work: BuildStages, plan text: String) throws {
        let plan = try PlanFile.check(Data(text.utf8)).plan
        let gen = work.target.folder("set-001/dial").appending(path: "gen")
        var sigs = [BuildStages.groundName: BuildStages.signature(ground: plan)]
        if plan.dark.drawn { sigs[BuildStages.groundDarkName] = BuildStages.signature(dark: plan) }
        for layer in plan.layers { sigs[layer.name] = BuildStages.signature(layer, plan) }
        for (name, sig) in sigs {
            try write("\(work.target.layout.direction) \(name)", to: gen.appending(path: "\(name).png"))
            try write(sig, to: gen.appending(path: "\(name).sig"))
        }
    }

    /// A project whose pick is a real picture, so preview makes a tile.
    static func pictured(_ dir: URL) throws -> ProjectStore {
        let store = try project(dir)
        var pick = LayerImage(side: 64, fill: SIMD4(0, 0, 0, 1))
        for y in 20..<44 { for x in 20..<44 { pick[x, y] = SIMD4(1, 1, 1, 1) } }
        try pick.write(to: store.iconImageURL(set: "set-001", slug: "dial"))
        return store
    }

    @Test func aDrawingFromTheSameWordsIsCopiedNotDrawn() throws {
        try withTempDir { dir in
            let store = try Self.pictured(dir)
            let lines = Lines()
            let main = try Self.direction(store, "main", plan: Self.mainPlan, lines: lines)
            try Self.drawn(main, plan: Self.mainPlan)
            let flipped = try Self.direction(store, "flipped", plan: Self.flippedPlan, lines: lines)
            // the same pick previews to the same ref.png in each direction, which sharing relies on
            let ref = "set-001/dial"
            #expect(FileManager.default.contentsEqual(
                atPath: main.target.layout.file(ref, "src/ref.png").path,
                andPath: flipped.target.layout.file(ref, "src/ref.png").path))

            let before = lines.said.count
            let priced = try flipped.draw(redraw: [], dryRun: true)
            #expect(priced.cost == "COST 2 images (set-001/dial/flare, set-001/dial/ground-dark)")
            #expect(Array(lines.said[before...]) == [
                "COST 2 images (set-001/dial/flare, set-001/dial/ground-dark)",
                "  would share set-001/dial/ground from main",
                "  would share set-001/dial/eclipse from main",
                "  would draw set-001/dial/flare",
                "  would draw set-001/dial/ground-dark",
            ])
            // the dry run copied nothing
            #expect(!FileManager.default.fileExists(atPath: flipped.target.layout.file(ref, "gen/ground.png").path))

            // a redraw asks Codex, whatever another direction has
            let redrawn = try flipped.draw(redraw: ["eclipse"], dryRun: true)
            #expect(redrawn.cost == "COST 3 images (set-001/dial/eclipse, set-001/dial/flare, set-001/dial/ground-dark)")
        }
    }

    @Test func aDirectionWithEverythingDrawnElsewhereCostsNothing() throws {
        try withTempDir { dir in
            let store = try Self.pictured(dir)
            let lines = Lines()
            let main = try Self.direction(store, "main", plan: Self.mainPlan, lines: lines)
            try Self.drawn(main, plan: Self.mainPlan)
            try Self.write("main key", to: main.target.layout.file("set-001/dial", "gen/eclipse.key"))
            let graphite = try Self.direction(store, "graphite", plan: Self.mainPlan, lines: lines)
            // an earlier drawing of its own, whose words have changed since
            let own = graphite.target.layout.file("set-001/dial", "gen/eclipse.png")
            try Self.write("graphite eclipse", to: own)
            try Self.write("old words", to: graphite.target.layout.file("set-001/dial", "gen/eclipse.sig"))

            let before = lines.said.count
            let run = try graphite.draw(redraw: [], dryRun: false)
            #expect(run.cost == "COST 0 images")
            #expect(run.status == 0)
            #expect(Array(lines.said[before...]) == [
                "COST 0 images",
                "SHARED set-001/dial/ground from main",
                "SHARED set-001/dial/eclipse from main",
                "SHARED set-001/dial/flare from main",
                "SHARED set-001/dial/ground-dark from main",
            ])
            let file = { (path: String) in graphite.target.layout.file("set-001/dial", path) }
            #expect(try String(contentsOf: own, encoding: .utf8) == "main eclipse")
            #expect(try String(contentsOf: file("gen/eclipse.key"), encoding: .utf8) == "main key")
            #expect(try String(contentsOf: file("gen/ground-dark.png"), encoding: .utf8) == "main ground-dark")
            // the drawing it replaced is kept for --restore, as a redraw's is
            #expect(try String(contentsOf: file("gen/rounds/eclipse-1.png"), encoding: .utf8) == "graphite eclipse")
            // a copy, not a link
            let attributes = try FileManager.default.attributesOfItem(atPath: own.path)
            #expect(attributes[.type] as? FileAttributeType == .typeRegular)

            // nothing left to draw or copy
            let again = try graphite.draw(redraw: [], dryRun: true)
            #expect(again.cost == "COST 0 images")

            // main's four drawings and graphite's replaced one: the copies are the same files and count once
            #expect(graphite.spentLine("set-001/dial") == "SPENT set-001/dial: 5 images drawn for this icon so far, every direction together")
        }
    }

    /// A named direction's first build makes its own tile, which is free; it stopped at "no tile yet" before.
    @Test func aNewDirectionPreviewsItself() throws {
        try withTempDir { dir in
            let store = try Self.pictured(dir)
            let lines = Lines()
            let layout = BuildLayout.store(store, direction: "dimmed")
            let work = BuildStages(
                target: Build.Target(
                    layout: layout, ids: ["set-001/dial"], store: store, command: { "rimlight build \($0) --direction dimmed" },
                    titles: ["set-001/dial": "Dial"]),
                say: { lines.say($0) })
            #expect(work.missingInput("draw", redraw: [], planStored: false) != nil)
            try work.previewMissing()
            #expect(work.missingInput("draw", redraw: [], planStored: false) == nil)
            #expect(lines.said.first?.hasPrefix("PREVIEW set-001/dial") == true)
            // a second call finds the tile and says nothing
            let count = lines.said.count
            try work.previewMissing()
            #expect(lines.said.count == count)
        }
    }

    @Test func anotherPickOrAnotherGroundSharesNothing() throws {
        try withTempDir { dir in
            let store = try Self.pictured(dir)
            let lines = Lines()
            let main = try Self.direction(store, "main", plan: Self.mainPlan, lines: lines)
            try Self.drawn(main, plan: Self.mainPlan)
            let other = try Self.direction(store, "other", plan: Self.mainPlan, lines: lines)

            // other drew its own ground from the same words: main's Dark ground, an edit of main's ground, does not fit it
            let ground = other.target.layout.file("set-001/dial", "gen/ground.png")
            try Self.write("other ground", to: ground)
            try Self.write(BuildStages.signature(ground: try PlanFile.check(Data(Self.mainPlan.utf8)).plan),
                to: other.target.layout.file("set-001/dial", "gen/ground.sig"))
            let darkOnly = try other.draw(redraw: [], dryRun: true)
            #expect(darkOnly.cost == "COST 1 image (set-001/dial/ground-dark)")

            // a direction previewed from another pick drew other pictures
            try Self.write("another pick", to: main.target.layout.file("set-001/dial", "src/ref.png"))
            let all = try other.draw(redraw: [], dryRun: true)
            #expect(all.cost == "COST 3 images (set-001/dial/eclipse, set-001/dial/flare, set-001/dial/ground-dark)")
        }
    }

    // MARK: Dark is free

    @Test func changingDarkDrawsNoLayer() throws {
        let dim = #"{"ground": {"keep": "the black field", "remove": "the white eclipse"}, "dark": "dim", "layers": [{"name": "eclipse", "what": "the white eclipse"}, {"name": "flare", "what": "the thin flare"}]}"#
        let tone = dim.replacingOccurrences(of: #""dark": "dim""#, with: ##""dark": {"tone": "#0b0b0c"}"##)
        let a = try PlanFile.check(Data(dim.utf8)).plan, b = try PlanFile.check(Data(tone.utf8)).plan
        for (x, y) in zip(a.layers, b.layers) { #expect(BuildStages.signature(x, a) == BuildStages.signature(y, b)) }
        // the prompt still asks neutral light only when Dark recolours the ground
        #expect(!LayerPrompts.layer(a, a.layers[0]).contains("neutral white light"))
        #expect(LayerPrompts.layer(b, b.layers[0]).contains("neutral white light"))

        try withTempDir { dir in
            let store = try Self.pictured(dir)
            let lines = Lines()
            let main = try Self.direction(store, "main", plan: tone, lines: lines)
            try Self.drawn(main, plan: tone)
            // drawn by 0.5.0: under dim each layer's .sig ended in an empty line, under any other Dark in "neutral light"
            let gen = main.target.folder("set-001/dial").appending(path: "gen")
            try Self.write(BuildStages.signature(a.layers[0], a) + "\n", to: gen.appending(path: "eclipse.sig"))
            try Self.write(BuildStages.signature(a.layers[1], a) + "\nneutral light", to: gen.appending(path: "flare.sig"))
            #expect(try main.draw(redraw: [], dryRun: true).cost == "COST 0 images")

            // a direction with another Dark shares both, the old signatures included
            let dimmed = try Self.direction(store, "dimmed", plan: dim, lines: lines)
            let before = lines.said.count
            #expect(try dimmed.draw(redraw: [], dryRun: true).cost == "COST 0 images")
            #expect(Array(lines.said[before...]) == [
                "COST 0 images",
                "  would share set-001/dial/ground from main",
                "  would share set-001/dial/eclipse from main",
                "  would share set-001/dial/flare from main",
            ])
        }
        // only a layer's signature loses the old line, and only the last one
        #expect(BuildStages.normalised("ground 1\nk\nneutral light") == "ground 1\nk\nneutral light")
        #expect(BuildStages.normalised("layer 1\nw\n\n\nmagenta\nneutral light") == "layer 1\nw\n\n\nmagenta")
        #expect(!BuildStages.sameSignature("layer 1\nother\n\n\nmagenta\n", "layer 1\nw\n\n\nmagenta"))
        #expect(!BuildStages.sameSignature(nil, "layer 1\nw\n\n\nmagenta"))
    }

    // MARK: zoom along an outline

    @Test func zoomWalksANamedOutlineOrEvery() throws {
        func aid(_ raw: [String]) throws -> Aid {
            try Aid.parse("zoom", Arguments(
                raw, flags: ["--quadrants", "--outlines"], options: ["--box", "--rendition", "--scale", "--outline"]))
        }
        #expect(try aid(["--outline", "tile", "--outline", "dot"]).outlines == ["tile", "dot"])
        #expect(try aid(["--outlines"]).outlines == [])
        #expect(try aid(["--outlines", "--rendition", "Dark"]).renditions == ["Dark"])
        #expect(try aid(["--quadrants"]).outlines == nil)
        #expect(throws: UsageError.self) { try aid(["--outline", "tile", "--quadrants"]) }
        #expect(throws: UsageError.self) { try aid(["--outlines", "--scale", "2"]) }
        #expect(throws: UsageError.self) {
            try Aid.parse("grid", Arguments(["--box", "0,0,8,8", "--outlines"], flags: ["--outlines"], options: ["--box"]))
        }
    }
}
