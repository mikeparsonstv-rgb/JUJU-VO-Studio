import Foundation

/// Little-endian helpers. All readers take zero-based `Data` (callers normalise slices first).
extension Data {
    @inline(__always) func u16(_ o: Int) -> UInt16 { UInt16(self[o]) | UInt16(self[o + 1]) << 8 }
    @inline(__always) func u32(_ o: Int) -> UInt32 {
        UInt32(self[o]) | UInt32(self[o + 1]) << 8 | UInt32(self[o + 2]) << 16 | UInt32(self[o + 3]) << 24
    }
    @inline(__always) func u64(_ o: Int) -> UInt64 { UInt64(u32(o)) | UInt64(u32(o + 4)) << 32 }
    func fourCC(_ o: Int) -> String { String(decoding: self[o..<(o + 4)], as: UTF8.self) }

    mutating func appendLE(_ v: UInt16) { append(UInt8(truncatingIfNeeded: v)); append(UInt8(truncatingIfNeeded: v >> 8)) }
    mutating func appendLE(_ v: UInt32) { for s in [0, 8, 16, 24] { append(UInt8(truncatingIfNeeded: v >> UInt32(s))) } }
    mutating func appendLE(_ v: Int16) { appendLE(UInt16(bitPattern: v)) }
    mutating func appendFourCC(_ id: String) { append(contentsOf: Array(id.utf8.prefix(4))) }

    /// Fixed-width ASCII field, NUL-padded. Throws if the text is non-ASCII or too long.
    mutating func appendFixedASCII(_ s: String, width: Int, field: String) throws {
        let bytes = Array(s.utf8)
        guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { throw BWFWriteError.nonASCII(field: field) }
        guard bytes.count <= width else { throw BWFWriteError.fieldTooLong(field: field, max: width) }
        append(contentsOf: bytes)
        append(contentsOf: [UInt8](repeating: 0, count: width - bytes.count))
    }

    /// ASCII text up to the first NUL in a fixed field; non-printables are dropped.
    func fixedASCII(_ o: Int, width: Int) -> String {
        let field = self[o..<(o + width)]
        let end = field.firstIndex(of: 0) ?? field.endIndex
        return String(decoding: field[field.startIndex..<end].filter { $0 >= 0x20 && $0 < 0x7F }, as: UTF8.self)
    }

    /// Re-base a slice so indices start at 0.
    var zeroBased: Data { startIndex == 0 ? self : Data(self) }
}
