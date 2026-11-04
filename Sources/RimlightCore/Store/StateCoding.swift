import Foundation

public enum StoreError: Error, CustomStringConvertible, LocalizedError, Equatable {
    case invalidID(String)
    case alreadyExists(String)
    case notFound(String)
    case invalidArgument(String)
    case io(String)
    /// Another process held `.rimlight/.lock` past the timeout.
    case lockTimeout(String)
    /// A file under `.rimlight/` carries this `schema`, above `Project.currentSchema`.
    case newerSchema(Int)

    public var description: String {
        switch self {
        case .invalidID(let m), .alreadyExists(let m), .notFound(let m), .invalidArgument(let m), .io(let m),
            .lockTimeout(let m):
            return m
        case .newerSchema(let found):
            return "This project was written by a newer rimlight (schema \(found); this build reads "
                + "\(Project.currentSchema)). Update rimlight."
        }
    }

    public var errorDescription: String? { description }
}

/// JSON settings for every file under `.rimlight/`: pretty, sorted keys so git diffs stay
/// stable, no escaped slashes, ISO 8601 UTC dates without fractional seconds.
public enum StateCoding {
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .custom(encodeDate)
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom(decodeDate)
        return d
    }

    /// Pretty JSON with a trailing newline.
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        var data = try encoder().encode(value)
        data.append(UInt8(ascii: "\n"))
        return data
    }

    public static func formatDate(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .gmt))
    }

    /// Accepts dates with or without fractional seconds.
    public static func parseDate(_ s: String) -> Date? {
        if let d = try? Date.ISO8601FormatStyle(timeZone: .gmt).parse(s) { return d }
        if let d = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .gmt).parse(s) { return d }
        return nil
    }

    /// `date` cut to whole seconds, which is what a round trip through a file keeps.
    public static func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    @Sendable private static func encodeDate(_ date: Date, _ encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(formatDate(date))
    }

    @Sendable private static func decodeDate(_ decoder: Decoder) throws -> Date {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let d = parseDate(s) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Not an ISO 8601 date: \(s)")
        }
        return d
    }
}

/// Writes a whole file as a hidden temp file in the same folder, then renames it over the
/// target, so a reader sees the old file or the new one and never half of one.
public enum AtomicFile {
    public static func write(_ data: Data, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        let temp = dir.appending(
            path: ".\(url.lastPathComponent).\(UUID().uuidString).tmp", directoryHint: .notDirectory)
        let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw StoreError.io("Cannot create \(temp.path) (errno \(errno))") }
        var failure: Int32 = 0
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let n = Darwin.write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    failure = errno
                    return
                }
                offset += n
            }
        }
        close(fd)
        if failure != 0 {
            unlink(temp.path)
            throw StoreError.io("Cannot write \(temp.path) (errno \(failure))")
        }
        guard rename(temp.path, url.path) == 0 else {
            let err = errno
            unlink(temp.path)
            throw StoreError.io("Cannot rename \(temp.path) to \(url.path) (errno \(err))")
        }
    }

    /// Moves `source` to `dest`, replacing it, in one rename. Across volumes the file is
    /// copied next to `dest` first, so the final step is still a rename.
    public static func move(_ source: URL, to dest: URL) throws {
        if rename(source.path, dest.path) == 0 { return }
        let err = errno
        guard err == EXDEV else {
            throw StoreError.io("Cannot move \(source.path) to \(dest.path) (errno \(err))")
        }
        let temp = dest.deletingLastPathComponent().appending(
            path: ".\(dest.lastPathComponent).\(UUID().uuidString).tmp", directoryHint: .notDirectory)
        do {
            try FileManager.default.copyItem(at: source, to: temp)
        } catch {
            throw StoreError.io("Cannot copy \(source.path) to \(temp.path): \(error.localizedDescription)")
        }
        guard rename(temp.path, dest.path) == 0 else {
            let err = errno
            unlink(temp.path)
            throw StoreError.io("Cannot rename \(temp.path) to \(dest.path) (errno \(err))")
        }
        unlink(source.path)
    }
}
