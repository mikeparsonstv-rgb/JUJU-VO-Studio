import Foundation

/// EBU Tech 3285 v2 Broadcast Audio Extension chunk (602 fixed bytes + CodingHistory).
public struct BextChunk: Equatable, Sendable {
    public static let fixedSize = 602
    /// Loudness fields are written as "not measured" (0x7FFF); JUJU never claims a loudness it did not measure.
    public static let loudnessNotMeasured: Int16 = 0x7FFF

    public var description: String          // ≤ 256 ASCII
    public var originator: String           // ≤ 32 ASCII
    public var originatorReference: String  // ≤ 32 ASCII
    public var originationDate: String      // yyyy-MM-dd
    public var originationTime: String      // HH:mm:ss
    public var timeReference: UInt64       // samples since midnight; 0 for JUJU renders
    public var version: UInt16
    public var codingHistory: String

    public init(description: String, originator: String, originatorReference: String, originationDate: String,
                originationTime: String, timeReference: UInt64 = 0, version: UInt16 = 2, codingHistory: String = "") {
        self.description = description; self.originator = originator; self.originatorReference = originatorReference
        self.originationDate = originationDate; self.originationTime = originationTime
        self.timeReference = timeReference; self.version = version; self.codingHistory = codingHistory
    }

    public func encoded() throws -> Data {
        var d = Data()
        try d.appendFixedASCII(description, width: 256, field: "bext.Description")
        try d.appendFixedASCII(originator, width: 32, field: "bext.Originator")
        try d.appendFixedASCII(originatorReference, width: 32, field: "bext.OriginatorReference")
        try d.appendFixedASCII(originationDate, width: 10, field: "bext.OriginationDate")
        try d.appendFixedASCII(originationTime, width: 8, field: "bext.OriginationTime")
        d.appendLE(UInt32(truncatingIfNeeded: timeReference))
        d.appendLE(UInt32(truncatingIfNeeded: timeReference >> 32))
        d.appendLE(version)
        d.append(contentsOf: [UInt8](repeating: 0, count: 64))                // UMID: not used
        for _ in 0..<5 { d.appendLE(Self.loudnessNotMeasured) }              // loudness block
        d.append(contentsOf: [UInt8](repeating: 0, count: 180))               // reserved
        let history = Array(codingHistory.utf8)
        guard history.allSatisfy({ $0 < 0x80 }) else { throw BWFWriteError.nonASCII(field: "bext.CodingHistory") }
        d.append(contentsOf: history)
        assert(d.count == Self.fixedSize + history.count)
        return d
    }

    static func decode(_ body: Data) throws -> BextChunk {
        let b = body.zeroBased
        guard b.count >= fixedSize else { throw WAVParseError.invalidFormat("bext chunk shorter than 602 bytes") }
        let history = b[fixedSize...].prefix { $0 != 0 }
        return BextChunk(description: b.fixedASCII(0, width: 256), originator: b.fixedASCII(256, width: 32),
                         originatorReference: b.fixedASCII(288, width: 32), originationDate: b.fixedASCII(320, width: 10),
                         originationTime: b.fixedASCII(330, width: 8), timeReference: b.u64(338), version: b.u16(346),
                         codingHistory: String(decoding: history, as: UTF8.self))
    }
}
