import Foundation

/// The install `rimlight self-install` makes, and the one the app makes when no `rimlight` is
/// installed: the binary and its resource bundle in `<prefix>/share/rimlight/<version>/`, and
/// `<prefix>/bin/rimlight` a symlink to it. The prefix is `~/.local` unless asked otherwise;
/// Claude Code's installer puts `claude` in `~/.local/bin`, so that folder is on PATH for the
/// people who use Rimlight. Homebrew's copy is never touched here.
public enum StandaloneInstall {
    public static var defaultPrefix: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local", directoryHint: .isDirectory)
    }

    /// `<prefix>/bin/rimlight`.
    public static func link(prefix: URL) -> URL {
        prefix.appending(path: "bin", directoryHint: .isDirectory)
            .appending(path: SkillText.commandName, directoryHint: .notDirectory)
    }

    /// `<prefix>/share/rimlight`, which holds one folder per installed version.
    public static func versionsDir(prefix: URL) -> URL {
        prefix.appending(path: "share", directoryHint: .isDirectory)
            .appending(path: SkillText.commandName, directoryHint: .isDirectory)
    }

    /// Copies `binary` and `bundle` into `<prefix>/share/rimlight/<version>/`, then points
    /// `<prefix>/bin/rimlight` at that binary with one atomic rename, so a shell never finds a
    /// half-written install. A plain file at the link's place, a copy made by hand, is replaced,
    /// and a resource bundle beside it goes too. The version it replaced is kept, since a render
    /// it started may still read its files; older ones are removed. Returns the link.
    @discardableResult
    public static func install(binary: URL, bundle: URL, version: RimlightVersion, prefix: URL = defaultPrefix) throws -> URL {
        let fm = FileManager.default
        let versions = versionsDir(prefix: prefix)
        let binDir = prefix.appending(path: "bin", directoryHint: .isDirectory)
        try createDirectory(versions)
        try createDirectory(binDir)

        // Staged under a hidden name, then renamed into place.
        let staging = versions.appending(path: ".\(version).\(UUID().uuidString).tmp", directoryHint: .isDirectory)
        try createDirectory(staging)
        do {
            try fm.copyItem(at: binary, to: staging.appending(path: SkillText.commandName, directoryHint: .notDirectory))
            try fm.copyItem(at: bundle, to: staging.appending(path: bundle.lastPathComponent, directoryHint: .isDirectory))
        } catch {
            try? fm.removeItem(at: staging)
            throw StoreError.io("Cannot copy rimlight into \(staging.path): \(error.localizedDescription)")
        }
        let dest = versions.appending(path: version.description, directoryHint: .isDirectory)
        if fm.fileExists(atPath: dest.path) {
            // Reinstalling the same version: move the old copy aside first, so the rename lands.
            let aside = versions.appending(path: ".\(version).\(UUID().uuidString).old", directoryHint: .isDirectory)
            try move(dest, to: aside)
            try? fm.removeItem(at: aside)
        }
        try move(staging, to: dest)

        let link = link(prefix: prefix)
        let previous = installedVersion(prefix: prefix)
        let target = "../share/\(SkillText.commandName)/\(version)/\(SkillText.commandName)"
        let temp = binDir.appending(path: ".\(SkillText.commandName).\(UUID().uuidString).tmp", directoryHint: .notDirectory)
        do {
            try fm.createSymbolicLink(atPath: temp.path, withDestinationPath: target)
        } catch {
            throw StoreError.io("Cannot create \(temp.path): \(error.localizedDescription)")
        }
        do {
            try move(temp, to: link)
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
        // A hand-made copy kept its bundle beside the binary.
        let strayBundle = binDir.appending(path: CoreResources.bundleName, directoryHint: .isDirectory)
        if fm.fileExists(atPath: strayBundle.path) { try? fm.removeItem(at: strayBundle) }

        let keep: Set<String> = [version.description, previous?.description].compactMap { $0 }.reduce(into: []) { $0.insert($1) }
        for name in (try? fm.contentsOfDirectory(atPath: versions.path)) ?? [] where !keep.contains(name) {
            guard !name.hasPrefix("."), RimlightVersion(name) != nil else { continue }
            try? fm.removeItem(at: versions.appending(path: name, directoryHint: .isDirectory))
        }
        return link
    }

    /// The version `<prefix>/bin/rimlight` points at, when it is a standalone install's link.
    public static func installedVersion(prefix: URL = defaultPrefix) -> RimlightVersion? {
        let link = link(prefix: prefix)
        guard let resolved = CurrentProcess.realPath(link.path), ToolCopy.kind(ofResolved: resolved) == .standalone
        else { return nil }
        return RimlightVersion(URL(filePath: resolved).deletingLastPathComponent().lastPathComponent)
    }

    /// Removes the link and every version folder. Only a standalone install's link is removed;
    /// a plain file or a link elsewhere at that place is left alone. Returns whether it removed
    /// anything. The installed Claude Code skill stays, since another copy may use it.
    @discardableResult
    public static func remove(prefix: URL = defaultPrefix) throws -> Bool {
        let fm = FileManager.default
        let link = link(prefix: prefix)
        var removed = false
        if installedVersion(prefix: prefix) != nil {
            do { try fm.removeItem(at: link) } catch {
                throw StoreError.io("Cannot remove \(link.path): \(error.localizedDescription)")
            }
            removed = true
        }
        let versions = versionsDir(prefix: prefix)
        if fm.fileExists(atPath: versions.path) {
            do { try fm.removeItem(at: versions) } catch {
                throw StoreError.io("Cannot remove \(versions.path): \(error.localizedDescription)")
            }
            removed = true
        }
        return removed
    }

    private static func createDirectory(_ url: URL) throws {
        do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) } catch {
            throw StoreError.io("Cannot create \(url.path): \(error.localizedDescription)")
        }
    }

    /// `rename(2)`: replaces a file or symlink at `to` atomically.
    private static func move(_ from: URL, to: URL) throws {
        guard rename(from.path, to.path) == 0 else {
            throw StoreError.io("Cannot move \(from.path) to \(to.path) (errno \(errno))")
        }
    }
}
