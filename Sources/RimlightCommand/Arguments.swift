import Foundation

struct UsageError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

/// One command's arguments: positionals, boolean flags, and options that take a value
/// (`--name value` or `--name=value`, repeatable). `--` ends the options.
struct Arguments {
    private(set) var positionals: [String] = []
    private var values: [String: [String]] = [:]
    private var flags: Set<String> = []

    init(_ args: some Sequence<String>, flags allowedFlags: Set<String> = [], options allowedOptions: Set<String> = []) throws {
        let allowedFlags = allowedFlags.union(["--json"])
        let allowedOptions = allowedOptions.union(["--project"])
        var iterator = args.makeIterator()
        var optionsEnded = false
        while let arg = iterator.next() {
            if optionsEnded || !arg.hasPrefix("-") || arg == "-" {
                positionals.append(arg)
                continue
            }
            if arg == "--" {
                optionsEnded = true
                continue
            }
            var name = arg
            var inline: String?
            if arg.hasPrefix("--"), let eq = arg.firstIndex(of: "=") {
                name = String(arg[..<eq])
                inline = String(arg[arg.index(after: eq)...])
            }
            if allowedFlags.contains(name) {
                guard inline == nil else { throw UsageError("\(name) takes no value") }
                flags.insert(name)
            } else if allowedOptions.contains(name) {
                guard let value = inline ?? iterator.next() else { throw UsageError("\(name) needs a value") }
                values[name, default: []].append(value)
            } else {
                throw UsageError("unknown option \(arg)")
            }
        }
    }

    func flag(_ name: String) -> Bool { flags.contains(name) }

    /// The last value given for `name`.
    func value(_ name: String) -> String? { values[name]?.last }

    /// Every value given for `name`, in order.
    func values(_ name: String) -> [String] { values[name] ?? [] }

    func required(_ name: String) throws -> String {
        guard let v = value(name), !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UsageError("\(name) is required")
        }
        return v
    }

    func int(_ name: String) throws -> Int? {
        guard let raw = value(name) else { return nil }
        guard let n = Int(raw) else { throw UsageError("\(name) takes a whole number, not \"\(raw)\"") }
        return n
    }

    func expectPositionals(_ count: Int, _ usage: String) throws {
        guard positionals.count == count else { throw UsageError("usage: \(usage)") }
    }
}
