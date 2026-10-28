import Foundation

public enum WAVParseError: Error, Equatable, LocalizedError {
    case notRIFFWave
    case fileTooLarge(Int)
    case chunkOutOfBounds(id: String, offset: Int, declaredSize: UInt32)
    case tooManyChunks
    case missingFormat
    case missingAudio
    case duplicateChunk(String)
    case invalidFormat(String)
    case unsupportedFormat(UInt16)
    case emptyAudio

    public var errorDescription: String? {
        switch self {
        case .notRIFFWave: "Not a WAV file (no RIFF/WAVE header)."
        case .fileTooLarge(let n): "File is too large for a WAV (\(n) bytes)."
        case .chunkOutOfBounds(let id, let o, let s): "Damaged WAV: chunk '\(id)' at byte \(o) claims \(s) bytes, past the end of the file."
        case .tooManyChunks: "Damaged WAV: implausible number of chunks."
        case .missingFormat: "WAV has no format chunk."
        case .missingAudio: "WAV has no audio data chunk."
        case .duplicateChunk(let id): "WAV has more than one '\(id)' chunk."
        case .invalidFormat(let why): "WAV format header is invalid (\(why))."
        case .unsupportedFormat(let tag): "Unsupported WAV encoding (format tag \(tag)); JUJU reads PCM and float WAV."
        case .emptyAudio: "WAV contains no audio."
        }
    }
}

/// A parsed RIFF/WAVE file. Offsets refer to the bytes passed to `WAVReader.parse`.
public struct WAVFile: Sendable {
    public struct Chunk: Equatable, Sendable {
        public let id: String
        public let offset: Int        // start of the 8-byte chunk header
        public let size: Int          // declared content size
        public var contentRange: Range<Int> { (offset + 8)..<(offset + 8 + size) }
    }
    public let chunks: [Chunk]
    public let format: WAVFormat
    public let formatChunkRange: Range<Int>
    public let audioRange: Range<Int>
    public let bext: BextChunk?
    public let ixml: String?
    public let juju: JUJUMetadata
    /// Tolerated irregularities (shown in diagnostics, never fatal).
    public let warnings: [String]

    public var audioByteCount: Int { audioRange.count }
    public var duration: Double { format.duration(ofAudioBytes: audioRange.count) }
}

public enum WAVReader {
    /// Upper bound on chunks walked; real files have a handful.
    public static let maxChunks = 512

    /// Parses bytes without trusting any declared length. Never reads outside `data`.
    public static func parse(_ input: Data) throws -> WAVFile {
        let data = input.zeroBased
        guard data.count <= Int(UInt32.max) + 8 else { throw WAVParseError.fileTooLarge(data.count) }
        guard data.count >= 12, data.fourCC(0) == "RIFF", data.fourCC(8) == "WAVE" else { throw WAVParseError.notRIFFWave }
        var warnings: [String] = []
        let riffEnd = Int(data.u32(4)) + 8
        if riffEnd != data.count { warnings.append("RIFF size says \(riffEnd) bytes, file has \(data.count)") }

        var chunks: [WAVFile.Chunk] = []
        var offset = 12
        while offset + 8 <= data.count {
            guard chunks.count < maxChunks else { throw WAVParseError.tooManyChunks }
            let id = data.fourCC(offset)
            let declared = data.u32(offset + 4)
            let size = Int(declared)
            guard offset + 8 + size <= data.count else {
                throw WAVParseError.chunkOutOfBounds(id: id, offset: offset, declaredSize: declared)
            }
            chunks.append(.init(id: id, offset: offset, size: size))
            offset += 8 + size + (size & 1)
        }
        if offset < data.count { warnings.append("\(data.count - offset) trailing bytes after last chunk") }
        if offset > data.count { warnings.append("final chunk is missing its pad byte") }

        func single(_ id: String) throws -> WAVFile.Chunk? {
            let found = chunks.filter { $0.id == id }
            guard found.count <= 1 else { throw WAVParseError.duplicateChunk(id) }
            return found.first
        }
        guard let fmt = try single("fmt ") else { throw WAVParseError.missingFormat }
        guard let audio = try single("data") else { throw WAVParseError.missingAudio }
        let format = try WAVFormat.decode(data[fmt.contentRange])
        guard audio.size > 0 else { throw WAVParseError.emptyAudio }
        if audio.size % Int(format.blockAlign) != 0 { warnings.append("audio length is not a whole number of sample frames") }

        // Metadata chunks: a damaged or duplicated metadata chunk never blocks reading the audio.
        let bextChunks = chunks.filter { $0.id == "bext" }
        let ixmlChunks = chunks.filter { $0.id == "iXML" }
        var bext: BextChunk?
        if let c = bextChunks.first {
            do { bext = try BextChunk.decode(data[c.contentRange]) } catch { warnings.append("bext chunk unreadable") }
        }
        let ixml = ixmlChunks.first.map { IXML.text(from: data[$0.contentRange]) }
        let juju: JUJUMetadata
        if bextChunks.count > 1 || ixmlChunks.count > 1 {
            juju = .conflicting("file has more than one \(bextChunks.count > 1 ? "bext" : "iXML") chunk")
        } else {
            juju = JUJUMetadata.extract(ixml: ixml, bext: bext)
        }
        return WAVFile(chunks: chunks, format: format, formatChunkRange: fmt.contentRange, audioRange: audio.contentRange,
                       bext: bext, ixml: ixml, juju: juju, warnings: warnings)
    }

    /// Reads and parses a file. Returns the bytes too, so callers can copy the audio without a second read.
    public static func load(contentsOf url: URL) throws -> (data: Data, file: WAVFile) {
        let data = try Data(contentsOf: url, options: .mappedIfSafe).zeroBased
        return (data, try parse(data))
    }
}
