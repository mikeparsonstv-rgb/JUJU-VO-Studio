import Foundation

/// Everything needed to resume, edit or clone a job's setup. Stored as immutable, versioned JSON revisions.
public struct JobSettings: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public struct OutputFormat: Codable, Equatable, Sendable {
        public var sampleRate: Int = 48_000
        public var bitDepth: Int = 24
        public var channels: Int = 1
        /// JUJU never converts silently; a different delivery format would be a recorded derivative.
        public var conversionPolicy: String = "none-silent"
    }
    public var schemaVersion: Int = JobSettings.schemaVersion
    public var outputFormat = OutputFormat()
    public var languageTag: String?
    public var marketCountryCode: String?
    public var namingPattern: String = "<Job>-<Actor>-<YYYY-MM-DD>-<LineNN|FullRead>-<TakeNN>.wav"
    public var takeNumbering: String = "per job · actor · line"
    public var engineID: String?            // nil until a real actor engine exists (Stage 2)
    public var directionNotes: [String] = []
    public init() {}
}

enum JSON {
    static func encode<T: Encodable>(_ value: T) -> String {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return String(decoding: (try? e.encode(value)) ?? Data("{}".utf8), as: UTF8.self)
    }
    static func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try d.decode(type, from: Data(text.utf8))
    }
}

/// Resolved values recorded on each take. For Stage 1 there is no renderer: provenance says what the audio really is.
struct ResolvedTakeSettings: Codable, Equatable {
    var provenance: String                  // importedWAV | mockFixture | render
    var provenanceNote: String
    var actor: String
    var voiceMasterOrigin: String
    var renderer: String                    // "none" in Stage 1
    var job: JobSettings
    var sourceFileName: String?
    var audio: AudioFacts
    struct AudioFacts: Codable, Equatable {
        var sampleRate: Int; var bitsPerSample: Int; var channels: Int; var codec: String
        var duration: Double; var dataSHA256: String
    }
}
