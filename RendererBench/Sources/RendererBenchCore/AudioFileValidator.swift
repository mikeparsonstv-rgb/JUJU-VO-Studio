import Foundation

public enum AudioFileValidationError: Error, LocalizedError, Equatable {
    case missing
    case empty
    case invalidContainer
    case invalidDuration

    public var errorDescription: String? {
        switch self {
        case .missing: "Renderer reported success but did not create its output audio file"
        case .empty: "Renderer reported success but created an empty output audio file"
        case .invalidContainer: "Renderer output is not a readable PCM or IEEE-float WAV container"
        case .invalidDuration: "Renderer reported a zero or nonsensical output duration"
        }
    }
}

public struct ValidatedAudio: Equatable, Sendable {
    public let duration: Double
    public let sampleRate: UInt32
    public let channels: UInt16
}

public enum AudioFileValidator {
    public static func validateWAV(at url: URL, reportedDuration: Double) throws -> ValidatedAudio {
        guard reportedDuration.isFinite, reportedDuration > 0 else { throw AudioFileValidationError.invalidDuration }
        guard FileManager.default.fileExists(atPath: url.path) else { throw AudioFileValidationError.missing }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard !data.isEmpty else { throw AudioFileValidationError.empty }
        guard data.count >= 44, data.ascii(0..<4) == "RIFF", data.ascii(8..<12) == "WAVE" else {
            throw AudioFileValidationError.invalidContainer
        }

        var offset = 12
        var format: UInt16?, channels: UInt16?, sampleRate: UInt32?, byteRate: UInt32?, dataBytes: UInt32?
        while offset + 8 <= data.count {
            let id = data.ascii(offset..<(offset + 4))
            let size = Int(data.uint32LE(at: offset + 4))
            let content = offset + 8
            guard size >= 0, content + size <= data.count else { throw AudioFileValidationError.invalidContainer }
            if id == "fmt ", size >= 16 {
                format = data.uint16LE(at: content)
                channels = data.uint16LE(at: content + 2)
                sampleRate = data.uint32LE(at: content + 4)
                byteRate = data.uint32LE(at: content + 8)
            } else if id == "data" {
                dataBytes = UInt32(size)
            }
            offset = content + size + (size % 2)
        }
        guard let format, format == 1 || format == 3,
              let channels, channels > 0,
              let sampleRate, sampleRate > 0,
              let byteRate, byteRate > 0,
              let dataBytes, dataBytes > 0 else { throw AudioFileValidationError.invalidContainer }
        let actualDuration = Double(dataBytes) / Double(byteRate)
        guard actualDuration.isFinite, actualDuration > 0 else { throw AudioFileValidationError.invalidDuration }
        return ValidatedAudio(duration: actualDuration, sampleRate: sampleRate, channels: channels)
    }
}

private extension Data {
    func ascii(_ range: Range<Int>) -> String? { String(data: self[range], encoding: .ascii) }
    func uint16LE(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }
    func uint32LE(at offset: Int) -> UInt32 {
        UInt32(self[offset]) | (UInt32(self[offset + 1]) << 8) |
        (UInt32(self[offset + 2]) << 16) | (UInt32(self[offset + 3]) << 24)
    }
}
