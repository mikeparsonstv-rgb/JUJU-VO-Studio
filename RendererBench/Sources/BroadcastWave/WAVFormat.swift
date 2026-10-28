import Foundation

/// Decoded `fmt ` chunk. The original chunk bytes are kept separately so exports copy them verbatim.
public struct WAVFormat: Equatable, Hashable, Sendable, Codable {
    public static let tagPCM: UInt16 = 1
    public static let tagFloat: UInt16 = 3
    public static let tagExtensible: UInt16 = 0xFFFE

    public let formatTag: UInt16
    /// `formatTag`, or the sub-format of a WAVE_FORMAT_EXTENSIBLE header (1 = PCM, 3 = float).
    public let effectiveFormatTag: UInt16
    public let channels: UInt16
    public let sampleRate: UInt32
    public let byteRate: UInt32
    public let blockAlign: UInt16
    public let bitsPerSample: UInt16

    public var isFloat: Bool { effectiveFormatTag == Self.tagFloat }
    public func duration(ofAudioBytes count: Int) -> Double { Double(count) / Double(byteRate) }

    /// Human summary, e.g. "48000 Hz · 24-bit PCM · mono".
    public var summary: String {
        let ch = channels == 1 ? "mono" : channels == 2 ? "stereo" : "\(channels) ch"
        return "\(sampleRate) Hz · \(bitsPerSample)-bit \(isFloat ? "float" : "PCM") · \(ch)"
    }

    /// Bytes of a canonical 16-byte PCM/float `fmt ` chunk body for new audio.
    public static func canonicalChunk(sampleRate: UInt32, channels: UInt16, bitsPerSample: UInt16, float: Bool = false) -> Data {
        var d = Data()
        let blockAlign = channels * (bitsPerSample / 8)
        d.appendLE(float ? tagFloat : tagPCM)
        d.appendLE(channels)
        d.appendLE(sampleRate)
        d.appendLE(sampleRate * UInt32(blockAlign))
        d.appendLE(blockAlign)
        d.appendLE(bitsPerSample)
        return d
    }

    static func decode(_ body: Data) throws -> WAVFormat {
        let b = body.zeroBased
        guard b.count >= 16 else { throw WAVParseError.invalidFormat("fmt chunk shorter than 16 bytes") }
        let tag = b.u16(0), ch = b.u16(2), sr = b.u32(4), br = b.u32(8), ba = b.u16(12), bits = b.u16(14)
        var effective = tag
        if tag == tagExtensible {
            guard b.count >= 40 else { throw WAVParseError.invalidFormat("extensible fmt chunk shorter than 40 bytes") }
            effective = b.u16(24) // first two bytes of the sub-format GUID
            let guidTail: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71]
            guard Array(b[26..<40]) == guidTail else { throw WAVParseError.unsupportedFormat(tag) }
        }
        guard effective == tagPCM || effective == tagFloat else { throw WAVParseError.unsupportedFormat(effective) }
        guard ch > 0, ch <= 64 else { throw WAVParseError.invalidFormat("channel count \(ch)") }
        guard sr >= 1000, sr <= 768_000 else { throw WAVParseError.invalidFormat("sample rate \(sr)") }
        let validBits: Set<UInt16> = effective == tagFloat ? [32, 64] : [8, 16, 24, 32]
        guard validBits.contains(bits) else { throw WAVParseError.invalidFormat("\(bits) bits per sample") }
        guard UInt32(ba) == UInt32(ch) * UInt32(bits / 8) else { throw WAVParseError.invalidFormat("block align \(ba)") }
        guard br == sr * UInt32(ba) else { throw WAVParseError.invalidFormat("byte rate \(br)") }
        return WAVFormat(formatTag: tag, effectiveFormatTag: effective, channels: ch, sampleRate: sr,
                         byteRate: br, blockAlign: ba, bitsPerSample: bits)
    }
}
