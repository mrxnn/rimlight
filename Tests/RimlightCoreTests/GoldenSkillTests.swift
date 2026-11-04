import Foundation
import Testing

@testable import RimlightCore

/// The creative text is frozen through the open-core split. The default skill, build.md and the
/// style files must match the committed `skills/rimlight/` byte for byte. A deliberate change to
/// that text updates the golden in the same commit: `RIMLIGHT_UPDATE_GOLDEN=1 swift test --filter
/// GoldenSkillTests` rewrites it from the bundled text.
@Suite struct GoldenSkillTests {
    @Test func skillMatchesTheGolden() throws {
        // The default skill with `rimlight` as the command and the styles folder and build.md
        // beside the file, since an agent loads a skill with its base directory.
        let text = try SkillText.rendered(cliPath: "rimlight", stylesPath: "styles", buildPath: "build.md")
        let golden = try Self.skillGolden("SKILL.md")
        try Self.expectGolden(Data(text.utf8), "SKILL.md", golden, at: "skills/rimlight/SKILL.md")
    }

    @Test func buildMatchesTheGolden() throws {
        let text = try SkillText.renderedBuild(cliPath: "rimlight", stylesPath: "styles", buildPath: "build.md")
        let golden = try Self.skillGolden("build.md")
        try Self.expectGolden(Data(text.utf8), "build.md", golden, at: "skills/rimlight/build.md")
    }

    @Test func stylesMatchTheGolden() throws {
        let bundled = try SkillText.stylesDirectory()
        let golden = try Self.skillGolden("styles")
        let names = try Self.fileNames(in: bundled)
        let goldenNames = try Self.fileNames(in: golden)
        #expect(names == goldenNames, "Styles/ and skills/rimlight/styles/ hold different files; update the golden")
        for name in names.intersection(goldenNames).sorted() {
            let data = try Data(contentsOf: bundled.appending(path: name, directoryHint: .notDirectory))
            let file = golden.appending(path: name, directoryHint: .notDirectory)
            try Self.expectGolden(data, "styles/" + name, file, at: "skills/rimlight/styles/" + name)
        }
    }

    // MARK: Helpers

    /// `path` inside the committed `skills/rimlight/`, which `npx skills add` and a plain clone
    /// read, so it is the golden itself rather than a copy in the test bundle.
    private static func skillGolden(_ path: String) throws -> URL {
        try packageRoot().appending(path: "skills/rimlight").appending(path: path)
    }

    /// The folder holding Package.swift, found by walking up from this file.
    private static func packageRoot() throws -> URL {
        let file = URL(filePath: #filePath, directoryHint: .notDirectory)
        let root = sequence(first: file.deletingLastPathComponent()) {
            $0.path == "/" ? nil : $0.deletingLastPathComponent()
        }.first { FileManager.default.fileExists(atPath: $0.appending(path: "Package.swift").path) }
        return try #require(root, "No Package.swift above \(file.path)")
    }

    /// The names of the files in `dir`, hidden ones left out.
    private static func fileNames(in dir: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { !$0.hasPrefix(".") })
    }

    /// Expects `actual`, the text of `name`, to equal the golden file at `url`, byte for byte, and
    /// on a mismatch records where they first differ. `goldenPath` is the golden's path in the
    /// package. With `RIMLIGHT_UPDATE_GOLDEN` set, it writes `actual` to `url` instead.
    private static func expectGolden(
        _ actual: Data, _ name: String, _ url: URL, at goldenPath: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        if ProcessInfo.processInfo.environment["RIMLIGHT_UPDATE_GOLDEN"] != nil {
            try actual.write(to: url, options: .atomic)
            return
        }
        let golden = try Data(contentsOf: url)
        guard actual != golden else { return }
        let diff = lineDiff(golden: String(decoding: golden, as: UTF8.self), actual: String(decoding: actual, as: UTF8.self))
        Issue.record(
            "\(name) differs from \(goldenPath). If the change is deliberate, update the golden in the same commit.\n\(diff)",
            sourceLocation: sourceLocation)
    }

    /// The one changed stretch of lines between `golden` and `actual`, with three lines of
    /// context: `-` for the golden, `+` for the actual text.
    private static func lineDiff(golden: String, actual: String) -> String {
        let old = golden.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let new = actual.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        var start = 0
        while start < old.count, start < new.count, old[start] == new[start] { start += 1 }
        guard start < old.count || start < new.count else {
            return "The lines read the same; the bytes differ (line endings or Unicode normalization)."
        }
        var (oldEnd, newEnd) = (old.count, new.count)
        while oldEnd > start, newEnd > start, old[oldEnd - 1] == new[newEnd - 1] {
            oldEnd -= 1
            newEnd -= 1
        }
        let context = 3
        let limit = 20
        var lines = ["First difference at line \(start + 1) (- golden, + actual):"]
        lines += old[max(0, start - context)..<start].map { "  " + $0 }
        lines += old[start..<oldEnd].prefix(limit).map { "- " + $0 }
        if oldEnd - start > limit { lines.append("- … \(oldEnd - start - limit) more") }
        lines += new[start..<newEnd].prefix(limit).map { "+ " + $0 }
        if newEnd - start > limit { lines.append("+ … \(newEnd - start - limit) more") }
        lines += old[oldEnd..<min(old.count, oldEnd + context)].map { "  " + $0 }
        return lines.joined(separator: "\n")
    }
}
