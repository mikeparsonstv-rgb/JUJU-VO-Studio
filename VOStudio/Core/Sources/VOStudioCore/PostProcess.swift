import Foundation
import BroadcastWave

/// The only automatic edit JUJU makes to engine output: trailing samples that are *exactly zero* (digital
/// padding, not quiet room tone) are trimmed to a short tail. Recorded on the take; the raw file's hash is kept.
public enum DigitalSilence {
    public struct Result: Sendable, Equatable, Codable {
        public var rawSHA256: String
        public var trimmedSeconds: Double
        public var note: String?
    }

    public static func trimTrailingZeros(at url: URL, keepTail: Double = 0.15, minimumToTrim: Double = 0.25) throws -> Result {
        let (data, file) = try WAVReader.load(contentsOf: url)
        let raw = SHA256.hex(data)
        let f = file.format
        guard f.effectiveFormatTag == WAVFormat.tagFloat || f.bitsPerSample >= 16 else { return Result(rawSHA256: raw, trimmedSeconds: 0, note: nil) }
        let block = Int(f.blockAlign)
        let audio = data[file.audioRange]
        var frames = audio.count / block
        let base = file.audioRange.lowerBound
        let total = frames
        data.withUnsafeBytes { p in
            let b = p.bindMemory(to: UInt8.self)
            outer: while frames > 0 {
                let o = base + (frames - 1) * block
                for i in 0..<block where b[o + i] != 0 { break outer }
                frames -= 1
            }
        }
        let keep = min(total, frames + Int(keepTail * Double(f.sampleRate)))
        let trimmed = Double(total - keep) / Double(f.sampleRate)
        guard trimmed >= minimumToTrim else { return Result(rawSHA256: raw, trimmedSeconds: 0, note: nil) }
        let fmt = Data(data[file.formatChunkRange])
        let newAudio = Data(audio.prefix(keep * block))
        var body = Data("WAVE".utf8)
        for (id, c) in [("fmt ", fmt), ("data", newAudio)] {
            body.append(contentsOf: Array(id.utf8)); var n = UInt32(c.count).littleEndian; body.append(Data(bytes: &n, count: 4)); body.append(c)
            if c.count % 2 == 1 { body.append(0) }
        }
        var out = Data("RIFF".utf8); var n = UInt32(body.count).littleEndian; out.append(Data(bytes: &n, count: 4)); out.append(body)
        try out.write(to: url, options: .atomic)
        return Result(rawSHA256: raw, trimmedSeconds: trimmed,
                      note: String(format: "Trimmed %.2f s of exact digital silence from the end of the engine output (kept %.2f s tail).", trimmed, keepTail))
    }
}
