import Foundation
import Testing

@testable import RimlightCore

/// What `rimlight build` keeps beside its own files: the run's record, the prune and the package's name.
@Suite struct BuildFilesTests {
    @Test func theRecordIsWrittenWithEveryKey() throws {
        try withTempDir { dir in
            // a record needs its icon: a build never makes the folder of one the app deleted
            let store = try BuildStateTests.project(dir)
            let record = BuildRecord(
                pick: "abc", rimlight: "0.3.0", engine: "layers 1", stages: ["preview", "draw", "fit", "pack"], failed: nil,
                built: Date(timeIntervalSince1970: 1_800_000_000.4))
            try store.writeBuildRecord(record, set: "set-001", slug: "dial")
            let url = store.buildFolder(set: "set-001", slug: "dial").appending(path: "build.json")
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.contains("\"failed\" : null"))
            #expect(store.readBuildRecord(set: "set-001", slug: "dial") == record)
        }
    }

    @Test func pruneLeavesWhatCostsAndWhatTheReviewNeeds() throws {
        try withTempDir { dir in
            let fm = FileManager.default
            let keep = ["plan.json", "rounds/plan-1.json", "src/tile.png", "gen/ground.png", "gen/keycap.png",
                        "out/build.icon/icon.json", "out/assembled.png", "out/review.png"]
            let gone = ["layers/ground.png", "layers/keycap.png", "out/renders/Dark.png", "out/zoom-0-0-512-512.png"]
            for path in keep + gone {
                let url = dir.appending(path: path)
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(repeating: 1, count: 100).write(to: url)
            }
            let listed = try BuildPrune.prune(dir, dryRun: true)
            #expect(listed.bytes == 400)
            #expect(fm.fileExists(atPath: dir.appending(path: "layers").path))
            let (removed, bytes) = try BuildPrune.prune(dir)
            #expect(removed == ["layers", "out/renders", "out/zoom-0-0-512-512.png"])
            #expect(bytes == 400)
            for path in keep { #expect(fm.fileExists(atPath: dir.appending(path: path).path)) }
            for path in gone { #expect(!fm.fileExists(atPath: dir.appending(path: path).path)) }
        }
    }

    @Test func titlesBecomeSafePackageNames() {
        #expect(BuildLayout.packageName("Dial at the long end") == "Dial at the long end")
        #expect(BuildLayout.packageName("Long dial: v2/final") == "Long dial- v2-final")
        #expect(BuildLayout.packageName("  .hidden ") == "hidden")
        #expect(BuildLayout.packageName("   ") == "build")
        let store = BuildLayout(kind: .store, root: URL(filePath: "/p/sets", directoryHint: .isDirectory), package: "build")
        #expect(store.named("A/B").packageURL("set-001/x").path == "/p/sets/set-001/x/builds/main/out/A-B.icon")
    }
}

/// Clear and Tinted take the ground the build names, so an inverted, light Dark need not wash out the hero there.
@Test func tintedTakesTheGroundItIsGiven() throws {
    func tinted(_ document: [String: Any]) -> String? {
        let groups = document["groups"] as? [[String: Any]]
        let ground = (groups?.last?["layers"] as? [[String: Any]])?.first
        let images = ground?["image-name-specializations"] as? [[String: String]]
        return images?.first { $0["appearance"] == "tinted" }?["value"]
    }
    #expect(tinted(IconPackage.document(layers: [.init(name: "tile")])) == IconPackage.groundDark)
    #expect(tinted(IconPackage.document(layers: [.init(name: "tile")], tintedGround: IconPackage.ground)) == IconPackage.ground)
}

/// A layer in one appearance is hidden in the others, Clear and Tinted showing what Default shows; a reader of the
/// package tells the app which appearance a layer is in.
@Test func aLayerInOneAppearanceIsHiddenInTheOthers() throws {
    let document = IconPackage.document(layers: [
        .init(name: "cloud", only: .light), .init(name: "sun", dark: true), .init(name: "stars", only: .dark),
    ])
    let groups = try #require(document["groups"] as? [[String: Any]])
    let layers = try #require(groups[0]["layers"] as? [[String: Any]])
    func hidden(_ name: String) -> [[String: AnyHashable]]? {
        (layers.first { $0["name"] as? String == name }?["hidden-specializations"] as? [[String: Any]])?
            .map { $0.mapValues { $0 as! AnyHashable } }
    }
    #expect(hidden("stars") == [["value": true], ["appearance": "dark", "value": false], ["appearance": "tinted", "value": true]])
    #expect(hidden("cloud") == [["value": false], ["appearance": "dark", "value": true], ["appearance": "tinted", "value": false]])
    #expect(hidden("sun") == nil)

    try withTempDir { dir in
        let package = dir.appending(path: "Sky.icon", directoryHint: .isDirectory)
        try IconPackage.write(to: package, layers: [.init(name: "cloud", only: .light), .init(name: "stars", only: .dark)], assets: [:])
        let read = try #require(IconPackage.layers(of: package, relativeTo: dir))
        #expect(read.layers.map(\.only) == ["dark", "light"])
    }
}
