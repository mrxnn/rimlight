import Foundation

/// Icon slugs: lowercase ASCII letters, digits and hyphens, no leading hyphen, at most 64
/// characters, unique within a set. They are folder names, so they must read well in Finder.
public enum Slug {
    public static let maxLength = 64

    public static func isValid(_ s: String) -> Bool {
        guard !s.isEmpty, s.utf8.count <= maxLength, s.utf8.first != UInt8(ascii: "-") else { return false }
        return s.utf8.allSatisfy { b in
            (b >= UInt8(ascii: "a") && b <= UInt8(ascii: "z"))
                || (b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9"))
                || b == UInt8(ascii: "-")
        }
    }

    public static func validate(_ s: String, as what: String = "icon") throws {
        guard isValid(s) else {
            throw StoreError.invalidID(
                "\(what) slug \"\(s)\" is not valid: use a-z, 0-9 and -, no leading hyphen, at most \(maxLength) characters"
            )
        }
    }

    /// Turns free text into a slug: "Counter with + × a" becomes "counter-with-a".
    public static func make(from text: String, maxLength: Int = 40) -> String {
        var out = ""
        var pendingHyphen = false
        for scalar in text.lowercased().unicodeScalars {
            let isAlnum = (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9")
            if isAlnum {
                if pendingHyphen && !out.isEmpty { out.append("-") }
                pendingHyphen = false
                out.unicodeScalars.append(scalar)
            } else {
                pendingHyphen = true
            }
            if out.count >= maxLength { break }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out
    }
}

/// Set ids: `set-001`, `set-002`, … in creation order.
public enum SetID {
    public static func make(_ n: Int) -> String { String(format: "set-%03d", n) }

    /// The number in `set-NNN`, or nil for anything else.
    public static func number(_ id: String) -> Int? {
        guard id.hasPrefix("set-") else { return nil }
        let digits = id.utf8.dropFirst(4)
        guard digits.count >= 3, digits.allSatisfy({ $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }) else {
            return nil
        }
        return Int(String(decoding: digits, as: UTF8.self))
    }

    public static func isValid(_ id: String) -> Bool { number(id) != nil }

    /// Newest first: by number, descending.
    public static func newestFirst(_ a: String, _ b: String) -> Bool {
        switch (number(a), number(b)) {
        case let (x?, y?): return x != y ? x > y : a > b
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return a > b
        }
    }
}
