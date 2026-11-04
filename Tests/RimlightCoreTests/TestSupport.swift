import Foundation
import ImageIO

/// A fresh folder under the temp directory, removed when the closure returns.
func withTempDir<T>(_ body: (URL) throws -> T) throws -> T {
    let dir = FileManager.default.temporaryDirectory
        .appending(path: "rimlight-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    return try body(dir)
}

/// Hand-built PNGs: valid files (zlib stored block, real CRCs) with a chosen colour type, so
/// the header reader is tested on every alpha case without an encoder deciding for us.
enum TinyPNG {
    enum Kind {
        case rgb, rgba, palette, paletteWithTRNS, grey

        var colorType: UInt8 {
            switch self {
            case .grey: 0
            case .rgb: 2
            case .palette, .paletteWithTRNS: 3
            case .rgba: 6
            }
        }

        var bytesPerPixel: Int {
            switch self {
            case .grey, .palette, .paletteWithTRNS: 1
            case .rgb: 3
            case .rgba: 4
            }
        }
    }

    static func make(_ kind: Kind, width: Int = 3, height: Int = 2) -> Data {
        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        png += chunk("IHDR", be32(width) + be32(height) + [8, kind.colorType, 0, 0, 0])
        if kind == .palette || kind == .paletteWithTRNS {
            png += chunk("PLTE", [0xF0, 0xE8, 0xD8, 0x6B, 0x70, 0x3A])
        }
        if kind == .paletteWithTRNS {
            png += chunk("tRNS", [0x00, 0xFF])
        }
        var raw: [UInt8] = []
        for _ in 0..<height {
            raw.append(0)  // filter: none
            raw += [UInt8](repeating: 1, count: width * kind.bytesPerPixel)
        }
        png += chunk("IDAT", zlibStored(raw))
        png += chunk("IEND", [])
        return png
    }

    /// Whether ImageIO can decode the bytes, to prove the fixtures are real PNGs.
    static func decodes(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    }

    private static func chunk(_ type: String, _ data: [UInt8]) -> Data {
        let typeBytes = Array(type.utf8)
        return Data(be32(data.count) + typeBytes + data + be32(Int(crc32(typeBytes + data))))
    }

    private static func be32(_ n: Int) -> [UInt8] {
        [UInt8(n >> 24 & 0xFF), UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)]
    }

    private static func zlibStored(_ data: [UInt8]) -> [UInt8] {
        let len = data.count
        var out: [UInt8] = [0x78, 0x01, 0x01, UInt8(len & 0xFF), UInt8(len >> 8), UInt8(~len & 0xFF), UInt8(~len >> 8 & 0xFF)]
        out += data
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return out + be32(Int(b << 16 | a))
    }

    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }
}
