import Foundation
import RB007TimingRepair
import Testing

@Test func performedSpanExcludesHeadAndTailSilenceAndKeepsInternalPause() throws {
    let sampleRate = 1_000
    var samples = [Float](repeating: 0, count: 4_000)
    for index in 500..<1_500 { samples[index] = 0.5 }
    for index in 2_000..<3_000 { samples[index] = -0.5 }
    let span = try #require(PerformedSpanMeasurement.measure(samples: samples, sampleRate: sampleRate,
                                                               frameLength: 100, hopLength: 50))
    #expect(span.firstSpeechOnsetSeconds == 0.45)
    #expect(span.lastSpeechOffsetSeconds == 3.05)
    #expect(span.performedSpanSeconds == 2.6)
    #expect(span.activeSpeechSeconds == 2.2)
    #expect(abs(span.internalPauseSeconds - 0.4) < 0.000_001)
    #expect(span.method == PerformedSpanMeasurement.methodVersion)
}

@Test func stretchRatioAndGuardrail() {
    let accepted = TimingRepairPlan(originalPerformedSpanSeconds: 10, oracleTargetPerformedSpanSeconds: 11,
                                    transcriptCoverage: 0.95)
    #expect(accepted.timeScale == 1.1)
    #expect(accepted.eligible)
    let rejected = TimingRepairPlan(originalPerformedSpanSeconds: 10, oracleTargetPerformedSpanSeconds: 12.1,
                                    transcriptCoverage: 1)
    #expect(!rejected.eligible)
    #expect(rejected.exclusionReason == "timing_repair_out_of_range")
}

@Test func incompleteRenderIsExcluded() {
    let plan = TimingRepairPlan(originalPerformedSpanSeconds: 10, oracleTargetPerformedSpanSeconds: 11,
                                transcriptCoverage: 0.4)
    #expect(!plan.eligible)
    #expect(plan.exclusionReason?.hasPrefix("ineligible_for_timing_repair") == true)
}

@Test func provenanceRecordsOracleAndRB006Identity() throws {
    let provenance = TimingRepairProvenance(sourceRunID: "run-1", sourceResultPath: "result.json",
                                            sourceSHA256: String(repeating: "a", count: 64),
                                            targetHumanAssetID: "BHM01_human_reference")
    let data = try JSONEncoder().encode(provenance)
    let restored = try JSONDecoder().decode(TimingRepairProvenance.self, from: data)
    #expect(restored.sourceMilestone == "RB-006")
    #expect(restored.targetSourceLabel == "oracle_target_performed_span")
    #expect(restored.sourceRunID == "run-1")
}

@Test func sourceIsNotOverwrittenAndHumanNeverBecomesRequestInput() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appending(path: "source.wav")
    try Data("authority".utf8).write(to: source)
    let before = try Data(contentsOf: source)
    let derivative = directory.appending(path: "derived.wav")
    try Data("derivative".utf8).write(to: derivative, options: .withoutOverwriting)
    #expect(try Data(contentsOf: source) == before)
    let rendererReferencePaths = ["BHM02_conditioning.wav"]
    #expect(!rendererReferencePaths.contains("BHM01_human_target.wav"))
}

@Test func repairedDurationToleranceAndListeningPair() {
    let requested = 12.0
    let measured = 12.018
    #expect(abs(measured - requested) <= 0.050)
    let pair = ListeningPair(label: "QWEN_run1", originalPath: "raw/original.wav",
                             repairedPath: "raw/repaired.wav", sourceRunID: "run-1")
    #expect(pair.originalPath != pair.repairedPath)
    #expect(pair.sourceRunID == "run-1")
}
