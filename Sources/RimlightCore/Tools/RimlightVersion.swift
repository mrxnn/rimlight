import Foundation

/// A `rimlight` version, `major.minor.patch`, compared field by field. Missing fields read as
/// zero, so "0.2" equals "0.2.0"; anything after a `-` or `+` is ignored.
public struct RimlightVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public var major: Int
    public var minor: Int
    public var patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Nil when `text` does not start with one to three dot-separated whole numbers.
    public init?(_ text: String) {
        let core = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(omittingEmptySubsequences: false, whereSeparator: { $0 == "-" || $0 == "+" }).first ?? ""
        let fields = core.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(fields.count) else { return nil }
        var numbers: [Int] = []
        for field in fields {
            guard let n = Int(field), n >= 0 else { return nil }
            numbers.append(n)
        }
        while numbers.count < 3 { numbers.append(0) }
        self.init(major: numbers[0], minor: numbers[1], patch: numbers[2])
    }

    /// This build's version.
    public static var current: RimlightVersion {
        guard let version = RimlightVersion(Rimlight.version) else { preconditionFailure("Rimlight.version is malformed") }
        return version
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (a: RimlightVersion, b: RimlightVersion) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }
}
