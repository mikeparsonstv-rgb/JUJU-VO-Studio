import CryptoKit
import Foundation
import RendererBenchCore

public struct QualificationAsset: Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey {
        case id, role, sha256
        case conditioningAllowed = "conditioning_allowed"
        case externalBenchmark = "external_benchmark"
    }
    public let id, role, sha256: String
    public let conditioningAllowed, externalBenchmark: Bool
}

public struct QualificationTranscript: Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey { case id, path, sha256, status }
    public let id, path, sha256, status: String
}

public struct CrossHoldoutDirection: Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey {
        case id
        case conditioningAssetID = "conditioning_asset_id"
        case conditioningTranscriptID = "conditioning_transcript_id"
        case targetTranscriptID = "target_transcript_id"
        case groundTruthAssetID = "ground_truth_asset_id"
    }
    public let id, conditioningAssetID, conditioningTranscriptID: String
    public let targetTranscriptID, groundTruthAssetID: String
}

public struct QualificationManifest: Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", qualificationID = "qualification_id"
        case language, accent, domain
        case baselinePolicy = "baseline_policy", runsPerDirection = "runs_per_direction"
        case rendererIDs = "renderer_ids", transcripts, assets, directions
        case aggregateWinner = "aggregate_winner"
    }
    public let schemaVersion: Int
    public let qualificationID, language, accent, domain, baselinePolicy: String
    public let runsPerDirection: Int
    public let rendererIDs: [String]
    public let transcripts: [QualificationTranscript]
    public let assets: [QualificationAsset]
    public let directions: [CrossHoldoutDirection]
    public let aggregateWinner: String?

    public static func load(from url: URL) throws -> Self {
        try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    public func validate() throws {
        guard schemaVersion == 1, runsPerDirection == 3,
              rendererIDs == ["qwen3", "voxcpm2", "chatterbox"],
              baselinePolicy == "untuned_renderer_native_baseline",
              aggregateWinner == nil else { throw QualificationError.invalidPolicy }
        let assetMap = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        let transcriptIDs = Set(transcripts.map(\.id))
        guard directions.count == 2, Set(directions.map(\.id)).count == 2 else {
            throw QualificationError.invalidDirections
        }
        for direction in directions {
            guard direction.conditioningAssetID != direction.groundTruthAssetID,
                  assetMap[direction.conditioningAssetID]?.conditioningAllowed == true,
                  assetMap[direction.groundTruthAssetID]?.role == "human_reference",
                  transcriptIDs.contains(direction.conditioningTranscriptID),
                  transcriptIDs.contains(direction.targetTranscriptID) else {
                throw QualificationError.dataLeakage(direction.id)
            }
        }
    }
}

public enum MeasurementState: String, Codable, Equatable, Sendable { case available, unavailable }

public struct MeasurementAvailability: Codable, Equatable, Sendable {
    public let state: MeasurementState
    public let reason: String?
    public init(state: MeasurementState, reason: String? = nil) {
        self.state = state; self.reason = reason
    }
}

public struct AuditionCopyMetadata: Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey { case sourceSHA256 = "source_sha256", outputPath = "output_path", appliedGainDB = "applied_gain_db" }
    public let sourceSHA256, outputPath: String
    public let appliedGainDB: Double
}

public enum QualificationError: Error, LocalizedError {
    case invalidPolicy, invalidDirections, dataLeakage(String), hashMismatch(String), missingMapping(String)
    public var errorDescription: String? {
        switch self {
        case .invalidPolicy: "Qualification must remain an untuned three-run, three-renderer baseline with no aggregate winner"
        case .invalidDirections: "Exactly two distinct cross-holdout directions are required"
        case .dataLeakage(let id): "Cross-holdout direction \(id) permits conditioning/ground-truth leakage"
        case .hashMismatch(let id): "SHA-256 mismatch for \(id)"
        case .missingMapping(let id): "Missing local asset mapping for \(id)"
        }
    }
}

public enum QualificationProvenance {
    public static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hasher.update(data: data) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func verify(manifest: QualificationManifest, localAssets: [String: String], root: URL) throws {
        for asset in manifest.assets {
            guard let raw = localAssets[asset.id] else { throw QualificationError.missingMapping(asset.id) }
            let url = URL(fileURLWithPath: raw, relativeTo: root).standardizedFileURL
            guard try sha256(url) == asset.sha256 else { throw QualificationError.hashMismatch(asset.id) }
        }
        for transcript in manifest.transcripts {
            let url = URL(fileURLWithPath: transcript.path, relativeTo: root).standardizedFileURL
            guard try sha256(url) == transcript.sha256 else { throw QualificationError.hashMismatch(transcript.id) }
        }
    }
}
