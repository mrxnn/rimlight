import Foundation
import Testing

@testable import RimlightCore

@Suite struct StoreTests {
    /// A created project, plus a helper that writes a tiny PNG to a temp path for `addIcon`.
    struct Fixture {
        let dir: URL
        let store: ProjectStore

        init(_ dir: URL) throws {
            self.dir = dir
            store = ProjectStore(projectRoot: dir)
            try store.create()
        }

        func tempPNG(_ kind: TinyPNG.Kind = .rgba) throws -> URL {
            let url = dir.appending(path: "render-\(UUID().uuidString).png")
            try TinyPNG.make(kind).write(to: url)
            return url
        }

        @discardableResult
        func add(
            _ slug: String, set: String = "set-001", parent: IconParent? = nil, refs: [IconReference] = [],
            prompt: String? = nil, fixes: [String] = [], fixAttempts: [FixAttempt] = [], replace: Bool = false,
            created: Date = .now
        ) throws -> IconSnapshot {
            try store.addIcon(
                set: set, slug: slug, title: "Title \(slug)", prompt: prompt ?? "prompt \(slug)", parent: parent, refs: refs,
                generator: GeneratorInfo(tool: "codex-image-gen", model: "gpt-6-luna"), by: "claude-code",
                image: try tempPNG(), imageInfo: ImageInfo(width: 3, height: 2, alpha: true), fixes: fixes,
                fixAttempts: fixAttempts, replace: replace, created: created)
        }
    }

    @Test func createMakesProjectAndFirstSet() throws {
        try withTempDir { dir in
            #expect(!ProjectStore.exists(at: dir))
            let store = ProjectStore(projectRoot: dir)
            #expect(try store.create())
            #expect(ProjectStore.exists(at: dir))
            #expect(try store.readProject().schema == 1)
            let sets = try store.readSets()
            #expect(sets.map(\.id) == ["set-001"])
            #expect(sets.first?.title == "Untitled set")
            #expect(sets.first?.chat == [:])
            // Idempotent.
            #expect(try store.create() == false)
            #expect(try store.readSets().count == 1)
        }
    }

    @Test func locateWalksUp() throws {
        try withTempDir { dir in
            #expect(ProjectStore.locate(from: dir) == nil)
            try ProjectStore(projectRoot: dir).create()
            let deep = dir.appending(path: "a/b/c", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
            #expect(ProjectStore.locate(from: deep)?.path == dir.path)
            #expect(ProjectStore.locate(from: dir)?.path == dir.path)
            // A store opened on `.rimlight` itself points at the project.
            #expect(ProjectStore(projectRoot: dir.appending(path: ".rimlight")).root.path == dir.path)
        }
    }

    @Test func createSetIncrementsAndListsNewestFirst() throws {
        try withTempDir { dir in
            let f = try Fixture(dir)
            #expect(try f.store.createSet(title: "Cream hardware").id == "set-002")
            #expect(try f.store.createSet(title: "  ").title == "Untitled set")
            #expect(try f.store.readSets().map(\.id) == ["set-003", "set-002", "set-001"])
            // A stray folder is not a set.
            try FileManager.default.createDirectory(at: f.store.setsDir.appending(path: "notes"), withIntermediateDirectories: true)
            #expect(try f.store.readSets().count == 3)
            #expect(try f.store.createSet().id == "set-004")
        }
    }

    @Test func setIDsOrderByNumber() {
        let ids = ["set-002", "set-1000", "set-999", "set-010"]
        #expect(ids.sorted(by: SetID.newestFirst) == ["set-1000", "set-999", "set-010", "set-002"])
        #expect(SetID.isValid("set-001"))
        #expect(!SetID.isValid("set-1"))
        #expect(!SetID.isValid("set-00a"))
    }

    @Test func renameSet() throws {
        try withTempDir { dir in
            let f = try Fixture(dir)
            #expect(try f.store.renameSet("set-001", title: " Spike ").title == "Spike")
            #expect(try f.store.readSet("set-001").title == "Spike")
            #expect(throws: StoreError.self) { try f.store.renameSet("set-001", title: " ") }
            #expect(throws: StoreError.self) { try f.store.renameSet("set-009", title: "Nope") }
        }
    }

    @Test func chatSessions() throws {
        try withTempDir { dir in
            let f = try Fixture(dir)
            try f.store.setChat(set: "set-001", harness: "claude", session: "abc")
            #expect(try f.store.readSet("set-001").chat == ["claude": "abc"])
            try f.store.setChat(set: "set-001", harness: "claude", session: nil)
            #expect(try f.store.readSet("set-001").chat == [:])
            // New Session forgets the current one; the history keeps it, once, oldest first.
            try f.store.setChat(set: "set-001", harness: "claude", session: "def")
            try f.store.setChat(set: "set-001", harness: "claude", session: "abc")
            let set = try f.store.readSet("set-001")
            #expect(set.chat == ["claude": "abc"])
            #expect(set.chatHistory == ["claude": ["abc", "def"]])

            try f.add("counter")
            let snapshot = try f.store.setIconChat(set: "set-001", slug: "counter", harness: "claude", session: "s1")
            #expect(snapshot.icon.chat == ["claude": "s1"])
            #expect(snapshot.icon.chatHistory == ["claude": ["s1"]])
            try f.store.setIconChat(set: "set-001", slug: "counter", harness: "claude", session: nil)
            let icon = try f.store.readIcon(set: "set-001", slug: "counter").icon
            #expect(icon.chat == [:])
            #expect(icon.chatHistory == ["claude": ["s1"]])
        }
    }

    @Test func batchArchiveAndDelete() throws {
        try withTempDir { dir in
            let f = try Fixture(dir)
            try f.add("one")
            try f.add("two")
            try f.add("three")
            let results = try f.store.setArchived([("set-001", "one"), ("set-001", "gone"), ("set-001", "two")], true)
            #expect(results.count == 3)
            #expect((try? results[0].get())?.icon.archived == true)
            #expect((try? results[1].get()) == nil)
            #expect((try? results[2].get())?.icon.slug == "two")
            let icons = try f.store.readIcons(in: "set-001")
            #expect(icons.filter(\.icon.archived).map(\.icon.slug).sorted() == ["one", "two"])

            let removed = try f.store.deleteIcons([("set-001", "one"), ("set-001", "gone"), ("set-001", "three")])
            #expect(removed.map { (try? $0.get()) != nil } == [true, false, true])
            #expect(try f.store.readIcons(in: "set-001").map(\.icon.slug) == ["two"])
        }
    }

    @Test func chatHistoryKeepsTheNewest() {
        var history: [String: [String]] = [:]
        for i in 0..<(ChatSessions.limit + 5) { ChatSessions.record("s\(i)", in: &history, harness: "claude") }
        let list = history["claude"] ?? []
        #expect(list.count == ChatSessions.limit)
        #expect(list.first == "s5")
        #expect(list.last == "s\(ChatSessions.limit + 4)")
        // A record from before the history: its current session still counts.
        #expect(ChatSessions.sessions(chat: ["claude": "old"], history: [:], harness: "claude") == ["old"])
        #expect(ChatSessions.sessions(chat: ["claude": "s5"], history: history, harness: "claude") == list)
        #expect(ChatSessions.sessions(chat: [:], history: [:], harness: "claude") == [])
    }

    @Test func recordsWithoutHistoryStillDecode() throws {
        let json = #"{"schema":1,"id":"set-001","title":"T","created":"2026-10-10T15:20:29Z","chat":{"claude":"x"}}"#
        let set = try StateCoding.decoder().decode(IconSet.self, from: Data(json.utf8))
        #expect(set.chat == ["claude": "x"])
        #expect(set.chatHistory == [:])
    }

    @Test func newerProjectSchemaIsRefused() throws {
        try withTempDir { dir in
            let f = try Fixture(dir)
            #expect(try f.store.readProject().schema == Project.currentSchema)
            try f.store.checkSchema()

            // Fields a newer rimlight might have changed are never read.
            try Data(#"{"schema":99,"created":12}"#.utf8).write(to: f.store.projectURL)
            let message = "This project was written by a newer rimlight (schema 99; this build reads 1). Update rimlight."
            #expect(StoreError.newerSchema(99).description == message)
            #expect(throws: StoreError.newerSchema(99)) { try f.store.readProject() }
            #expect(throws: StoreError.newerSchema(99)) { try f.store.checkSchema() }
            #expect(throws: StoreError.newerSchema(99)) { try f.store.create() }

            // An older or equal schema reads as today; a missing or broken file is not this check's.
            try Data(#"{"schema":1,"created":"2026-10-10T15:20:29Z"}"#.utf8).write(to: f.store.projectURL)
            #expect(try f.store.readProject().schema == 1)
            try f.store.checkSchema()
            try Data("not json".utf8).write(to: f.store.projectURL)
            try f.store.checkSchema()
            try FileManager.default.removeItem(at: f.store.projectURL)
            try f.store.checkSchema()
        }
    }

    @Test func newerSetAndIconRecordsAreSkippedOrRefused() throws {
        try withTempDir { dir in
            let f = try Fixture(dir)
            try f.store.createSet(title: "Newer")
            try f.add("old")
            try f.add("new")
            let bump = { (url: URL) throws in
                let text = try String(contentsOf: url, encoding: .utf8)
                try Data(text.replacingOccurrences(of: #""schema" : 1"#, with: #""schema" : 2"#).utf8).write(to: url)
            }
            try bump(f.store.setURL("set-002"))
            try bump(f.store.iconRecordURL(set: "set-001", slug: "new"))

            // Lists skip them like undecodable records; reads and writes of one refuse it.
            #expect(try f.store.readSets().map(\.id) == ["set-001"])
            #expect(try f.store.readIcons(in: "set-001").map(\.icon.slug) == ["old"])
            #expect(throws: StoreError.newerSchema(2)) { try f.store.readSet("set-002") }
            #expect(throws: StoreError.newerSchema(2)) { try f.store.renameSet("set-002", title: "T") }
            #expect(throws: StoreError.newerSchema(2)) { try f.store.readIcon(set: "set-001", slug: "new") }
            #expect(throws: StoreError.newerSchema(2)) { try f.store.setArchived(set: "set-001", slug: "new", true) }
            #expect(throws: StoreError.newerSchema(2)) { try f.add("new", replace: true) }
            let record = try String(contentsOf: f.store.iconRecordURL(set: "set-001", slug: "new"), encoding: .utf8)
            #expect(record.contains(#""schema" : 2"#), "the newer record is left as it was")
        }
    }

    @Test func addIconWritesRecordAndRefusesDuplicates() throws {
        try withTempDir { dir in
            let f = try Fixture(dir)
            let temp = try f.tempPNG()
            let snapshot = try f.store.addIcon(
                set: "set-001", slug: "counter-cream", title: "Counter, cream", prompt: "the prompt",
                refs: [.file("/abs/other.png")], by: "claude-code", image: temp,
                imageInfo: ImageInfo(width: 3, height: 2, alpha: true))
            #expect(snapshot.id == "set-001/counter-cream")
            #expect(snapshot.icon.mode == .generate)
            #expect(snapshot.stamp != nil)
            #expect(!FileManager.default.fileExists(atPath: temp.path), "the temp render is moved, not copied")
            #expect(FileManager.default.fileExists(atPath: snapshot.imageURL.path))

            let json = try String(contentsOf: f.store.iconRecordURL(set: "set-001", slug: "counter-cream"), encoding: .utf8)
            #expect(json.contains(#""parent" : null"#))
            #expect(json.contains(#""schema" : 1"#))
            #expect(json.contains(#""path" : "/abs/other.png""#))
            #expect(json.contains(#""generator" : null"#))

            #expect(throws: StoreError.alreadyExists(
                "Icon set-001/counter-cream already exists; pick a new slug or replace it")
            ) { try f.add("counter-cream") }

            let child = try f.add("counter-black", parent: IconParent(set: "set-001", icon: "counter-cream"))
            #expect(child.icon.mode == .refine)
            #expect(throws: StoreError.self) { try f.add("x", parent: IconParent(set: "set-001", icon: "missing")) }
            #expect(throws: StoreError.self) { try f.add("y", set: "set-002") }
            #expect(throws: StoreError.self) { try f.add("Bad Slug") }
        }
    }

    @Test func addIconKeepsTheRawRenderAndAReplacementWithoutOneDropsIt() throws {
        try withTempDir { dir in
            let f = try Fixture(dir)
            let raw = try f.tempPNG()
            try f.store.addIcon(
                set: "set-001", slug: "fitted", title: "Fitted", prompt: "p", by: "claude-code", image: try f.tempPNG(),
                raw: raw, imageInfo: ImageInfo(width: 3, height: 2, alpha: true))
            let rawURL = f.store.iconRawImageURL(set: "set-001", slug: "fitted")
            #expect(FileManager.default.fileExists(atPath: rawURL.path))
            #expect(!FileManager.default.fileExists(atPath: raw.path))

            try f.add("fitted", replace: true)
            #expect(!FileManager.default.fileExists(atPath: rawURL.path))
            #expect(try f.store.readIcons(in: "set-001").map(\.icon.slug) == ["fitted"])
        }
    }

    @Test func addIconKeepsTheOriginalRenderAndAReplacementWithoutOneDropsIt() throws {
        try withTempDir { dir in
            let f = try Fixture(dir)
            let original = try f.tempPNG()
            let before = try f.store.addIcon(
                set: "set-001", slug: "cut", title: "Cut", prompt: "p", by: "claude-code", image: try f.tempPNG(),
                raw: try f.tempPNG(), original: original, imageInfo: ImageInfo(width: 3, height: 2, alpha: true))
            let originalURL = f.store.iconOriginalImageURL(set: "set-001", slug: "cut")
            #expect(FileManager.default.fileExists(atPath: originalURL.path))
            #expect(!FileManager.default.fileExists(atPath: original.path))

            // A refit swaps icon.png and raw.png and leaves the original alone.
            try f.store.replaceImage(
                set: "set-001", slug: "cut", image: try f.tempPNG(), raw: try f.tempPNG(),
                imageInfo: ImageInfo(width: 3, height: 2, alpha: true), stamp: before.stamp)
            #expect(FileManager.default.fileExists(atPath: originalURL.path))

            try f.add("cut", replace: true)
            #expect(!FileManager.default.fileExists(atPath: originalURL.path))
        }
    }

    @Test func replaceImageSwapsTheFilesAndKeepsTheRecord() throws {
        try withTempDir { dir in
            let f = try Fixture(dir)
            let before = try f.add("refit", prompt: "concept", fixes: ["a fix"])
            let saved = try f.store.replaceImage(
                set: "set-001", slug: "refit", image: try f.tempPNG(), raw: try f.tempPNG(),
                imageInfo: ImageInfo(width: 1254, height: 1254, alpha: true), stamp: before.stamp)
            #expect(saved.icon.image == ImageInfo(width: 1254, height: 1254, alpha: true))
            let reread = try f.store.readIcon(set: "set-001", slug: "refit")
            #expect(reread.icon.prompt == "concept" && reread.icon.fixes == ["a fix"])
            #expect(reread.icon.created == before.icon.created)
            #expect(FileManager.default.fileExists(atPath: f.store.iconRawImageURL(set: "set-001", slug: "refit").path))

            // A stamp from before the swap no longer matches, so a second swap is refused.
            #expect(throws: StoreError.self) {
                try f.store.replaceImage(
                    set: "set-001", slug: "refit", image: try f.tempPNG(), raw: try f.tempPNG(),
                    imageInfo: ImageInfo(width: 3, height: 2, alpha: true), stamp: FileStamp(mtimeNS: 1, size: 1))
            }
        }
    }

    @Test func addIconPlacesPNGBeforeRecord() throws {
        try withTempDir { dir in
            let f = try Fixture(dir)
            // A folder where icon.json should go makes the final rename fail.
            let folder = f.store.iconFolder(set: "set-001", slug: "half")
            try FileManager.default.createDirectory(
                at: folder.appending(path: "icon.json", directoryHint: .isDirectory), withIntermediateDirectories: true)
            #expect(throws: StoreError.self) { try f.add("half") }
            #expect(FileManager.default.fileExists(atPath: folder.appending(path: "icon.png").path))
            // Without its record the icon is invisible to readers.
            #expect(try f.store.readIcons(in: "set-001").isEmpty)
        }
    }

    @Test func replaceKeepsIdentityAndLineage() throws {
        try withTempDir { dir in
            let f = try Fixture(dir)
            let created = Date(timeIntervalSince1970: 1_800_000_000)
            try f.add("base")
            try f.add(
                "edit", parent: IconParent(set: "set-001", icon: "base"), refs: [.icon(set: "set-001", icon: "base")],
                created: created)
            try f.store.setIconChat(set: "set-001", slug: "edit", harness: "claude", session: "s1")
            try f.store.setArchived(set: "set-001", slug: "edit", true)
            try f.store.setFavorite(set: "set-001", slug: "edit", true)

            // The transparent re-edit: Image 1 is the icon itself, no --parent.
            let fixed = try f.add("edit", refs: [.icon(set: "set-001", icon: "edit")], replace: true)
            #expect(fixed.icon.created == created)
            #expect(fixed.icon.chat == ["claude": "s1"])
            #expect(fixed.icon.chatHistory == ["claude": ["s1"]])
            #expect(fixed.icon.archived)
            #expect(fixed.icon.favorite)
            #expect(fixed.icon.parent == IconParent(set: "set-001", icon: "base"))
            #expect(fixed.icon.mode == .refine)
            #expect(fixed.icon.refs == [.icon(set: "set-001", icon: "base")])
            #expect(try f.store.readIcon(set: "set-001", slug: "edit") == fixed)

            #expect(throws: StoreError.self) {
                try f.add("solo", parent: IconParent(set: "set-001", icon: "solo"))
            }
        }
    }

    @Test func aFixOfItsOwnFileKeepsTheConceptPrompt() throws {
        try withTempDir { dir in
            let f = try Fixture(dir)
            let base = try f.add("olive", prompt: "Square image. An olive device.")
            #expect(base.icon.fixes == nil)
            let record = f.store.iconRecordURL(set: "set-001", slug: "olive")
            #expect(try String(contentsOf: record, encoding: .utf8).contains(#""fixes" : null"#))

            // The transparency fix: Image 1 is the icon's own file, replaced with --force.
            let me = IconReference.icon(set: "set-001", icon: "olive")
            let fixed = try f.add("olive", refs: [me], prompt: "Edit Image 1. Remove the backdrop.", replace: true)
            #expect(fixed.icon.prompt == "Square image. An olive device.")
            #expect(fixed.icon.fixes == ["Edit Image 1. Remove the backdrop."])
            let again = try f.add("olive", refs: [me], prompt: "Edit Image 1. Clear the corners.", replace: true)
            #expect(again.icon.prompt == "Square image. An olive device.")
            #expect(again.icon.fixes == ["Edit Image 1. Remove the backdrop.", "Edit Image 1. Clear the corners."])
            #expect(try f.store.readIcon(set: "set-001", slug: "olive") == again)

            // A record written before the field existed reads as no fixes.
            var json = try String(contentsOf: record, encoding: .utf8)
            json = json.replacingOccurrences(of: #""fixes" : ["#, with: #""unused" : ["#)
            try Data(json.utf8).write(to: record)
            #expect(try f.store.readIcon(set: "set-001", slug: "olive").icon.fixes == nil)
        }
    }

    /// `generate` fixes a render before storing it, so a new icon can arrive with fixes.
    @Test func fixesMadeBeforeStoringAreAppended() throws {
        try withTempDir { dir in
            let f = try Fixture(dir)
            let fresh = try f.add("olive", prompt: "Square image. An olive device.", fixes: ["Edit Image 1. Clear it."])
            #expect(fresh.icon.prompt == "Square image. An olive device.")
            #expect(fresh.icon.fixes == ["Edit Image 1. Clear it."])

            // An edit of its own file, itself fixed before storing: both land in order.
            let me = IconReference.icon(set: "set-001", icon: "olive")
            let again = try f.add(
                "olive", refs: [me], prompt: "Edit Image 1. Red body.", fixes: ["Edit Image 1. Clear it."], replace: true)
            #expect(again.icon.prompt == "Square image. An olive device.")
            #expect(again.icon.fixes == ["Edit Image 1. Clear it.", "Edit Image 1. Red body.", "Edit Image 1. Clear it."])

            // A redo starts its fixes over.
            let redo = try f.add("olive", prompt: "Square image. A sage device.", fixes: ["Edit Image 1. Clear it."], replace: true)
            #expect(redo.icon.fixes == ["Edit Image 1. Clear it."])
        }
    }

    /// Every fix attempt is recorded, written as null when there were none, and read as nil
    /// from a record written before the field existed.
    @Test func fixAttemptsAreRecorded() throws {
        try withTempDir { dir in
            let f = try Fixture(dir)
            let edit = FixAttempt(kind: .transparencyEdit, transparent: false, seconds: 48.2)
            let reroll = FixAttempt(kind: .reroll, transparent: true, seconds: 55)
            let base = try f.add("olive", prompt: "Square image. An olive device.")
            #expect(base.icon.fixAttempts == nil)
            let record = f.store.iconRecordURL(set: "set-001", slug: "olive")
            #expect(try String(contentsOf: record, encoding: .utf8).contains(#""fixAttempts" : null"#))

            let fresh = try f.add("olive", prompt: "Square image. An olive device.", fixAttempts: [edit, reroll], replace: true)
            #expect(fresh.icon.fixAttempts == [edit, reroll])
            let json = try String(contentsOf: record, encoding: .utf8)
            #expect(json.contains(#""kind" : "transparency-edit""#) && json.contains(#""kind" : "reroll""#))
            #expect(json.contains(#""transparent" : true"#) && json.contains(#""seconds" : 48.2"#))
            #expect(try f.store.readIcon(set: "set-001", slug: "olive") == fresh)

            // A fix of its own file keeps the attempts before it; failed attempts are appended.
            let me = IconReference.icon(set: "set-001", icon: "olive")
            let fixed = try f.add("olive", refs: [me], prompt: TransparencyFix.prompt, fixAttempts: [edit], replace: true)
            #expect(fixed.icon.fixAttempts == [edit, reroll, edit])
            let failed = try f.store.addFixAttempts(set: "set-001", slug: "olive", [edit, edit])
            #expect(failed.icon.fixAttempts == [edit, reroll, edit, edit, edit])
            #expect(FileStamp.of(failed.imageURL) == fixed.stamp)

            // A redo starts its attempts over.
            let redo = try f.add("olive", prompt: "Square image. A sage device.", replace: true)
            #expect(redo.icon.fixAttempts == nil)

            var old = try String(contentsOf: record, encoding: .utf8)
            old = old.replacingOccurrences(of: #""fixAttempts" : null"#, with: #""unused" : null"#)
            try Data(old.utf8).write(to: record)
            #expect(try f.store.readIcon(set: "set-001", slug: "olive").icon.fixAttempts == nil)
        }
    }

    @Test func setAlphaCorrectsTheRecordOnly() throws {
        try withTempDir { dir in
            let f = try Fixture(dir)
            let base = try f.add("olive")
            #expect(base.icon.image.alpha)
            let opaque = try f.store.setAlpha(set: "set-001", slug: "olive", false)
            #expect(opaque.icon.image == ImageInfo(width: 3, height: 2, alpha: false))
            #expect(try f.store.readIcon(set: "set-001", slug: "olive").icon.image.alpha == false)
            #expect(FileStamp.of(opaque.imageURL) == base.stamp)
        }
    }

    @Test func aRedoTakesTheNewPrompt() throws {
        try withTempDir { dir in
            let f = try Fixture(dir)
            try f.add("olive", prompt: "Square image. An olive device.")
            let me = IconReference.icon(set: "set-001", icon: "olive")
            try f.add("olive", refs: [me], prompt: "Edit Image 1. Remove the backdrop.", replace: true)

            // --force with no ref to itself: a new render from a new prompt; the old fixes go with the old render.
            let redo = try f.add(
                "olive", refs: [.file("/abs/moodboard.png")], prompt: "Square image. A sage device.", replace: true)
            #expect(redo.icon.prompt == "Square image. A sage device.")
            #expect(redo.icon.fixes == nil)
            #expect(redo.icon.refs == [.file("/abs/moodboard.png")])
            let bare = try f.add("olive", prompt: "Square image. A moss device.", replace: true)
            #expect(bare.icon.prompt == "Square image. A moss device.")
            #expect(bare.icon.fixes == nil)
        }
    }

    @Test func archivedFlag() throws {
        try withTempDir { dir in
            let f = try Fixture(dir)
            try f.add("a")
            #expect(try f.store.readIcon(set: "set-001", slug: "a").icon.archived == false)
            #expect(try f.store.setArchived(set: "set-001", slug: "a", true).icon.archived)
            #expect(try f.store.readIcon(set: "set-001", slug: "a").icon.archived)
            try f.store.setArchived(set: "set-001", slug: "a", false)
            #expect(try f.store.readIcon(set: "set-001", slug: "a").icon.archived == false)
        }
    }

    @Test func favoriteFlag() throws {
        try withTempDir { dir in
            let f = try Fixture(dir)
            try f.add("a")
            try f.add("b")
            #expect(try f.store.readIcon(set: "set-001", slug: "a").icon.favorite == false)
            let results = try f.store.setFavorite([("set-001", "a"), ("set-001", "b")], true)
            #expect(results.allSatisfy { (try? $0.get())?.icon.favorite == true })
            #expect(try f.store.readIcon(set: "set-001", slug: "b").icon.favorite)
            try f.store.setFavorite(set: "set-001", slug: "a", false)
            #expect(try f.store.readIcon(set: "set-001", slug: "a").icon.favorite == false)
            #expect(try f.store.readIcon(set: "set-001", slug: "b").icon.favorite)
        }
    }

    @Test func deleteIconRemovesFolder() throws {
        try withTempDir { dir in
            let f = try Fixture(dir)
            let a = try f.add("a")
            try f.add("b")
            try f.store.deleteIcon(set: "set-001", slug: "a")
            #expect(!FileManager.default.fileExists(atPath: a.folder.path))
            #expect(try f.store.readIcons(in: "set-001").map(\.icon.slug) == ["b"])
            let leftovers = try FileManager.default.contentsOfDirectory(atPath: f.store.setDir("set-001").path)
            #expect(leftovers.sorted() == ["b", "set.json"])
            #expect(throws: StoreError.self) { try f.store.deleteIcon(set: "set-001", slug: "a") }
        }
    }

    @Test func archivedSetFlag() throws {
        try withTempDir { dir in
            let f = try Fixture(dir)
            try f.store.createSet(title: "Second")
            try f.add("a")
            try f.store.setArchived(set: "set-001", slug: "a", true)
            #expect(try f.store.readSet("set-001").archived == false)
            let json = try String(contentsOf: f.store.setURL("set-001"), encoding: .utf8)
            #expect(json.contains(#""archived" : false"#), "the key is always written")

            #expect(try f.store.setSetArchived("set-001", true).archived)
            #expect(try f.store.readSet("set-001").archived)
            // Every set is still read, archived or not, and the icons keep their own flags.
            #expect(try f.store.readSets().map { [$0.id: $0.archived] } == [["set-002": false], ["set-001": true]])
            #expect(try f.store.readIcon(set: "set-001", slug: "a").icon.archived)
            try f.store.setSetArchived("set-001", false)
            #expect(try f.store.readSet("set-001").archived == false)
            #expect(throws: StoreError.self) { try f.store.setSetArchived("set-009", true) }

            // A set.json written before the field existed reads as not archived.
            try f.store.setSetArchived("set-002", true)
            let url = f.store.setURL("set-002")
            let old = try String(contentsOf: url, encoding: .utf8)
                .replacingOccurrences(of: #""archived" : true"#, with: #""unused" : true"#)
            try Data(old.utf8).write(to: url)
            #expect(try f.store.readSet("set-002").archived == false)
        }
    }

    @Test func deleteSetRemovesFolderAndIcons() throws {
        try withTempDir { dir in
            let f = try Fixture(dir)
            try f.store.createSet(title: "Doomed")
            let a = try f.add("a", set: "set-002")
            try f.add("b", set: "set-002")
            try f.add("keep")
            try f.store.setSetArchived("set-002", true)

            try f.store.deleteSet("set-002")
            #expect(!FileManager.default.fileExists(atPath: f.store.setDir("set-002").path))
            #expect(!FileManager.default.fileExists(atPath: a.folder.path))
            #expect(try f.store.readSets().map(\.id) == ["set-001"])
            #expect(try f.store.readIcons(in: "set-001").map(\.icon.slug) == ["keep"])
            let leftovers = try FileManager.default.contentsOfDirectory(atPath: f.store.setsDir.path)
            #expect(leftovers == ["set-001"], "nothing hidden is left behind")
            #expect(throws: StoreError.self) { try f.store.deleteSet("set-002") }
            #expect(throws: StoreError.self) { try f.store.deleteSet("../set-001") }
        }
    }

    @Test func readIconsSkipsCorruptRecordsAndSorts() throws {
        try withTempDir { dir in
            let f = try Fixture(dir)
            let t0 = Date(timeIntervalSince1970: 1_800_000_000)
            try f.add("zeta", created: t0)
            try f.add("alpha", created: t0)
            try f.add("early", created: t0.addingTimeInterval(-60))
            let broken = try f.add("broken", created: t0)
            try Data("{ not json".utf8).write(to: broken.folder.appending(path: "icon.json"))
            // A folder with no record, and hidden temp debris.
            try FileManager.default.createDirectory(
                at: f.store.iconFolder(set: "set-001", slug: "empty"), withIntermediateDirectories: true)
            try Data().write(to: f.store.setDir("set-001").appending(path: ".set.json.tmp"))

            let icons = try f.store.readIcons(in: "set-001")
            #expect(icons.map(\.icon.slug) == ["early", "alpha", "zeta"])
            #expect(icons.allSatisfy { $0.stamp != nil && $0.setID == "set-001" })
            #expect(throws: StoreError.self) { try f.store.readIcon(set: "set-001", slug: "broken") }
            #expect(throws: StoreError.self) { try f.store.readIcons(in: "set-042") }
        }
    }

    @Test func iconRoundTripsThroughDisk() throws {
        try withTempDir { dir in
            let f = try Fixture(dir)
            let added = try f.add("round", refs: [.icon(set: "set-001", icon: "x"), .file("/a b/c.png")])
            #expect(try f.store.readIcon(set: "set-001", slug: "round") == added)
            #expect(try f.store.readIcons(in: "set-001") == [added])
        }
    }

    @Test func exclusiveIsReentrantAndBlocksOtherStores() throws {
        try withTempDir { dir in
            let f = try Fixture(dir)
            let depth = try f.store.exclusive { try f.store.exclusive { 2 } }
            #expect(depth == 2)

            // A second store on the same project is another lock holder, as another process would be.
            let other = ProjectStore(projectRoot: dir, lockTimeout: 0.2)
            try f.store.exclusive {
                #expect(throws: StoreError.self) { try other.exclusive { () } }
            }
            #expect(try other.exclusive { true })
        }
    }

    @Test func writesNeedAProject() throws {
        try withTempDir { dir in
            let store = ProjectStore(projectRoot: dir)
            #expect(throws: StoreError.self) { try store.createSet(title: "x") }
            #expect(throws: StoreError.self) { try store.readSets() }
        }
    }
}

@Suite struct SlugTests {
    @Test func validity() {
        for s in ["a", "counter-cream", "olive-device-two-keys", "x1", "1x", String(repeating: "a", count: 64)] {
            #expect(Slug.isValid(s), "\(s)")
        }
        for s in ["", "-lead", "Upper", "under_score", "sp ace", "dot.ted", "ü", String(repeating: "a", count: 65)] {
            #expect(!Slug.isValid(s), "\(s)")
        }
    }

    @Test func makeFromTitle() {
        #expect(Slug.make(from: "Counter with + × a") == "counter-with-a")
        #expect(Slug.make(from: "  Printer, two keys!  ") == "printer-two-keys")
        #expect(Slug.make(from: "×××") == "")
        #expect(Slug.isValid(Slug.make(from: String(repeating: "word ", count: 30))))
    }
}

@Suite struct PNGHeaderTests {
    @Test(arguments: [
        (TinyPNG.Kind.rgb, false), (.rgba, true), (.paletteWithTRNS, true), (.palette, false), (.grey, false),
    ])
    func alpha(kind: TinyPNG.Kind, alpha: Bool) throws {
        try withTempDir { dir in
            let data = TinyPNG.make(kind, width: 5, height: 4)
            #expect(TinyPNG.decodes(data), "the fixture is a real PNG")
            let url = dir.appending(path: "x.png")
            try data.write(to: url)
            let header = try #require(PNGHeader.read(url))
            #expect(header.width == 5)
            #expect(header.height == 4)
            #expect(header.colorType == kind.colorType)
            #expect(header.hasAlpha == alpha)
        }
    }

    @Test func rejectsNonPNG() throws {
        try withTempDir { dir in
            let text = dir.appending(path: "x.png")
            try Data("not a png at all, just some text here".utf8).write(to: text)
            #expect(PNGHeader.read(text) == nil)
            #expect(PNGHeader.read(dir.appending(path: "missing.png")) == nil)
            let short = dir.appending(path: "short.png")
            try TinyPNG.make(.rgba).prefix(20).write(to: short)
            #expect(PNGHeader.read(short) == nil)
        }
    }
}
