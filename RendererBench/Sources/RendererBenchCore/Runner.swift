import Foundation

public enum BenchmarkRunnerError: Error, LocalizedError {
    case unknownRenderer(String)
    public var errorDescription: String? { switch self { case .unknownRenderer(let id): "Unknown renderer '\(id)'" } }
}

public struct BenchmarkRunner: Sendable {
    public let registry: RendererRegistry
    public let store: BenchStore
    public init(registry: RendererRegistry, store: BenchStore) { self.registry = registry; self.store = store }

    @discardableResult
    public func render(_ request: RendererRequest, rendererID: String,
                       runID: String = UUID().uuidString.lowercased()) throws -> RendererResult {
        guard let adapter = registry.adapter(id: rendererID) else { throw BenchmarkRunnerError.unknownRenderer(rendererID) }
        let descriptor = adapter.descriptor
        let paths = store.paths(testID: request.testID, runID: runID, rendererID: rendererID)
        try store.prepare(paths); try store.write(request, to: paths.requestFile)
        let started = Date(); var audio: RenderedAudio?; var errorMessage: String?
        var rendererEnvironment: [String: String] = [:]
        do {
            let rendered = try adapter.render(request, to: paths.outputAudioFile)
            rendererEnvironment = rendered.environmentSnapshot
            let validated = try AudioFileValidator.validateWAV(at: paths.outputAudioFile,
                                                                reportedDuration: rendered.duration)
            audio = RenderedAudio(duration: validated.duration,
                                  firstAudioLatency: rendered.firstAudioLatency,
                                  environmentSnapshot: rendered.environmentSnapshot.merging([
                                    "output_sample_rate": String(validated.sampleRate),
                                    "output_channels": String(validated.channels)
                                  ]) { current, _ in current })
            rendererEnvironment = audio?.environmentSnapshot ?? rendererEnvironment
        }
        catch {
            errorMessage = error.localizedDescription
            if let failure = error as? any RendererFailureMetadata {
                rendererEnvironment.merge(failure.environmentSnapshot) { _, failureValue in failureValue }
            }
        }
        let completed = Date(), elapsed = max(completed.timeIntervalSince(started), 0)
        let result = RendererResult(
            schemaVersion: 1, runID: runID, testID: request.testID, rendererID: descriptor.id,
            rendererVersion: descriptor.rendererVersion, modelCheckpoint: descriptor.modelCheckpoint,
            settingsSnapshot: request.rendererSettings, descriptorSnapshot: descriptor,
            capabilitySnapshot: descriptor.capabilities, outputAudioPath: audio == nil ? nil : paths.outputAudioFile.path,
            outputDuration: audio?.duration, renderStartedAt: started, renderCompletedAt: completed,
            renderTime: elapsed, firstAudioLatency: audio?.firstAudioLatency,
            realtimeFactor: audio.flatMap { $0.duration > 0 ? elapsed / $0.duration : nil },
            success: errorMessage == nil, error: errorMessage,
            environmentSnapshot: Self.environment().merging(rendererEnvironment) { _, renderer in renderer })
        try store.write(result, to: paths.resultFile)
        return result
    }
    private static func environment() -> [String: String] {
        let info = ProcessInfo.processInfo
        return ["operating_system": info.operatingSystemVersionString,
                "processor_count": String(info.processorCount), "host_name": info.hostName]
    }
}
