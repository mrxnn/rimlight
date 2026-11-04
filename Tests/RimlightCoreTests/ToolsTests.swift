import Foundation
import Testing

@testable import RimlightCore

@Suite struct ToolsTests {
    // MARK: Versions

    @Test func versionsParseAndCompare() throws {
        #expect(RimlightVersion("0.2.0") == RimlightVersion(major: 0, minor: 2, patch: 0))
        #expect(RimlightVersion("1") == RimlightVersion("1.0.0"))
        #expect(RimlightVersion("0.2.0-beta.1") == RimlightVersion("0.2.0"))
        #expect(try #require(RimlightVersion("0.1.9")) < #require(RimlightVersion("0.2.0")))
        #expect(try #require(RimlightVersion("0.10.0")) > #require(RimlightVersion("0.9.9")))
        for bad in ["", "abc", "1.2.3.4", "1..2", "-1.0.0", "v1.0"] { #expect(RimlightVersion(bad) == nil) }
        #expect(RimlightVersion.current.description == Rimlight.version)
    }

    // MARK: Copies on PATH

    @Test func kindComesFromTheResolvedPath() {
        #expect(ToolCopy.kind(ofResolved: "/opt/homebrew/Cellar/rimlight/0.2.0/libexec/rimlight") == .homebrew)
        #expect(ToolCopy.kind(ofResolved: "/usr/local/Cellar/rimlight/0.2.0/bin/rimlight") == .homebrew)
        #expect(ToolCopy.kind(ofResolved: "/Users/a/.local/share/rimlight/0.2.0/rimlight") == .standalone)
        #expect(ToolCopy.kind(ofResolved: "/Users/a/.local/bin/rimlight") == .other)
        #expect(ToolCopy.kind(ofResolved: "/Users/a/.local/share/rimlight/latest/rimlight") == .other)
        #expect(ToolCopy.kind(ofResolved: "/Applications/Rimlight.app/Contents/MacOS/rimlight") == .other)
    }

    /// PATH order, absolute entries only, executable files only, and one entry per real file.
    @Test func lookupAllListsEachRealFileOnceInPathOrder() throws {
        try withTempDir { dir in
            let fm = FileManager.default
            let (a, b, c, d) = (folder(dir, "a"), folder(dir, "b"), folder(dir, "c"), folder(dir, "d"))
            try executableFile(a.appending(path: "rimlight"))
            try fm.createSymbolicLink(at: b.appending(path: "rimlight"), withDestinationURL: a.appending(path: "rimlight"))
            try executableFile(c.appending(path: "rimlight"))
            fm.createFile(atPath: d.appending(path: "rimlight").path, contents: Data("x".utf8))  // not executable
            let path = [d.path, a.path, b.path, "relative", c.path, a.path].joined(separator: ":")
            let found = CurrentProcess.lookupAll("rimlight", searchPath: path)
            #expect(found.map(\.path) == [a.appending(path: "rimlight").path, c.appending(path: "rimlight").path])
            #expect(found.first?.resolved == CurrentProcess.lookup("rimlight", searchPath: path)?.path)
            #expect(CurrentProcess.lookupAll("rimlight", searchPath: nil).isEmpty)
        }
    }

    // MARK: Standalone install

    @Test func standaloneInstallLinksTheVersionAndKeepsThePreviousOne() throws {
        try withTempDir { dir in
            let fm = FileManager.default
            let (binary, bundle) = try fakeBuild(dir)
            let prefix = dir.appending(path: "prefix", directoryHint: .isDirectory)
            let versions = StandaloneInstall.versionsDir(prefix: prefix)
            func installed() -> [String] {
                ((try? fm.contentsOfDirectory(atPath: versions.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
            }

            let link = try StandaloneInstall.install(binary: binary, bundle: bundle, version: v("0.1.0"), prefix: prefix)
            #expect(link == StandaloneInstall.link(prefix: prefix))
            #expect(try fm.destinationOfSymbolicLink(atPath: link.path) == "../share/rimlight/0.1.0/rimlight")
            #expect(StandaloneInstall.installedVersion(prefix: prefix) == v("0.1.0"))
            #expect(fm.isExecutableFile(atPath: link.path))
            #expect(fm.fileExists(atPath: versions.appending(path: "0.1.0/\(CoreResources.bundleName)/Info.plist").path))
            #expect(CurrentProcess.realPath(link.path).map { ToolCopy.kind(ofResolved: $0) } == .standalone)

            try StandaloneInstall.install(binary: binary, bundle: bundle, version: v("0.2.0"), prefix: prefix)
            #expect(StandaloneInstall.installedVersion(prefix: prefix) == v("0.2.0"))
            #expect(installed() == ["0.1.0", "0.2.0"])

            try StandaloneInstall.install(binary: binary, bundle: bundle, version: v("0.3.0"), prefix: prefix)
            #expect(installed() == ["0.2.0", "0.3.0"])

            // The same version again replaces it in place.
            try StandaloneInstall.install(binary: binary, bundle: bundle, version: v("0.3.0"), prefix: prefix)
            #expect(StandaloneInstall.installedVersion(prefix: prefix) == v("0.3.0"))
            #expect(installed().contains("0.3.0"))

            #expect(try StandaloneInstall.remove(prefix: prefix))
            #expect(!fm.fileExists(atPath: link.path))
            #expect(!fm.fileExists(atPath: versions.path))
            #expect(try !StandaloneInstall.remove(prefix: prefix))
        }
    }

    /// The README's old way was copying the binary and its bundle into ~/.local/bin by hand.
    @Test func standaloneInstallReplacesAHandMadeCopy() throws {
        try withTempDir { dir in
            let fm = FileManager.default
            let (binary, bundle) = try fakeBuild(dir)
            let prefix = dir.appending(path: "prefix", directoryHint: .isDirectory)
            let bin = folder(prefix, "bin")
            try executableFile(bin.appending(path: "rimlight"))
            try fm.copyItem(at: bundle, to: bin.appending(path: CoreResources.bundleName))

            // A plain file is not a standalone install, so remove leaves it.
            #expect(StandaloneInstall.installedVersion(prefix: prefix) == nil)
            #expect(try !StandaloneInstall.remove(prefix: prefix))
            #expect(fm.fileExists(atPath: bin.appending(path: "rimlight").path))

            try StandaloneInstall.install(binary: binary, bundle: bundle, version: v("0.2.0"), prefix: prefix)
            #expect(StandaloneInstall.installedVersion(prefix: prefix) == v("0.2.0"))
            #expect(!fm.fileExists(atPath: bin.appending(path: CoreResources.bundleName).path))
        }
    }

    // MARK: Install record

    @Test func installRecordsVersionPickAndCommand() throws {
        try withTempDir { dir in
            let skills = dir.appending(path: "skills", directoryHint: .isDirectory)
            #expect(SkillText.record(in: skills) == nil)
            #expect(SkillText.defaultPick(in: skills) == .adaptive)

            try SkillText.install(cliPath: "rimlight", to: skills, skill: .style(.monoMark))
            let record = try #require(SkillText.record(in: skills))
            #expect(record.version == Rimlight.version)
            #expect(record.style == "mono-mark")
            #expect(record.command == "rimlight")
            #expect(SkillText.defaultPick(in: skills) == .style(.monoMark))

            // Nothing changed, so the record keeps its date.
            try SkillText.install(cliPath: "rimlight", to: skills, skill: .style(.monoMark))
            #expect(SkillText.record(in: skills)?.installed == record.installed)

            try SkillText.install(cliPath: "/opt/x/rimlight", to: skills, skill: .none)
            #expect(SkillText.record(in: skills)?.style == "none")
            #expect(SkillText.record(in: skills)?.command == "/opt/x/rimlight")
            #expect(SkillText.defaultPick(in: skills) == .none)
        }
    }

    @Test func recordNamesRoundTrip() {
        for skill in DesignSkill.builtIn {
            let name = SkillRecord.styleName(of: skill)
            let record = SkillRecord(version: "0.2.0", style: name, command: "rimlight", installed: Date())
            #expect(record.skill == skill)
        }
        let file = DesignSkill(path: "/tmp/mine.md")
        #expect(SkillRecord(version: "0.2.0", style: SkillRecord.styleName(of: file), command: "rimlight", installed: Date()).skill == file)
        #expect(SkillRecord(version: "0.2.0", style: "no-such-style", command: "rimlight", installed: Date()).skill == nil)
    }

    /// An older rimlight's skill is rewritten, keeping its pick, by the copy PATH runs only.
    @Test func refreshRewritesAnOlderSkillFromThePathCopyOnly() throws {
        try withTempDir { dir in
            let fm = FileManager.default
            let skills = dir.appending(path: "skills", directoryHint: .isDirectory)
            let real = folder(dir, "real")
            let exe = real.appending(path: "rimlight")
            try executableFile(exe)
            let bin = folder(dir, "bin")
            try fm.createSymbolicLink(at: bin.appending(path: "rimlight"), withDestinationURL: exe)

            // No record: nothing to do.
            #expect(try !SkillText.refreshIfOlder(executable: exe, searchPath: bin.path, skillsDir: skills))

            try SkillText.install(cliPath: "rimlight", to: skills, skill: .none)
            #expect(try !SkillText.refreshIfOlder(executable: exe, searchPath: bin.path, skillsDir: skills))

            // Pretend 0.0.1 wrote it, with a stale text.
            var record = try #require(SkillText.record(in: skills))
            record.version = "0.0.1"
            try SkillText.writeRecord(record, in: skills)
            try Data("old text\n".utf8).write(to: SkillText.installedURL(in: skills))
            // As from a version before build.md shipped.
            try fm.removeItem(at: SkillText.installedBuildURL(in: skills))

            // A copy that PATH does not run leaves it alone.
            #expect(try !SkillText.refreshIfOlder(executable: exe, searchPath: "", skillsDir: skills))
            #expect(SkillText.record(in: skills)?.version == "0.0.1")

            #expect(try SkillText.refreshIfOlder(executable: exe, searchPath: bin.path, skillsDir: skills))
            #expect(SkillText.record(in: skills)?.version == Rimlight.version)
            #expect(SkillText.record(in: skills)?.style == "none")
            let text = try String(contentsOf: SkillText.installedURL(in: skills), encoding: .utf8)
            #expect(text.hasPrefix("---\nname: rimlight"))
            #expect(!text.contains("## Designing icons"))
            #expect(fm.fileExists(atPath: SkillText.installedBuildURL(in: skills).path))
            #expect(try !SkillText.refreshIfOlder(executable: exe, searchPath: bin.path, skillsDir: skills))
        }
    }

    // MARK: Helpers

    private func v(_ text: String) -> RimlightVersion { RimlightVersion(text)! }

    private func folder(_ parent: URL, _ name: String) -> URL {
        let url = parent.appending(path: name, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func executableFile(_ url: URL) throws {
        try Data("#!/bin/sh\necho rimlight 0.0.0\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// A stand-in binary and resource bundle, as a build leaves them side by side.
    private func fakeBuild(_ dir: URL) throws -> (binary: URL, bundle: URL) {
        let build = folder(dir, "build")
        let binary = build.appending(path: "rimlight")
        try executableFile(binary)
        let bundle = folder(build, CoreResources.bundleName)
        try Data("<plist/>".utf8).write(to: bundle.appending(path: "Info.plist"))
        return (binary, bundle)
    }
}
