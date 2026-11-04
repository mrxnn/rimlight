import Foundation

/// Reads and writes one project's `.rimlight/` folder.
///
/// ```
/// project.json
/// sets/set-001/set.json
/// sets/set-001/<slug>/icon.png    the render, never processed
/// sets/set-001/<slug>/icon.json   the record, written last
/// .cache/                         app-owned, ignored here
/// .jobs/<id>.json                 one marker per render in progress (RenderJobs.swift)
/// .lock                           flock for read-modify-writes
/// ```
///
/// Every file is written to a hidden temp file and renamed into place, so reads take no
/// lock and never see half a file. Writes hold an in-process recursive lock and an
/// exclusive `flock` on `.lock`, because the app and any number of `rimlight` processes
/// write the same project.
public final class ProjectStore: Sendable {
    public static let folderName = ".rimlight"
    public static let defaultSetTitle = "Untitled set"
    public static let imageName = "icon.png"
    /// The render before the fit, kept beside an `icon.png` fitted to the tile shape: the
    /// model's own image, or its transparency fix when one ran.
    public static let rawImageName = "raw.png"
    /// The model's opaque render, kept beside an `icon.png` made from it by a transparency fix.
    public static let originalImageName = "original.png"
    public static let recordName = "icon.json"

    /// The project folder, the one that contains `.rimlight`.
    public let root: URL
    /// `<project>/.rimlight`.
    public let stateRoot: URL
    /// How long a write waits for another process to release `.lock` before throwing.
    public let lockTimeout: TimeInterval

    private let lock = NSRecursiveLock()
    private let fileLock = FileLockState()

    /// `projectRoot` may also point at the `.rimlight` folder itself. Touches no file.
    public init(projectRoot: URL, lockTimeout: TimeInterval = 5) {
        var dir = projectRoot.standardized
        if dir.lastPathComponent == Self.folderName { dir = dir.deletingLastPathComponent() }
        root = dir
        stateRoot = dir.appending(path: Self.folderName, directoryHint: .isDirectory)
        self.lockTimeout = lockTimeout
    }

    /// The nearest folder at or above `cwd` that contains `.rimlight/`.
    public static func locate(from cwd: URL) -> URL? {
        var path = cwd.standardized.path
        while true {
            if isDirectory((path as NSString).appendingPathComponent(folderName)) {
                return URL(filePath: path, directoryHint: .isDirectory)
            }
            let parent = (path as NSString).deletingLastPathComponent
            if parent == path || parent.isEmpty { return nil }
            path = parent
        }
    }

    /// Whether the folder holds a project, which is whether `.rimlight/project.json` exists.
    public static func exists(at projectRoot: URL) -> Bool {
        let store = ProjectStore(projectRoot: projectRoot)
        return fileExists(store.projectURL.path)
    }

    // MARK: Paths

    public var projectURL: URL { stateRoot.appending(path: "project.json", directoryHint: .notDirectory) }
    public var setsDir: URL { stateRoot.appending(path: "sets", directoryHint: .isDirectory) }
    /// App-owned caches. The store never reads or writes them.
    public var cacheDir: URL { stateRoot.appending(path: ".cache", directoryHint: .isDirectory) }
    /// The advisory lock file shared by every process writing this project.
    public var lockURL: URL { stateRoot.appending(path: ".lock", directoryHint: .notDirectory) }

    public func setDir(_ id: String) -> URL { setsDir.appending(path: id, directoryHint: .isDirectory) }
    public func setURL(_ id: String) -> URL { setDir(id).appending(path: "set.json", directoryHint: .notDirectory) }
    public func iconFolder(set: String, slug: String) -> URL {
        setDir(set).appending(path: slug, directoryHint: .isDirectory)
    }
    public func iconImageURL(set: String, slug: String) -> URL {
        iconFolder(set: set, slug: slug).appending(path: Self.imageName, directoryHint: .notDirectory)
    }
    public func iconRawImageURL(set: String, slug: String) -> URL {
        iconFolder(set: set, slug: slug).appending(path: Self.rawImageName, directoryHint: .notDirectory)
    }
    public func iconOriginalImageURL(set: String, slug: String) -> URL {
        iconFolder(set: set, slug: slug).appending(path: Self.originalImageName, directoryHint: .notDirectory)
    }
    public func iconRecordURL(set: String, slug: String) -> URL {
        iconFolder(set: set, slug: slug).appending(path: Self.recordName, directoryHint: .notDirectory)
    }

    // MARK: Create

    /// Makes `.rimlight/`, `set-001` titled "Untitled set" when there is no set, and
    /// `project.json` last, since its presence is what `exists(at:)` checks. Safe to call
    /// on an existing project, unless a newer rimlight wrote it (`checkSchema`); returns whether
    /// it wrote anything.
    @discardableResult
    public func create() throws -> Bool {
        try makeDirectory(stateRoot)
        return try exclusive {
            try checkSchema()
            var wrote = false
            try makeDirectory(setsDir)
            if try setIDs().isEmpty {
                try createSet(title: Self.defaultSetTitle)
                wrote = true
            }
            if !Self.fileExists(projectURL.path) {
                try writeJSON(Project(created: Self.now()), to: projectURL)
                wrote = true
            }
            return wrote
        }
    }

    // MARK: Reads (no lock)

    /// Throws `StoreError.newerSchema` when project.json's `schema` is above
    /// `Project.currentSchema`.
    public func readProject() throws -> Project {
        try decode(Project.self, at: projectURL, what: "project.json", decoder: StateCoding.decoder())
    }

    /// What opening a project checks: throws `StoreError.newerSchema` when project.json was
    /// written by a newer rimlight, whose fields this build would misread. A missing or
    /// unreadable project.json passes, as it did before the check. One small read.
    public func checkSchema() throws {
        do { _ = try readProject() } catch StoreError.newerSchema(let found) {
            throw StoreError.newerSchema(found)
        } catch {}
    }

    /// Every set, archived ones included, newest first. A folder whose set.json is missing,
    /// unreadable or of a newer schema is skipped.
    public func readSets() throws -> [IconSet] {
        let decoder = StateCoding.decoder()
        return try setIDs().sorted(by: SetID.newestFirst).compactMap { id in
            guard var set = try? decode(IconSet.self, at: setURL(id), what: "set \(id)", decoder: decoder) else {
                return nil
            }
            set.id = id
            return set
        }
    }

    public func readSet(_ id: String) throws -> IconSet {
        try validateSetID(id)
        var set = try decode(IconSet.self, at: setURL(id), what: "Set \(id)", decoder: StateCoding.decoder())
        set.id = id
        return set
    }

    /// The set's icons, oldest first (ties by slug). Per icon: one read and decode of
    /// icon.json and one `stat` of icon.png. Folders whose icon.json is missing, undecodable
    /// or of a newer schema are skipped, which also hides an icon whose render is still landing.
    public func readIcons(in setID: String) throws -> [IconSnapshot] {
        try validateSetID(setID)
        let names: [String]
        do { names = try FileManager.default.contentsOfDirectory(atPath: setDir(setID).path) } catch {
            throw StoreError.notFound("Set \(setID) not found at \(setDir(setID).path)")
        }
        let decoder = StateCoding.decoder()
        var icons: [IconSnapshot] = []
        icons.reserveCapacity(names.count)
        for name in names where Slug.isValid(name) {
            if let snapshot = try? snapshot(set: setID, slug: name, decoder: decoder) { icons.append(snapshot) }
        }
        icons.sort { ($0.icon.created, $0.icon.slug) < ($1.icon.created, $1.icon.slug) }
        return icons
    }

    public func readIcon(set: String, slug: String) throws -> IconSnapshot {
        try validateSetID(set)
        try Slug.validate(slug)
        return try snapshot(set: set, slug: slug, decoder: StateCoding.decoder())
    }

    // MARK: Writes (locked, atomic)

    /// A new empty set with the next `set-NNN` id.
    @discardableResult
    public func createSet(title: String = ProjectStore.defaultSetTitle) throws -> IconSet {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return try exclusive {
            try makeDirectory(setsDir)
            let next = (try setIDs().compactMap(SetID.number).max() ?? 0) + 1
            let set = IconSet(id: SetID.make(next), title: title.isEmpty ? Self.defaultSetTitle : title, created: Self.now())
            try makeDirectory(setDir(set.id))
            try writeJSON(set, to: setURL(set.id))
            return set
        }
    }

    @discardableResult
    public func renameSet(_ id: String, title: String) throws -> IconSet {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw StoreError.invalidArgument("A set needs a title") }
        return try updateSet(id) { $0.title = title }
    }

    /// Records `session` as the set chat's session for `harness` and adds it to the chat's
    /// history. nil forgets the current session; the history keeps it.
    @discardableResult
    public func setChat(set id: String, harness: String, session: String?) throws -> IconSet {
        try updateSet(id) { set in
            set.chat[harness] = session
            if let session { ChatSessions.record(session, in: &set.chatHistory, harness: harness) }
        }
    }

    /// Records `session` as the icon chat's session for `harness` and adds it to the chat's
    /// history. nil forgets the current session; the history keeps it.
    @discardableResult
    public func setIconChat(set: String, slug: String, harness: String, session: String?) throws -> IconSnapshot {
        try updateIcon(set: set, slug: slug) { icon in
            icon.chat[harness] = session
            if let session { ChatSessions.record(session, in: &icon.chatHistory, harness: harness) }
        }
    }

    /// Corrects the stored `image.alpha` of a render whose pixels were judged again.
    @discardableResult
    public func setAlpha(set: String, slug: String, _ alpha: Bool) throws -> IconSnapshot {
        try updateIcon(set: set, slug: slug) { $0.image.alpha = alpha }
    }

    /// Swaps a stored render for one fitted again from `raw.png`: `image` becomes `icon.png`,
    /// `raw` becomes `raw.png`, `original.png` stays, and of the record only `image` changes.
    /// Refused when `icon.png` is no longer the file `stamp` describes, so a render that landed
    /// in the meantime is kept.
    @discardableResult
    public func replaceImage(
        set: String, slug: String, image fromTemp: URL, raw rawTemp: URL, imageInfo: ImageInfo, stamp: FileStamp?
    ) throws -> IconSnapshot {
        try exclusive {
            var snapshot = try readIcon(set: set, slug: slug)
            guard snapshot.stamp == stamp else {
                throw StoreError.invalidArgument("Icon \(set)/\(slug) changed while it was being fitted; it was kept")
            }
            try AtomicFile.move(rawTemp, to: iconRawImageURL(set: set, slug: slug))
            try AtomicFile.move(fromTemp, to: snapshot.imageURL)
            snapshot.icon.image = imageInfo
            try writeJSON(snapshot.icon, to: iconRecordURL(set: set, slug: slug))
            snapshot.stamp = FileStamp.of(snapshot.imageURL)
            return snapshot
        }
    }

    /// Appends fix attempts that left the render as it was (every one came back opaque).
    @discardableResult
    public func addFixAttempts(set: String, slug: String, _ attempts: [FixAttempt]) throws -> IconSnapshot {
        try updateIcon(set: set, slug: slug) { icon in
            guard !attempts.isEmpty else { return }
            icon.fixAttempts = (icon.fixAttempts ?? []) + attempts
        }
    }

    @discardableResult
    public func setArchived(set: String, slug: String, _ archived: Bool) throws -> IconSnapshot {
        try updateIcon(set: set, slug: slug) { $0.archived = archived }
    }

    /// Archives or restores several icons, holding the lock once for all of them. One that
    /// fails leaves the others written. The results follow `icons`' order.
    public func setArchived(_ icons: [(set: String, slug: String)], _ archived: Bool) throws -> [Result<
        IconSnapshot, any Error
    >] {
        try exclusive { icons.map { icon in Result { try setArchived(set: icon.set, slug: icon.slug, archived) } } }
    }

    @discardableResult
    public func setFavorite(set: String, slug: String, _ favorite: Bool) throws -> IconSnapshot {
        try updateIcon(set: set, slug: slug) { $0.favorite = favorite }
    }

    /// Adds or removes several icons from Favorites, holding the lock once for all of them.
    /// One that fails leaves the others written. The results follow `icons`' order.
    public func setFavorite(_ icons: [(set: String, slug: String)], _ favorite: Bool) throws -> [Result<
        IconSnapshot, any Error
    >] {
        try exclusive { icons.map { icon in Result { try setFavorite(set: icon.set, slug: icon.slug, favorite) } } }
    }

    /// Archives or restores a whole set. Its icons' own flags are left as they are.
    @discardableResult
    public func setSetArchived(_ id: String, _ archived: Bool) throws -> IconSet {
        try updateSet(id) { $0.archived = archived }
    }

    /// Removes the set's folder and every icon in it. Moved aside to a hidden name first, as
    /// `deleteIcon` does, so readers see the set or nothing.
    public func deleteSet(_ id: String) throws {
        try validateSetID(id)
        try exclusive {
            let folder = setDir(id)
            guard Self.isDirectory(folder.path) else { throw StoreError.notFound("Set \(id) not found") }
            let trash = setsDir.appending(path: ".\(id).deleted-\(UUID().uuidString)", directoryHint: .isDirectory)
            guard rename(folder.path, trash.path) == 0 else {
                throw StoreError.io("Cannot move \(folder.path) aside (errno \(errno))")
            }
            try? FileManager.default.removeItem(at: trash)
        }
    }

    /// Removes the icon's folder. It is renamed to a hidden name first, so readers see the
    /// icon or nothing, never a folder half gone.
    public func deleteIcon(set: String, slug: String) throws {
        try validateSetID(set)
        try Slug.validate(slug)
        try exclusive {
            let folder = iconFolder(set: set, slug: slug)
            guard Self.isDirectory(folder.path) else {
                throw StoreError.notFound("Icon \(set)/\(slug) not found")
            }
            let trash = setDir(set).appending(path: ".\(slug).deleted-\(UUID().uuidString)", directoryHint: .isDirectory)
            guard rename(folder.path, trash.path) == 0 else {
                throw StoreError.io("Cannot move \(folder.path) aside (errno \(errno))")
            }
            try? FileManager.default.removeItem(at: trash)
        }
    }

    /// Removes several icons' folders, holding the lock once for all of them. One that fails
    /// leaves the others removed. The results follow `icons`' order.
    public func deleteIcons(_ icons: [(set: String, slug: String)]) throws -> [Result<Void, any Error>] {
        try exclusive { icons.map { icon in Result { try deleteIcon(set: icon.set, slug: icon.slug) } } }
    }

    /// Copies the icon into a new folder of its set, render, `raw.png`, `original.png` and every build direction included, so the
    /// two can be refined and built apart. The copy is `<slug>-copy` titled `<title> copy`, then `-copy-2` and
    /// `copy 2`, the first that is free. A copy of a copy drops its own suffix first, so it reads as the next copy. It keeps the
    /// record's concept and lineage but starts with no chat, unarchived, created `now`. The folder is copied under a
    /// hidden name (a clone on APFS, so a build's drawings take no new space) and renamed into place with its new
    /// record, so a reader sees the copy whole or not at all. A build of the icon that is running holds its
    /// direction's `.lock` and refuses the copy; one that starts meanwhile waits for it.
    @discardableResult
    public func duplicateIcon(set: String, slug: String, now: Date = .now) throws -> IconSnapshot {
        try validateSetID(set)
        try Slug.validate(slug)
        return try exclusive {
            let original = try readIcon(set: set, slug: slug)
            var locks: [Int32] = []
            defer { for fd in locks { close(fd) } }
            for direction in buildDirections(set: set, slug: slug) {
                let fd = open(direction.folder.appending(path: ".lock", directoryHint: .notDirectory).path, O_RDWR | O_CLOEXEC)
                guard fd >= 0 else { continue }
                locks.append(fd)
                if flock(fd, LOCK_SH | LOCK_NB) != 0 {
                    throw StoreError.invalidArgument("The \(direction.name) build of \(set)/\(slug) is running")
                }
            }
            let (copySlug, copyTitle) = freeCopyName(set: set, slug: slug, title: original.icon.title)
            var icon = original.icon
            icon.slug = copySlug
            icon.title = copyTitle
            icon.created = StateCoding.wholeSeconds(now)
            icon.archived = false
            icon.chat = [:]
            icon.chatHistory = [:]
            let staged = setDir(set).appending(path: ".\(copySlug).copy-\(UUID().uuidString)", directoryHint: .isDirectory)
            do {
                try FileManager.default.copyItem(at: original.folder, to: staged)
                try writeJSON(icon, to: staged.appending(path: Self.recordName, directoryHint: .notDirectory))
                let folder = iconFolder(set: set, slug: copySlug)
                guard rename(staged.path, folder.path) == 0 else {
                    throw StoreError.io("Cannot move the copy to \(folder.path) (errno \(errno))")
                }
            } catch {
                try? FileManager.default.removeItem(at: staged)
                throw error
            }
            return try readIcon(set: set, slug: copySlug)
        }
    }

    /// Duplicates several icons, holding the lock once for all of them. One that fails leaves the other copies
    /// made. The results follow `icons`' order.
    public func duplicateIcons(_ icons: [(set: String, slug: String)], now: Date = .now) throws -> [Result<
        IconSnapshot, any Error
    >] {
        try exclusive { icons.map { icon in Result { try duplicateIcon(set: icon.set, slug: icon.slug, now: now) } } }
    }

    /// The first `<base>-copy[-n]` with no folder in the set, and its title. `base` is `slug` without a `-copy` or
    /// `-copy-<n>` of its own, cut so the longest suffix still fits a slug.
    private func freeCopyName(set: String, slug: String, title: String) -> (slug: String, title: String) {
        func strip(_ text: String, _ marker: String) -> String {
            guard let range = text.range(of: marker, options: .backwards) else { return text }
            let tail = text[range.upperBound...]
            guard tail.isEmpty || (tail.first == marker.first && tail.dropFirst().allSatisfy(\.isNumber) && tail.count > 1)
            else { return text }
            let base = String(text[..<range.lowerBound])
            return base.isEmpty ? text : base
        }
        var base = strip(slug, "-copy")
        let room = Slug.maxLength - "-copy-9999".count
        if base.count > room { base = String(base.prefix(room)) }
        while base.hasSuffix("-") { base.removeLast() }
        let titleBase = strip(title, " copy")
        var n = 1
        while true {
            let candidate = n == 1 ? "\(base)-copy" : "\(base)-copy-\(n)"
            if !Self.fileExists(iconFolder(set: set, slug: candidate).path) {
                return (candidate, n == 1 ? "\(titleBase) copy" : "\(titleBase) copy \(n)")
            }
            n += 1
        }
    }

    /// Stores a render as `sets/<set>/<slug>/`: moves `fromTemp` into `icon.png` first and
    /// writes `icon.json` last, because the record is the commit marker readers wait for.
    /// `mode` is `refine` when `parent` is set.
    ///
    /// An existing icon is refused unless `replace`. A replacement keeps the icon's
    /// `created`, `archived`, `favorite` and `chat`, and its lineage: a nil `parent`, or one naming the
    /// icon itself, keeps the old parent, and refs to the icon itself are dropped (the old
    /// refs stay when none are left). A replacement that refs the icon itself is a fix of
    /// its own file (a transparency fix): it keeps the concept's `prompt` and appends the new
    /// one to `fixes`. Any other replacement is a redo and takes the new prompt. `fixes` are
    /// the prompts of edits already made to `fromTemp` before it got here (the automatic
    /// transparency fix), appended last. `fixAttempts` follow the same rule: a fix of its own
    /// file keeps the old ones, a redo starts over, and the new ones are appended last.
    /// `raw` is the image before the fit when `fromTemp` was fitted to the tile shape; it
    /// becomes `raw.png`. `original` is the model's opaque render when a transparency fix made
    /// the image from it; it becomes `original.png`. A replacement without either drops the
    /// old file. A record of a newer schema is never replaced.
    @discardableResult
    public func addIcon(
        set: String,
        slug: String,
        title: String,
        prompt: String,
        parent: IconParent? = nil,
        refs: [IconRef] = [],
        generator: GeneratorInfo? = nil,
        by: String,
        image fromTemp: URL,
        raw rawTemp: URL? = nil,
        original originalTemp: URL? = nil,
        imageInfo: ImageInfo,
        fixes newFixes: [String] = [],
        fixAttempts newAttempts: [FixAttempt] = [],
        replace: Bool = false,
        created: Date = .now
    ) throws -> IconSnapshot {
        try validateSetID(set)
        try Slug.validate(slug)
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw StoreError.invalidArgument("An icon needs a title") }
        guard Self.fileExists(fromTemp.path) else { throw StoreError.notFound("Image not found: \(fromTemp.path)") }
        for temp in [rawTemp, originalTemp].compactMap(\.self) where !Self.fileExists(temp.path) {
            throw StoreError.notFound("Image not found: \(temp.path)")
        }

        return try exclusive {
            guard Self.fileExists(setURL(set).path) else { throw StoreError.notFound("Set \(set) does not exist") }
            let isSelf = { (s: String?, i: String?) in s == set && i == slug }
            if let parent, !isSelf(parent.set, parent.icon) {
                guard Self.fileExists(iconRecordURL(set: parent.set, slug: parent.icon).path) else {
                    throw StoreError.notFound("Parent icon \(parent.path) does not exist")
                }
            }

            let folder = iconFolder(set: set, slug: slug)
            let recordURL = iconRecordURL(set: set, slug: slug)
            var previous: Icon?
            if Self.isRegularFile(recordURL.path) {
                guard replace else {
                    throw StoreError.alreadyExists("Icon \(set)/\(slug) already exists; pick a new slug or replace it")
                }
                do {
                    previous = try decode(Icon.self, at: recordURL, what: "Icon \(set)/\(slug)", decoder: StateCoding.decoder())
                } catch StoreError.newerSchema(let found) {
                    // Replacing it would drop the fields this build cannot read.
                    throw StoreError.newerSchema(found)
                } catch {}
            }

            var parent = parent
            var refs = refs
            var prompt = prompt
            var fixes: [String]?
            var attempts: [FixAttempt]?
            if let previous {
                if parent == nil || isSelf(parent?.set, parent?.icon) { parent = previous.parent }
                if refs.contains(where: { isSelf($0.set, $0.icon) }) {
                    fixes = (previous.fixes ?? []) + [prompt]
                    attempts = previous.fixAttempts
                    prompt = previous.prompt
                }
                refs.removeAll { isSelf($0.set, $0.icon) }
                if refs.isEmpty { refs = previous.refs }
            } else if isSelf(parent?.set, parent?.icon) {
                throw StoreError.invalidArgument("Icon \(set)/\(slug) cannot be its own parent")
            }
            if !newFixes.isEmpty { fixes = (fixes ?? []) + newFixes }
            if !newAttempts.isEmpty { attempts = (attempts ?? []) + newAttempts }

            let icon = Icon(
                slug: slug, title: title, created: previous?.created ?? StateCoding.wholeSeconds(created), by: by,
                prompt: prompt, parent: parent, refs: refs, generator: generator, image: imageInfo,
                archived: previous?.archived ?? false, favorite: previous?.favorite ?? false, chat: previous?.chat ?? [:], chatHistory: previous?.chatHistory ?? [:], fixes: fixes,
                fixAttempts: attempts)

            try makeDirectory(folder)
            for (temp, name) in [(originalTemp, Self.originalImageName), (rawTemp, Self.rawImageName)] {
                let url = folder.appending(path: name, directoryHint: .notDirectory)
                if let temp {
                    try AtomicFile.move(temp, to: url)
                } else if Self.fileExists(url.path) {
                    do { try FileManager.default.removeItem(at: url) } catch {
                        throw StoreError.io("Cannot remove \(url.path): \(error.localizedDescription)")
                    }
                }
            }
            let imageURL = folder.appending(path: Self.imageName, directoryHint: .notDirectory)
            try AtomicFile.move(fromTemp, to: imageURL)
            try writeJSON(icon, to: recordURL)
            return IconSnapshot(icon: icon, setID: set, folder: folder, imageURL: imageURL, stamp: FileStamp.of(imageURL))
        }
    }

    // MARK: Lock

    /// Runs `body` holding the in-process lock and an exclusive `flock` on `.rimlight/.lock`.
    /// Reentrant: a nested call on the same store reuses the lock it already holds.
    @discardableResult
    public func exclusive<T>(_ body: () throws -> T) throws -> T {
        try lock.withLock {
            if fileLock.depth == 0 { fileLock.fd = try acquireFileLock() }
            fileLock.depth += 1
            defer {
                fileLock.depth -= 1
                if fileLock.depth == 0 {
                    flock(fileLock.fd, LOCK_UN)
                    close(fileLock.fd)
                    fileLock.fd = -1
                }
            }
            return try body()
        }
    }

    /// Polls with backoff (1 to 20 ms) and throws after `lockTimeout`. flock has no timed
    /// wait, hence LOCK_NB in a loop.
    private func acquireFileLock() throws -> Int32 {
        let path = lockURL.path
        let fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else {
            let err = errno
            if err == ENOENT { throw StoreError.notFound("No project at \(root.path): run `rimlight init` first") }
            throw StoreError.io("Cannot open \(path) (errno \(err))")
        }
        let deadline = Date.now.addingTimeInterval(lockTimeout)
        var pause: useconds_t = 1_000
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            let err = errno
            if err == EINTR { continue }
            guard err == EWOULDBLOCK else {
                close(fd)
                throw StoreError.io("flock on \(path) failed (errno \(err))")
            }
            guard Date.now < deadline else {
                close(fd)
                throw StoreError.lockTimeout(
                    "Another process held \(path) for over \(String(format: "%g", lockTimeout)) s. Try again.")
            }
            usleep(pause)
            pause = min(pause * 2, 20_000)
        }
        return fd
    }

    // MARK: Private

    private func updateSet(_ id: String, _ change: (inout IconSet) -> Void) throws -> IconSet {
        try validateSetID(id)
        return try exclusive {
            var set = try readSet(id)
            change(&set)
            try writeJSON(set, to: setURL(id))
            return set
        }
    }

    private func updateIcon(set: String, slug: String, _ change: (inout Icon) -> Void) throws -> IconSnapshot {
        try exclusive {
            var snapshot = try readIcon(set: set, slug: slug)
            change(&snapshot.icon)
            try writeJSON(snapshot.icon, to: iconRecordURL(set: set, slug: slug))
            return snapshot
        }
    }

    /// The `set-NNN` folders under `sets/`, in no order.
    private func setIDs() throws -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: setsDir.path) else {
            if Self.isDirectory(stateRoot.path) { return [] }
            throw StoreError.notFound("No project at \(root.path): run `rimlight init` first")
        }
        return names.filter(SetID.isValid)
    }

    private func snapshot(set: String, slug: String, decoder: JSONDecoder) throws -> IconSnapshot {
        let folder = iconFolder(set: set, slug: slug)
        let recordURL = folder.appending(path: Self.recordName, directoryHint: .notDirectory)
        var icon = try decode(Icon.self, at: recordURL, what: "Icon \(set)/\(slug)", decoder: decoder)
        icon.slug = slug
        let imageURL = folder.appending(path: Self.imageName, directoryHint: .notDirectory)
        return IconSnapshot(icon: icon, setID: set, folder: folder, imageURL: imageURL, stamp: FileStamp.of(imageURL))
    }

    func validateSetID(_ id: String) throws {
        guard SetID.isValid(id) else {
            throw StoreError.invalidID("\"\(id)\" is not a set id (set-001, set-002, …)")
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, at url: URL, what: String, decoder: JSONDecoder) throws -> T {
        let data: Data
        do { data = try Data(contentsOf: url) } catch {
            if !Self.fileExists(url.path) { throw StoreError.notFound("\(what) not found at \(url.path)") }
            throw StoreError.io("Cannot read \(url.path): \(error.localizedDescription)")
        }
        do { return try decoder.decode(T.self, from: data) } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.io("Cannot decode \(url.path): \(error)")
        }
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try AtomicFile.write(try StateCoding.encode(value), to: url)
    }

    private func makeDirectory(_ url: URL) throws {
        do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) } catch {
            throw StoreError.io("Cannot create \(url.path): \(error.localizedDescription)")
        }
    }

    private static func now() -> Date { StateCoding.wholeSeconds(.now) }

    static func fileExists(_ path: String) -> Bool { access(path, F_OK) == 0 }

    public static func isDirectory(_ path: String) -> Bool {
        var st = stat()
        return stat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
    }

    public static func isRegularFile(_ path: String) -> Bool {
        var st = stat()
        return stat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFREG
    }
}

/// Nesting depth and descriptor of a store's `flock`. Touched only while the store's
/// recursive lock is held, which is what makes the unchecked Sendable sound.
private final class FileLockState: @unchecked Sendable {
    var depth = 0
    var fd: Int32 = -1
}
