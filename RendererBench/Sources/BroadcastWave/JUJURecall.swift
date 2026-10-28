import Foundation

/// The immutable lookup keys every JUJU-exported WAV carries (Build 01 brief §7A.1).
/// They are lookup keys only — not proof of ownership, never a trigger for any automatic action.
public struct JUJURecallIdentifiers: Equatable, Hashable, Sendable, Codable {
    public static let currentMetadataVersion = 1
    public let jobID: UUID
    public let takeID: UUID
    /// Nil only when recovered from the bext fallback, which carries job + take but not the export.
    public let exportID: UUID?
    public let metadataVersion: Int

    public init(jobID: UUID, takeID: UUID, exportID: UUID?, metadataVersion: Int = currentMetadataVersion) {
        self.jobID = jobID; self.takeID = takeID; self.exportID = exportID; self.metadataVersion = metadataVersion
    }
}

/// What a WAV says about its JUJU origin. Audio stays readable in every case.
public enum JUJUMetadata: Equatable, Sendable {
    public enum Source: String, Sendable { case ixml, bextFallback }
    case absent
    case valid(JUJURecallIdentifiers, source: Source)
    case unsupportedVersion(Int)
    case malformed(String)
    case conflicting(String)

    public var identifiers: JUJURecallIdentifiers? {
        if case .valid(let ids, _) = self { return ids } else { return nil }
    }

    public enum Key {
        public static let job = "JUJU_JOB_UUID"
        public static let take = "JUJU_TAKE_UUID"
        public static let export = "JUJU_EXPORT_UUID"
        public static let version = "JUJU_METADATA_VERSION"
    }

    /// Canonical source is iXML USER; bext Description and OriginatorReference are redundant cross-checks.
    static func extract(ixml: String?, bext: BextChunk?) -> JUJUMetadata {
        let bextIDs = bext.flatMap { BextJUJU.parseDescription($0.description) }
        let refTake = bext.flatMap { JUJUOriginatorReference.decode($0.originatorReference) }
        let refIsJUJU = bext.map { JUJUOriginatorReference.looksLikeJUJU($0.originatorReference) } ?? false
        if refIsJUJU && refTake == nil { return .malformed("bext OriginatorReference is not a valid JUJU take reference") }

        let pairs = ixml.map { IXML.elements("USER", in: $0).flatMap(IXML.userPairs) } ?? []
        let jujuPairs = pairs.filter { $0.key.hasPrefix("JUJU_") }

        if !jujuPairs.isEmpty {
            var values: [String: String] = [:]
            for p in jujuPairs {
                if let existing = values[p.key], existing != p.value { return .conflicting("iXML repeats \(p.key) with different values") }
                values[p.key] = p.value
            }
            guard let vText = values[Key.version] else { return .malformed("iXML has JUJU fields but no \(Key.version)") }
            guard let version = Int(vText), version > 0 else { return .malformed("\(Key.version) '\(vText)' is not a version number") }
            guard version == JUJURecallIdentifiers.currentMetadataVersion else { return .unsupportedVersion(version) }
            guard let jText = values[Key.job], let job = strictUUID(jText) else { return .malformed("missing or invalid \(Key.job)") }
            guard let tText = values[Key.take], let take = strictUUID(tText) else { return .malformed("missing or invalid \(Key.take)") }
            var export: UUID?
            if let eText = values[Key.export] {
                guard let e = strictUUID(eText) else { return .malformed("invalid \(Key.export)") }
                export = e
            }
            if export == take || export == job { return .malformed("export UUID repeats the job or take UUID") }
            if let b = bextIDs, b.job != job || b.take != take { return .conflicting("bext Description disagrees with iXML") }
            if let r = refTake, r != take { return .conflicting("bext OriginatorReference disagrees with iXML take") }
            return .valid(.init(jobID: job, takeID: take, exportID: export, metadataVersion: version), source: .ixml)
        }

        if let b = bextIDs {
            if let r = refTake, r != b.take { return .conflicting("bext OriginatorReference disagrees with bext Description") }
            return .valid(.init(jobID: b.job, takeID: b.take, exportID: nil), source: .bextFallback)
        }
        if bext?.description.hasPrefix(BextJUJU.prefix) == true { return .malformed("bext Description has an unreadable JUJU line") }
        return .absent
    }

    /// Accepts only the canonical 8-4-4-4-12 hex form (any case). Foundation's parser is lenient about little else, but be explicit.
    static func strictUUID(_ s: String) -> UUID? {
        guard s.count == 36 else { return nil }
        return UUID(uuidString: s)
    }
}

/// `bext.Description` fallback line: `JUJU job=<uuid>; take=<uuid>` (88 ASCII chars, fits the 256-char field).
public enum BextJUJU {
    public static let prefix = "JUJU job="
    public static func description(job: UUID, take: UUID) -> String {
        "JUJU job=\(job.uuidString.lowercased()); take=\(take.uuidString.lowercased())"
    }
    static func parseDescription(_ text: String) -> (job: UUID, take: UUID)? {
        guard text.hasPrefix(prefix) else { return nil }
        let parts = text.dropFirst(5).split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, parts[0].hasPrefix("job="), parts[1].hasPrefix("take="),
              let job = JUJUMetadata.strictUUID(String(parts[0].dropFirst(4))),
              let take = JUJUMetadata.strictUUID(String(parts[1].dropFirst(5))) else { return nil }
        return (job, take)
    }
}

/// `bext.OriginatorReference` (32 ASCII max): "JUJU" + RFC 4648 base32 (no padding) of the 16 take-UUID bytes
/// = 4 + 26 = 30 characters. Reversible and documented; never a truncated or hyphenated UUID.
public enum JUJUOriginatorReference {
    static let tag = "JUJU"
    static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".utf8)

    public static func encode(_ id: UUID) -> String {
        let u = id.uuid
        let bytes = [u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7, u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15]
        var out: [UInt8] = [], buffer: UInt32 = 0, bits = 0
        for b in bytes {
            buffer = buffer << 8 | UInt32(b); bits += 8
            while bits >= 5 { bits -= 5; out.append(alphabet[Int(buffer >> UInt32(bits) & 31)]) }
        }
        if bits > 0 { out.append(alphabet[Int(buffer << UInt32(5 - bits) & 31)]) }
        return tag + String(decoding: out, as: UTF8.self)
    }

    static func looksLikeJUJU(_ s: String) -> Bool { s.hasPrefix(tag) }

    public static func decode(_ s: String) -> UUID? {
        guard s.count == 30, s.hasPrefix(tag) else { return nil }
        var bytes: [UInt8] = [], buffer: UInt32 = 0, bits = 0
        for c in s.utf8.dropFirst(4) {
            guard let v = alphabet.firstIndex(of: c) else { return nil }
            buffer = buffer << 5 | UInt32(v); bits += 5
            if bits >= 8 { bits -= 8; bytes.append(UInt8(truncatingIfNeeded: buffer >> UInt32(bits))) }
        }
        guard bytes.count == 16, buffer & ((1 << UInt32(bits)) - 1) == 0 else { return nil } // pad bits must be zero
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
