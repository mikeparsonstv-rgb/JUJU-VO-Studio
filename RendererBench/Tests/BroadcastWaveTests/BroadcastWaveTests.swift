import Foundation
import Testing
@testable import BroadcastWave
import RendererBenchCore

// MARK: - Fixtures

private let jobA = UUID(uuidString: "0A1B2C3D-4E5F-4A6B-8C7D-0E1F2A3B4C5D")!
private let takeJane0304 = UUID(uuidString: "9F8E7D6C-5B4A-4938-8271-605F4E3D2C1B")!
private let export1 = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
private let export2 = UUID(uuidString: "66666666-7777-4888-9999-AAAAAAAAAAAA")!

private func tempDir() throws -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("bw-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

/// Plain 44-byte-header WAV with a deterministic ramp — stands in for a renderer output (test fixture, not a take).
private func plainWAV(sampleRate: UInt32 = 48_000, channels: UInt16 = 1, bits: UInt16 = 24, frames: Int = 4_800) -> Data {
    let fmt = WAVFormat.canonicalChunk(sampleRate: sampleRate, channels: channels, bitsPerSample: bits)
    var audio = Data()
    for i in 0..<(frames * Int(channels) * Int(bits / 8)) { audio.append(UInt8(truncatingIfNeeded: i &* 31 &+ 7)) }
    return riff([("fmt ", fmt), ("data", audio)])
}

private func riff(_ chunks: [(String, Data)]) -> Data {
    var body = Data("WAVE".utf8)
    for (id, c) in chunks {
        body.append(contentsOf: Array(id.utf8)); body.appendLE(UInt32(c.count)); body.append(c)
        if c.count % 2 == 1 { body.append(0) }
    }
    var out = Data("RIFF".utf8); out.appendLE(UInt32(body.count)); out.append(body); return out
}

private func info(_ export: UUID?, job: UUID = jobA, take: UUID = takeJane0304) -> BWFExportInfo {
    BWFExportInfo(identifiers: .init(jobID: job, takeID: take, exportID: export), project: "Job A",
                  scene: "Line03", take: 4, origination: Date(timeIntervalSince1970: 1_793_200_000),
                  timeZone: TimeZone(identifier: "Europe/London")!)
}

private func exportFixture(_ dir: URL, name: String = "JobA-Jane-2026-10-28-Line03-Take04.wav",
                           source: Data = plainWAV(), export: UUID = export1) throws -> (URL, BWFExportReceipt, Data) {
    let src = dir.appendingPathComponent("render-\(UUID().uuidString).wav")
    try source.write(to: src)
    let dest = dir.appendingPathComponent(name)
    return (dest, try BWFWriter.export(sourceWAV: src, to: dest, info: info(export)), source)
}

// MARK: - Independent reader (shares no code with BroadcastWave)

private struct IndependentWAV {
    var chunks: [(id: String, start: Int, size: Int)] = []
    var bytes: [UInt8]
    init(_ data: Data) throws {
        bytes = [UInt8](data)
        func u32(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o+1]) << 8 | Int(bytes[o+2]) << 16 | Int(bytes[o+3]) << 24 }
        guard bytes.count >= 12, String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
              String(bytes: bytes[8..<12], encoding: .ascii) == "WAVE", u32(4) + 8 == bytes.count else { throw CocoaError(.fileReadCorruptFile) }
        var p = 12
        while p < bytes.count {
            let id = String(bytes: bytes[p..<p+4], encoding: .ascii)!
            let n = u32(p + 4)
            guard p + 8 + n <= bytes.count else { throw CocoaError(.fileReadCorruptFile) }
            chunks.append((id, p + 8, n)); p += 8 + n + (n & 1)
        }
        guard p == bytes.count else { throw CocoaError(.fileReadCorruptFile) }
    }
    func body(_ id: String) -> [UInt8]? { chunks.first { $0.id == id }.map { Array(bytes[$0.start..<$0.start+$0.size]) } }
    func ixmlUserValue(_ key: String) -> String? {
        guard let x = body("iXML"), let s = String(bytes: x, encoding: .utf8),
              let a = s.range(of: "<USER>"), let b = s.range(of: "</USER>") else { return nil }
        for line in s[a.upperBound..<b.lowerBound].components(separatedBy: "\n") where line.hasPrefix(key + "=") {
            return String(line.dropFirst(key.count + 1))
        }
        return nil
    }
    func bextString(_ offset: Int, _ width: Int) -> String {
        let f = body("bext")![offset..<offset+width]
        return String(bytes: f.prefix { $0 != 0 }, encoding: .ascii)!
    }
}

// MARK: - §7A.4 vectors (model-free)

@Test func exportCarriesExactIDsReadByIndependentParser() throws {
    let dir = try tempDir()
    let (url, receipt, source) = try exportFixture(dir)
    let w = try IndependentWAV(try Data(contentsOf: url))
    #expect(w.ixmlUserValue("JUJU_JOB_UUID") == jobA.uuidString.lowercased())
    #expect(w.ixmlUserValue("JUJU_TAKE_UUID") == takeJane0304.uuidString.lowercased())
    #expect(w.ixmlUserValue("JUJU_EXPORT_UUID") == export1.uuidString.lowercased())
    #expect(w.ixmlUserValue("JUJU_METADATA_VERSION") == "1")
    // fmt and data bytes are byte-identical to the source render
    let src = try IndependentWAV(source)
    #expect(w.body("fmt ") == src.body("fmt "))
    #expect(w.body("data") == src.body("data"))
    #expect(w.chunks.map(\.id) == ["fmt ", "bext", "iXML", "data"])
    // the existing bench validator accepts it
    let v = try AudioFileValidator.validateWAV(at: url, reportedDuration: 0.1)
    #expect(v.sampleRate == 48_000 && v.channels == 1 && abs(v.duration - 0.1) < 1e-9)
    #expect(receipt.audioSHA256 == SHA256.hex(Data(src.body("data")!)))
    #expect(receipt.fileSHA256 == SHA256.hex(try Data(contentsOf: url)))
}

@Test func bextLayoutMatchesEBU3285v2() throws {
    let dir = try tempDir()
    let (url, _, _) = try exportFixture(dir)
    let w = try IndependentWAV(try Data(contentsOf: url))
    let b = w.body("bext")!
    #expect(b.count >= 602)
    #expect(w.bextString(0, 256) == "JUJU job=\(jobA.uuidString.lowercased()); take=\(takeJane0304.uuidString.lowercased())")
    #expect(w.bextString(256, 32) == "JUJU VO Studio")
    let ref = w.bextString(288, 32)
    #expect(ref.count == 30 && ref.count <= 32 && !ref.contains("-"))
    #expect(JUJUOriginatorReference.decode(ref) == takeJane0304)
    #expect(w.bextString(320, 10) == "2026-10-28")          // local date, Europe/London
    #expect(b[346] == 2 && b[347] == 0)                      // version 2
    for k in 0..<5 { #expect(b[412 + 2*k] == 0xFF && b[413 + 2*k] == 0x7F) } // loudness "not measured"
    #expect(String(bytes: b[602...], encoding: .ascii)!.hasPrefix("A=PCM,F=48000,W=24,M=mono"))
}

@Test func secondExportOfSameTakeKeepsJobAndTakeWithDistinctExport() throws {
    let dir = try tempDir()
    let (u1, r1, _) = try exportFixture(dir)
    let (u2, r2, _) = try exportFixture(dir, name: "JobA-Jane-2026-10-28-Line03-Take04-44k16.wav",
                                        source: plainWAV(sampleRate: 44_100, bits: 16, frames: 4_410), export: export2)
    let a = try WAVReader.load(contentsOf: u1).file.juju.identifiers!
    let b = try WAVReader.load(contentsOf: u2).file.juju.identifiers!
    #expect(a.jobID == b.jobID && a.takeID == b.takeID)
    #expect(a.exportID == export1 && b.exportID == export2)
    #expect(r1.format != r2.format && r2.format.sampleRate == 44_100 && r2.format.bitsPerSample == 16)
}

@Test func renamedFileStillResolvesFromMetadata() throws {
    let dir = try tempDir()
    let (url, _, _) = try exportFixture(dir)
    let renamed = dir.appendingPathComponent("FINAL final v3 (client).wav")
    try FileManager.default.moveItem(at: url, to: renamed)
    #expect(try WAVReader.load(contentsOf: renamed).file.juju == .valid(.init(jobID: jobA, takeID: takeJane0304, exportID: export1), source: .ixml))
}

@Test func strippedMetadataReadsAsAbsentWithAudioIntact() throws {
    let dir = try tempDir()
    let (url, _, source) = try exportFixture(dir)
    let w = try IndependentWAV(try Data(contentsOf: url))
    let stripped = riff([("fmt ", Data(w.body("fmt ")!)), ("data", Data(w.body("data")!))])
    let f = try WAVReader.parse(stripped)
    #expect(f.juju == .absent)
    #expect(Data(stripped[f.audioRange]) == Data(try IndependentWAV(source).body("data")!))
}

@Test func bextOnlyFallbackRecoversJobAndTake() throws {
    let dir = try tempDir()
    let (url, _, _) = try exportFixture(dir)
    let w = try IndependentWAV(try Data(contentsOf: url))
    let noIXML = riff([("fmt ", Data(w.body("fmt ")!)), ("bext", Data(w.body("bext")!)), ("data", Data(w.body("data")!))])
    #expect(try WAVReader.parse(noIXML).juju == .valid(.init(jobID: jobA, takeID: takeJane0304, exportID: nil), source: .bextFallback))
}

@Test func exportNeverOverwritesAnExistingFile() throws {
    let dir = try tempDir()
    let (url, _, _) = try exportFixture(dir)
    let before = try Data(contentsOf: url)
    #expect(throws: BWFWriteError.destinationExists(url.path)) {
        _ = try exportFixture(dir, export: export2)
    }
    #expect(try Data(contentsOf: url) == before)
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix(".juju-tmp") }
    #expect(leftovers.isEmpty)
}

@Test func exportRequiresExportUUID() throws {
    let fmt = WAVFormat.canonicalChunk(sampleRate: 48_000, channels: 1, bitsPerSample: 16)
    #expect(throws: BWFWriteError.missingExportID) { _ = try BWFWriter.compose(formatChunk: fmt, audio: Data(count: 96), info: info(nil)) }
}

@Test func oddLengthChunksArePaddedAndExtensibleFormatPreserved() throws {
    // 8-bit mono, odd sample count → odd data chunk; WAVE_FORMAT_EXTENSIBLE header kept verbatim.
    var ext = Data()
    ext.appendLE(UInt16(0xFFFE)); ext.appendLE(UInt16(1)); ext.appendLE(UInt32(48_000)); ext.appendLE(UInt32(48_000))
    ext.appendLE(UInt16(1)); ext.appendLE(UInt16(8)); ext.appendLE(UInt16(22)); ext.appendLE(UInt16(8)); ext.appendLE(UInt32(4))
    ext.append(contentsOf: [0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71])
    let src = riff([("fmt ", ext), ("data", Data((0..<4_801).map { UInt8(truncatingIfNeeded: $0) }))])
    let dir = try tempDir()
    let (url, receipt, _) = try exportFixture(dir, source: src)
    let w = try IndependentWAV(try Data(contentsOf: url))   // strict: total size and padding must be exact
    #expect(w.body("fmt ").map { Data($0) } == ext)
    #expect(w.body("data")!.count == 4_801)
    #expect(receipt.format.formatTag == 0xFFFE && receipt.format.effectiveFormatTag == 1)
}

// MARK: - Fail-safe parsing

@Test func hugeChunkLengthFailsSafely() throws {
    var d = plainWAV()
    d.replaceSubrange(40..<44, with: [0xFF, 0xFF, 0xFF, 0x7F])   // data size → ~2 GB
    #expect(throws: WAVParseError.chunkOutOfBounds(id: "data", offset: 36, declaredSize: 0x7FFF_FFFF)) { try WAVReader.parse(d) }
}

@Test func truncatedAndNonWAVInputsFailSafely() throws {
    #expect(throws: WAVParseError.notRIFFWave) { try WAVReader.parse(Data("ID3 not a wav at all".utf8)) }
    #expect(throws: WAVParseError.notRIFFWave) { try WAVReader.parse(Data()) }
    let d = plainWAV()
    #expect(throws: (any Error).self) { try WAVReader.parse(d.prefix(30)) }
    #expect(throws: WAVParseError.missingAudio) { try WAVReader.parse(riff([("fmt ", WAVFormat.canonicalChunk(sampleRate: 48_000, channels: 1, bitsPerSample: 16))])) }
}

@Test func tooManyChunksFailsSafely() throws {
    let junk = Array(repeating: ("JUNK", Data()), count: 600)
    #expect(throws: WAVParseError.tooManyChunks) { try WAVReader.parse(riff(junk + [("fmt ", WAVFormat.canonicalChunk(sampleRate: 48_000, channels: 1, bitsPerSample: 16)), ("data", Data(count: 2))])) }
}

@Test func duplicateAudioChunkIsRejected() throws {
    let fmt = WAVFormat.canonicalChunk(sampleRate: 48_000, channels: 1, bitsPerSample: 16)
    #expect(throws: WAVParseError.duplicateChunk("data")) { try WAVReader.parse(riff([("fmt ", fmt), ("data", Data(count: 2)), ("data", Data(count: 2))])) }
}

private func withIXML(_ user: String, bext: BextChunk? = nil, ixmlCount: Int = 1) -> Data {
    let fmt = WAVFormat.canonicalChunk(sampleRate: 48_000, channels: 1, bitsPerSample: 16)
    let x = Data("<?xml version=\"1.0\"?><BWFXML><IXML_VERSION>2.10</IXML_VERSION><USER>\(user)</USER></BWFXML>".utf8)
    var chunks: [(String, Data)] = [("fmt ", fmt)]
    if let bext { chunks.append(("bext", try! bext.encoded())) }
    for _ in 0..<ixmlCount { chunks.append(("iXML", x)) }
    chunks.append(("data", Data(count: 96)))
    return riff(chunks)
}
private let goodUser = "JUJU_JOB_UUID=\(jobA.uuidString)\nJUJU_TAKE_UUID=\(takeJane0304.uuidString)\nJUJU_EXPORT_UUID=\(export1.uuidString)\nJUJU_METADATA_VERSION=1"

@Test func metadataProblemsAreReportedNotGuessed() throws {
    #expect(try WAVReader.parse(withIXML(goodUser)).juju.identifiers?.takeID == takeJane0304)   // upper-case UUIDs accepted
    if case .malformed = try WAVReader.parse(withIXML(goodUser.replacingOccurrences(of: takeJane0304.uuidString, with: "not-a-uuid"))).juju {} else { Issue.record("bad UUID") }
    #expect(try WAVReader.parse(withIXML(goodUser.replacingOccurrences(of: "VERSION=1", with: "VERSION=2"))).juju == .unsupportedVersion(2))
    if case .malformed = try WAVReader.parse(withIXML(goodUser.replacingOccurrences(of: "\nJUJU_METADATA_VERSION=1", with: ""))).juju {} else { Issue.record("missing version") }
    if case .conflicting = try WAVReader.parse(withIXML(goodUser + "\nJUJU_TAKE_UUID=\(export2.uuidString)")).juju {} else { Issue.record("repeated key") }
    if case .conflicting = try WAVReader.parse(withIXML(goodUser, ixmlCount: 2)).juju {} else { Issue.record("duplicate iXML") }
    let otherBext = BextChunk(description: BextJUJU.description(job: jobA, take: export2), originator: "x",
                              originatorReference: "", originationDate: "2026-10-28", originationTime: "12:00:00")
    if case .conflicting = try WAVReader.parse(withIXML(goodUser, bext: otherBext)).juju {} else { Issue.record("bext disagrees") }
    let badRef = BextChunk(description: "", originator: "x", originatorReference: "JUJU0000", originationDate: "2026-10-28", originationTime: "12:00:00")
    if case .malformed = try WAVReader.parse(withIXML("", bext: badRef)).juju {} else { Issue.record("bad originator ref") }
    #expect(try WAVReader.parse(withIXML("SOUND_DEVICES=1")).juju == .absent)   // other apps' USER data is ignored
}

// MARK: - Encodings

@Test func originatorReferenceRoundTripsAndRejectsJunk() {
    for _ in 0..<200 { let u = UUID(); #expect(JUJUOriginatorReference.decode(JUJUOriginatorReference.encode(u)) == u) }
    let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
    #expect(JUJUOriginatorReference.encode(zero) == "JUJU" + String(repeating: "A", count: 26))
    #expect(JUJUOriginatorReference.decode("JUJU" + String(repeating: "A", count: 25) + "B") == nil)  // non-zero pad bits
    #expect(JUJUOriginatorReference.decode("JUJU" + String(repeating: "A", count: 25) + "1") == nil)  // not base32
    #expect(JUJUOriginatorReference.decode(takeJane0304.uuidString) == nil)
}

@Test func sha256KnownVectors() {
    #expect(SHA256.hex(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    #expect(SHA256.hex(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    #expect(SHA256.hex(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)) == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    #expect(SHA256.hex(Data(repeating: 0x61, count: 1_000_000)) == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
}

@Test func ixmlEscapesJobNames() throws {
    let x = String(decoding: IXML.encode(.init(project: "Lenor <DE> & \"Co\"")), as: UTF8.self)
    #expect(x.contains("<PROJECT>Lenor &lt;DE&gt; &amp; &quot;Co&quot;</PROJECT>"))
    #expect(IXML.elements("PROJECT", in: x) == ["Lenor <DE> & \"Co\""])
}
