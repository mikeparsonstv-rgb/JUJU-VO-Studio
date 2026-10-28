import Foundation

public struct ReferenceAssetMetadata: Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey {
        case assetID = "asset_id", displayName = "display_name", source, licence
        case redistributionPermitted = "redistribution_permitted", language
        case speakerDescription = "speaker_description", transcript
        case sampleRate = "sample_rate", channels, duration, notes, dateAdded = "date_added"
    }
    public var assetID, displayName, source, licence: String
    public var redistributionPermitted: Bool
    public var language, speakerDescription, transcript: String
    public var sampleRate, channels: Int
    public var duration: Double
    public var notes: String
    public var dateAdded: String

    public init(assetID: String, displayName: String, source: String, licence: String,
                redistributionPermitted: Bool, language: String, speakerDescription: String,
                transcript: String, sampleRate: Int, channels: Int, duration: Double,
                notes: String, dateAdded: String) {
        self.assetID = assetID; self.displayName = displayName; self.source = source; self.licence = licence
        self.redistributionPermitted = redistributionPermitted; self.language = language
        self.speakerDescription = speakerDescription; self.transcript = transcript
        self.sampleRate = sampleRate; self.channels = channels; self.duration = duration
        self.notes = notes; self.dateAdded = dateAdded
    }
}

public struct ReferenceAssetCatalogue: Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version", status, blocker, assets }
    public var schemaVersion: Int
    public var status, blocker: String
    public var assets: [ReferenceAssetMetadata]
}

public struct BenchmarkDefinition: Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", testID = "test_id", displayName = "display_name"
        case purpose, script, language, directionText = "direction_text"
        case referenceRequired = "reference_required", notes
    }
    public var schemaVersion: Int
    public var testID, displayName, purpose, script, language, directionText: String
    public var referenceRequired: Bool
    public var notes: String
}

public enum BenchCatalogError: Error, LocalizedError {
    case duplicateTestID(String)
    case missingDefinitions
    public var errorDescription: String? {
        switch self {
        case .duplicateTestID(let id): "Duplicate benchmark definition '\(id)'"
        case .missingDefinitions: "No benchmark definition JSON files were found"
        }
    }
}

public enum BenchCatalog {
    public static func loadDefinitions(from directory: URL) throws -> [BenchmarkDefinition] {
        let files = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil).filter { $0.pathExtension.lowercased() == "json" }.sorted { $0.path < $1.path }
        guard !files.isEmpty else { throw BenchCatalogError.missingDefinitions }
        let decoder = JSONDecoder()
        let definitions = try files.map { try decoder.decode(BenchmarkDefinition.self, from: Data(contentsOf: $0)) }
        var ids = Set<String>()
        for definition in definitions where !ids.insert(definition.testID).inserted {
            throw BenchCatalogError.duplicateTestID(definition.testID)
        }
        return definitions
    }
}
