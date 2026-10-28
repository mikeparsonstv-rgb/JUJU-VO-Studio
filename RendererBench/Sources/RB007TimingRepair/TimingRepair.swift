import Foundation

public struct PerformedSpan: Codable, Equatable, Sendable {
    public let sourceDurationSeconds: Double
    public let firstSpeechOnsetSeconds: Double
    public let lastSpeechOffsetSeconds: Double
    public let performedSpanSeconds: Double
    public let activeSpeechSeconds: Double
    public let internalPauseSeconds: Double
    public let internalPauseProportion: Double
    public let method: String

    public init(sourceDurationSeconds: Double, firstSpeechOnsetSeconds: Double,
                lastSpeechOffsetSeconds: Double, performedSpanSeconds: Double,
                activeSpeechSeconds: Double, internalPauseSeconds: Double,
                internalPauseProportion: Double, method: String) {
        self.sourceDurationSeconds = sourceDurationSeconds
        self.firstSpeechOnsetSeconds = firstSpeechOnsetSeconds
        self.lastSpeechOffsetSeconds = lastSpeechOffsetSeconds
        self.performedSpanSeconds = performedSpanSeconds
        self.activeSpeechSeconds = activeSpeechSeconds
        self.internalPauseSeconds = internalPauseSeconds
        self.internalPauseProportion = internalPauseProportion
        self.method = method
    }
}

public enum PerformedSpanMeasurement {
    public static let methodVersion = "frame_peak_relative_threshold_v1"

    public static func measure(samples: [Float], sampleRate: Int, frameLength: Int = 2_048,
                               hopLength: Int = 512, topDB: Double = 35) -> PerformedSpan? {
        guard !samples.isEmpty, sampleRate > 0, frameLength > 0, hopLength > 0 else { return nil }
        let peak = samples.map { abs(Double($0)) }.max() ?? 0
        guard peak > 0 else { return nil }
        let threshold = peak * pow(10, -topDB / 20)
        var activeFrames: [(start: Int, end: Int)] = []
        var start = 0
        while start < samples.count {
            let end = min(samples.count, start + frameLength)
            let active = samples[start..<end].contains { abs(Double($0)) >= threshold }
            if active { activeFrames.append((start, end)) }
            start += hopLength
        }
        guard let first = activeFrames.first, let last = activeFrames.last else { return nil }
        var merged: [(Int, Int)] = []
        for interval in activeFrames {
            if let prior = merged.last, interval.start <= prior.1 {
                merged[merged.count - 1].1 = max(prior.1, interval.end)
            } else {
                merged.append((interval.start, interval.end))
            }
        }
        let activeSamples = merged.reduce(0) { $0 + $1.1 - $1.0 }
        let spanSamples = last.end - first.start
        let active = Double(activeSamples) / Double(sampleRate)
        let span = Double(spanSamples) / Double(sampleRate)
        let internalPause = max(0, span - active)
        return PerformedSpan(
            sourceDurationSeconds: Double(samples.count) / Double(sampleRate),
            firstSpeechOnsetSeconds: Double(first.start) / Double(sampleRate),
            lastSpeechOffsetSeconds: Double(last.end) / Double(sampleRate),
            performedSpanSeconds: span,
            activeSpeechSeconds: active,
            internalPauseSeconds: internalPause,
            internalPauseProportion: span > 0 ? internalPause / span : 0,
            method: methodVersion
        )
    }
}

public struct TimingRepairPlan: Codable, Equatable, Sendable {
    public static let minimumTimeScale = 0.85
    public static let maximumTimeScale = 1.20
    public let originalPerformedSpanSeconds: Double
    public let oracleTargetPerformedSpanSeconds: Double
    public let timeScale: Double
    public let eligible: Bool
    public let exclusionReason: String?

    public init(originalPerformedSpanSeconds: Double, oracleTargetPerformedSpanSeconds: Double,
                transcriptCoverage: Double, completenessThreshold: Double = 0.80) {
        self.originalPerformedSpanSeconds = originalPerformedSpanSeconds
        self.oracleTargetPerformedSpanSeconds = oracleTargetPerformedSpanSeconds
        timeScale = oracleTargetPerformedSpanSeconds / originalPerformedSpanSeconds
        if transcriptCoverage < completenessThreshold {
            eligible = false
            exclusionReason = "ineligible_for_timing_repair: transcript coverage below threshold"
        } else if !(Self.minimumTimeScale...Self.maximumTimeScale).contains(timeScale) {
            eligible = false
            exclusionReason = "timing_repair_out_of_range"
        } else {
            eligible = true
            exclusionReason = nil
        }
    }
}

public struct TimingRepairProvenance: Codable, Equatable, Sendable {
    public let sourceMilestone: String
    public let sourceRunID: String?
    public let sourceResultPath: String?
    public let sourceSHA256: String
    public let targetSourceLabel: String
    public let targetHumanAssetID: String
    public let algorithm: String

    public init(sourceMilestone: String = "RB-006", sourceRunID: String?, sourceResultPath: String?,
                sourceSHA256: String, targetSourceLabel: String = "oracle_target_performed_span",
                targetHumanAssetID: String, algorithm: String = "AVAudioUnitTimePitch") {
        self.sourceMilestone = sourceMilestone
        self.sourceRunID = sourceRunID
        self.sourceResultPath = sourceResultPath
        self.sourceSHA256 = sourceSHA256
        self.targetSourceLabel = targetSourceLabel
        self.targetHumanAssetID = targetHumanAssetID
        self.algorithm = algorithm
    }
}

public struct ListeningPair: Codable, Equatable, Sendable {
    public let label: String
    public let originalPath: String
    public let repairedPath: String
    public let sourceRunID: String?

    public init(label: String, originalPath: String, repairedPath: String, sourceRunID: String?) {
        self.label = label
        self.originalPath = originalPath
        self.repairedPath = repairedPath
        self.sourceRunID = sourceRunID
    }
}
