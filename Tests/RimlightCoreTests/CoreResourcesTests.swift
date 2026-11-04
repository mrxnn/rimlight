import Foundation
import Testing

@testable import RimlightCore

/// A Homebrew-style prefix: `bin/rimlight` links to `../libexec/rimlight`, and the bundle may
/// sit beside the real binary or in `share/rimlight`.
@Test func resourceFoldersFollowTheExecutableSymlink() throws {
    try withTempDir { prefix in
        let fm = FileManager.default
        let dirs = ["bin", "libexec", "share/rimlight"].map { prefix.appending(path: $0, directoryHint: .isDirectory) }
        for dir in dirs { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        try Data().write(to: dirs[1].appending(path: "rimlight"))
        let link = dirs[0].appending(path: "rimlight")
        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: "../libexec/rimlight")

        let canonical = { (url: URL) in url.resolvingSymlinksInPath().path }
        let folders = CoreResources.folders(executable: link).map(canonical)
        let (bin, libexec, share) = (canonical(dirs[0]), canonical(dirs[1]), canonical(dirs[2]))
        #expect(!folders.contains(bin))
        let exeIndex = try #require(folders.firstIndex(of: libexec))
        #expect(folders.last == share)
        #expect(exeIndex < folders.count - 1)
    }
}
