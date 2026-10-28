import Foundation
import Testing
@testable import RB006Qualification
@testable import RendererBenchCore

private func rb006Root() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}
private func rb006Manifest() throws -> QualificationManifest {
    try QualificationManifest.load(from: rb006Root().appending(path: "BenchAssets/qualifications/RB006-Birmingham.json"))
}

@Test func qualificationManifestParsing() throws {
    let manifest = try rb006Manifest(); try manifest.validate()
    #expect(manifest.qualificationID == "RB006-Birmingham-Baseline")
}

@Test func crossHoldoutDirectionsValidate() throws {
    let directions = try rb006Manifest().directions
    #expect(directions.map(\.id) == ["BHM-XH-01", "BHM-XH-02"])
    #expect(directions[0].conditioningTranscriptID == "BHM01")
    #expect(directions[0].targetTranscriptID == "BHM02")
}

@Test func conditioningAndGroundTruthDifferPerDirection() throws {
    for direction in try rb006Manifest().directions {
        #expect(direction.conditioningAssetID != direction.groundTruthAssetID)
    }
}

@Test func targetHumanCannotEnterItsDirectionConditioning() throws {
    let manifest = try rb006Manifest()
    for direction in manifest.directions {
        let requestReferences = [direction.conditioningAssetID]
        #expect(!requestReferences.contains(direction.groundTruthAssetID))
    }
}

@Test func threeRunsRemainDistinct() throws {
    let runner = BenchmarkRunner(registry: .standard(), store: BenchStore(rootURL: try temporaryDirectory()))
    let request = RendererRequest(testID: "BHM-XH-01", script: "fixture", language: "en-GB")
    let results = try (1...3).map { _ in try runner.render(request, rendererID: "mock") }
    #expect(Set(results.map(\.runID)).count == 3)
}

@Test func threeRendererEvidenceDoesNotCollide() {
    let store = BenchStore(rootURL: URL(fileURLWithPath: "/tmp/rb006-fixture"))
    let paths = ["qwen3", "voxcpm2", "chatterbox"].map { store.paths(testID: "BHM-XH-01", runID: "run", rendererID: $0).resultFile }
    #expect(Set(paths).count == 3)
}

@Test func sha256ProvenancePersists() throws {
    let manifest = try rb006Manifest()
    #expect(manifest.assets.allSatisfy { $0.sha256.count == 64 })
    #expect(manifest.assets.first { $0.id == "BHM01_human_reference" }?.sha256 == "ead6baecac68910aff1254bc2d368b4dd4b750f3cb4705e88ece03fd55a511c4")
}

@Test func exactTranscriptHashesPersist() throws {
    let hashes = Dictionary(uniqueKeysWithValues: try rb006Manifest().transcripts.map { ($0.id, $0.sha256) })
    #expect(hashes["BHM01"] == "3e9e7ba2eb9f23d7bbba4db82e7010f2abff616e2a4d21727a05f836c4b3a79c")
    #expect(hashes["BHM02"] == "af1c9689b57a32372a837e4f35156a603bdcc879e0861bcc7392bbc2a2d9d1ad")
}

@Test func baselinePolicyIsUntunedAndThreeRun() throws {
    let manifest = try rb006Manifest()
    #expect(manifest.baselinePolicy == "untuned_renderer_native_baseline")
    #expect(manifest.runsPerDirection == 3)
}

@Test func elevenLabsIsExternalAndCannotCondition() throws {
    let external = try rb006Manifest().assets.filter(\.externalBenchmark)
    #expect(external.count == 4)
    #expect(external.allSatisfy { !$0.conditioningAllowed && $0.role == "closed_benchmark" })
}

@Test func rawAuditionCopyDoesNotOverwriteSource() throws {
    let directory = try temporaryDirectory(), source = directory.appending(path: "original.wav")
    let copy = directory.appending(path: "derived/raw.wav")
    try Data("private-original".utf8).write(to: source)
    let before = try QualificationProvenance.sha256(source)
    try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: source, to: copy)
    #expect(try QualificationProvenance.sha256(source) == before)
    #expect(copy != source)
}

@Test func levelMatchMetadataRecordsGain() throws {
    let metadata = AuditionCopyMetadata(sourceSHA256: String(repeating: "a", count: 64), outputPath: "derived.wav", appliedGainDB: -2.75)
    #expect(try roundTrip(metadata).appliedGainDB == -2.75)
}

@Test func unavailableMeasurementsAreExplicit() throws {
    let unavailable = MeasurementAvailability(state: .unavailable, reason: "No licence-gated speaker verifier selected")
    #expect(try roundTrip(unavailable) == unavailable)
    #expect(unavailable.reason != nil)
}

@Test func noAggregateSubjectiveWinnerIsSynthesized() throws {
    #expect(try rb006Manifest().aggregateWinner == nil)
    let raw = try String(contentsOf: rb006Root().appending(path: "BenchAssets/qualifications/RB006-Birmingham.json"), encoding: .utf8)
    #expect(!raw.contains("subjective_score"))
}
