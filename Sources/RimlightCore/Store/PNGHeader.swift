import Foundation

/// What a PNG's header says, read without decoding pixels: the size from IHDR, and whether
/// the file can carry transparency (colour type 4 or 6, or a tRNS chunk before IDAT). Whether
/// it really is transparent is `ImageProbe`'s call.
public struct PNGHeader: Hashable, Sendable {
    public var width: Int
    public var height: Int
    /// IHDR colour type: 0 grey, 2 RGB, 3 palette, 4 grey and alpha, 6 RGBA.
    public var colorType: UInt8
    public var hasAlpha: Bool

    public init(width: Int, height: Int, colorType: UInt8, hasAlpha: Bool) {
        self.width = width
        self.height = height
        self.colorType = colorType
        self.hasAlpha = hasAlpha
    }

    private static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    /// nil for a missing file or anything that is not a PNG. Reads 33 bytes, plus 8 per
    /// chunk header between IHDR and the first IDAT when the colour type has no alpha.
    public static func read(_ url: URL) -> PNGHeader? {
        let fd = url.withUnsafeFileSystemRepresentation { path in
            path.map { open($0, O_RDONLY | O_CLOEXEC) } ?? -1
        }
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        func bytes(_ n: Int, at offset: off_t) -> [UInt8]? {
            var buf = [UInt8](repeating: 0, count: n)
            let got = buf.withUnsafeMutableBytes { pread(fd, $0.baseAddress, n, offset) }
            return got == n ? buf : nil
        }
        func uint32(_ b: ArraySlice<UInt8>) -> Int { b.reduce(0) { $0 << 8 | Int($1) } }

        // Signature, then IHDR: length 13, type, width, height, depth, colour type, three more bytes, CRC.
        guard let head = bytes(33, at: 0), Array(head[0..<8]) == signature,
            uint32(head[8..<12]) == 13, head[12..<16].elementsEqual("IHDR".utf8)
        else { return nil }
        let width = uint32(head[16..<20])
        let height = uint32(head[20..<24])
        let colorType = head[25]
        guard width > 0, height > 0, [0, 2, 3, 4, 6].contains(colorType) else { return nil }

        var hasAlpha = colorType == 4 || colorType == 6
        var offset: off_t = 33
        // tRNS must come before the first IDAT, so the walk stops there.
        while !hasAlpha, let chunk = bytes(8, at: offset) {
            let type = chunk[4..<8]
            if type.elementsEqual("tRNS".utf8) { hasAlpha = true }
            if type.elementsEqual("IDAT".utf8) || type.elementsEqual("IEND".utf8) { break }
            offset += off_t(8 + uint32(chunk[0..<4]) + 4)
        }
        return PNGHeader(width: width, height: height, colorType: colorType, hasAlpha: hasAlpha)
    }
}
