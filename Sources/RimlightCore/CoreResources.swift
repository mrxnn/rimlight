import Foundation

/// The files in RimlightCore's `Resources/`, shipped as `RimlightCore_RimlightCore.bundle`.
public enum CoreResources {
    public static let bundleName = "RimlightCore_RimlightCore.bundle"

    /// A bundled file, or a folder when `ext` is nil. Found by hand because `Bundle.module` traps
    /// when the bundle is missing.
    public static func url(_ name: String, withExtension ext: String?) -> URL? {
        folders(executable: CurrentProcess.executableURL).lazy
            .compactMap { Bundle(url: $0.appending(path: bundleName, directoryHint: .isDirectory)) }
            .compactMap { $0.url(forResource: name, withExtension: ext) }
            .first
    }

    /// The resource bundle this process found, the folder `rimlight self-install` copies.
    public static func bundleURL() -> URL? {
        folders(executable: CurrentProcess.executableURL).lazy
            .map { $0.appending(path: bundleName, directoryHint: .isDirectory) }
            .first { Bundle(url: $0) != nil }
    }

    /// Where the bundle is looked for, in order: the app's Contents/Resources, the Resources
    /// folder beside Contents/MacOS (the CLI inside the app), next to the executable (Xcode's
    /// Products and `swift build`), next to the code's own image (`swift test`, the .xctest
    /// beside it), then `<exe>/../share/rimlight` (a Homebrew-style prefix). The executable's
    /// symlinks are resolved first, so `bin/rimlight -> ../libexec/rimlight` looks in libexec.
    static func folders(executable: URL?) -> [URL] {
        let exeDir = executable?.resolvingSymlinksInPath().deletingLastPathComponent()
        let folders: [URL?] = [
            Bundle.main.resourceURL,
            exeDir?.deletingLastPathComponent().appending(path: "Resources", directoryHint: .isDirectory),
            exeDir,
            Bundle(for: BundleToken.self).bundleURL.deletingLastPathComponent(),
            Bundle.main.bundleURL,
            exeDir?.deletingLastPathComponent().appending(path: "share/rimlight", directoryHint: .isDirectory),
        ]
        return folders.compactMap { $0 }
    }

    private final class BundleToken {}
}
