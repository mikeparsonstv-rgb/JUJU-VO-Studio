import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum BWFWriteError: Error, Equatable, LocalizedError {
    case nonASCII(field: String)
    case fieldTooLong(field: String, max: Int)
    case missingExportID
    case tooLarge
    case destinationExists(String)
    case verificationFailed(String)
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .nonASCII(let f): "\(f) must be plain ASCII."
        case .fieldTooLong(let f, let m): "\(f) is longer than \(m) characters."
        case .missingExportID: "Every JUJU export needs its own export UUID."
        case .tooLarge: "Audio is too large for a single WAV file."
        case .destinationExists(let p): "A file already exists at \(p); JUJU never overwrites an export."
        case .verificationFailed(let why): "The written WAV failed verification: \(why)."
        case .io(let why): "Could not write the WAV: \(why)."
        }
    }
}

/// Human-facing production info written alongside the IDs. Never paths, scripts, keys or consent records.
public struct BWFExportInfo: Sendable {
    public var identifiers: JUJURecallIdentifiers
    public var originator: String
    public var project: String?
    public var scene: String?
    public var take: Int?
    public var origination: Date
    public var timeZone: TimeZone

    public init(identifiers: JUJURecallIdentifiers, originator: String = "JUJU VO Studio", project: String? = nil,
                scene: String? = nil, take: Int? = nil, origination: Date, timeZone: TimeZone = .current) {
        self.identifiers = identifiers; self.originator = originator; self.project = project
        self.scene = scene; self.take = take; self.origination = origination; self.timeZone = timeZone
    }
}

public struct BWFExportReceipt: Equatable, Sendable {
    public let destination: URL
    public let fileSHA256: String
    public let audioSHA256: String
    public let format: WAVFormat
    public let byteCount: Int
    public let duration: Double
}

public enum BWFWriter {
    /// Builds RIFF/WAVE: `fmt ` (verbatim) · `bext` · `iXML` · `data` (verbatim). Metadata precedes audio so it is
    /// found without scanning the samples.
    public static func compose(formatChunk: Data, audio: Data, info: BWFExportInfo) throws -> Data {
        guard let exportID = info.identifiers.exportID else { throw BWFWriteError.missingExportID }
        let format = try WAVFormat.decode(formatChunk)
        let ids = info.identifiers
        let (date, time) = stamp(info.origination, info.timeZone)
        let bext = BextChunk(
            description: BextJUJU.description(job: ids.jobID, take: ids.takeID),
            originator: String(info.originator.unicodeScalars.filter { $0.isASCII && $0.value >= 0x20 }.prefix(32).map(Character.init)),
            originatorReference: JUJUOriginatorReference.encode(ids.takeID),
            originationDate: date, originationTime: time,
            codingHistory: "A=\(format.isFloat ? "PCM_FLOAT" : "PCM"),F=\(format.sampleRate),W=\(format.bitsPerSample),"
                + "M=\(format.channels == 1 ? "mono" : format.channels == 2 ? "stereo" : "multi"),T=\(info.originator.filter(\.isASCII))\r\n")
        let ixml = IXML.encode(.init(project: info.project, scene: info.scene, take: info.take, user: [
            (JUJUMetadata.Key.job, ids.jobID.uuidString.lowercased()),
            (JUJUMetadata.Key.take, ids.takeID.uuidString.lowercased()),
            (JUJUMetadata.Key.export, exportID.uuidString.lowercased()),
            (JUJUMetadata.Key.version, String(ids.metadataVersion))
        ]))

        var body = Data("WAVE".utf8)
        func chunk(_ id: String, _ content: Data) {
            body.appendFourCC(id); body.appendLE(UInt32(content.count)); body.append(content)
            if content.count & 1 == 1 { body.append(0) }
        }
        chunk("fmt ", formatChunk)
        chunk("bext", try bext.encoded())
        chunk("iXML", ixml)
        guard audio.count <= Int(UInt32.max) - body.count - 64 else { throw BWFWriteError.tooLarge }
        chunk("data", audio)
        var out = Data("RIFF".utf8)
        out.appendLE(UInt32(body.count))
        out.append(body)
        return out
    }

    /// Re-wraps an existing WAV's format + audio bytes, untouched, with JUJU metadata, and writes it atomically:
    /// temp file in the destination folder → reopen + verify → no-replace link into place → remove temp.
    public static func export(sourceWAV: URL, to destination: URL, info: BWFExportInfo) throws -> BWFExportReceipt {
        let (src, file) = try WAVReader.load(contentsOf: sourceWAV)
        let fmt = src[file.formatChunkRange]
        let audio = src[file.audioRange]
        let composed = try compose(formatChunk: Data(fmt), audio: Data(audio), info: info)
        return try writeVerified(composed, to: destination, expectedFormat: file.format,
                                 expectedAudioSHA: SHA256.hex(audio), identifiers: info.identifiers)
    }

    /// Writes new audio (e.g. a mock-labelled test take) as a JUJU export.
    public static func write(formatChunk: Data, audio: Data, to destination: URL, info: BWFExportInfo) throws -> BWFExportReceipt {
        let composed = try compose(formatChunk: formatChunk, audio: audio, info: info)
        return try writeVerified(composed, to: destination, expectedFormat: try WAVFormat.decode(formatChunk),
                                 expectedAudioSHA: SHA256.hex(audio), identifiers: info.identifiers)
    }

    static func writeVerified(_ bytes: Data, to destination: URL, expectedFormat: WAVFormat, expectedAudioSHA: String,
                              identifiers: JUJURecallIdentifiers) throws -> BWFExportReceipt {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else { throw BWFWriteError.destinationExists(destination.path) }
        let dir = destination.deletingLastPathComponent()
        let temp = dir.appendingPathComponent(".juju-tmp-\(UUID().uuidString).wav")
        defer { try? fm.removeItem(at: temp) }
        do {
            try bytes.write(to: temp)
            let h = try FileHandle(forUpdating: temp); try h.synchronize(); try h.close()
        } catch { throw BWFWriteError.io(error.localizedDescription) }

        // Verify what is actually on disk, not the in-memory buffer.
        let (onDisk, parsed) = try WAVReader.load(contentsOf: temp)
        guard parsed.format == expectedFormat else { throw BWFWriteError.verificationFailed("format changed") }
        guard SHA256.hex(onDisk[parsed.audioRange]) == expectedAudioSHA else { throw BWFWriteError.verificationFailed("audio bytes changed") }
        guard case .valid(let ids, .ixml) = parsed.juju, ids == identifiers else {
            throw BWFWriteError.verificationFailed("identifiers did not read back (\(parsed.juju))")
        }
        guard parsed.warnings.isEmpty else { throw BWFWriteError.verificationFailed(parsed.warnings.joined(separator: "; ")) }

        // link(2) fails with EEXIST rather than replacing: an export can never overwrite another file.
        if link(temp.path, destination.path) != 0 {
            let e = errno
            if e == EEXIST { throw BWFWriteError.destinationExists(destination.path) }
            throw BWFWriteError.io(String(cString: strerror(e)))
        }
        return BWFExportReceipt(destination: destination, fileSHA256: SHA256.hex(onDisk), audioSHA256: expectedAudioSHA,
                                format: parsed.format, byteCount: onDisk.count, duration: parsed.duration)
    }

    static func stamp(_ date: Date, _ tz: TimeZone) -> (String, String) {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return (String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!),
                String(format: "%02d:%02d:%02d", c.hour!, c.minute!, c.second!))
    }
}
