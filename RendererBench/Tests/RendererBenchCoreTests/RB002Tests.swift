import Foundation
import Testing
@testable import RendererBenchCore
@testable import Qwen3RendererAdapter

private struct FakeQwenClient: QwenWorkerClient {
    enum Behavior: Sendable { case healthy, unavailable, renderSuccess, renderFailure }
    let behavior: Behavior

    func send(_ request: QwenWorkerRequest) throws -> QwenWorkerResponse {
        switch behavior {
        case .healthy:
            return QwenWorkerResponse(requestID: request.requestID, success: true,
                packageVersions: ["qwen-tts": "test"], pythonVersion: "3.12", device: "cpu",
                modelAvailable: true, tokenizerAvailable: true, renderAttemptable: true)
        case .unavailable:
            return QwenWorkerResponse(requestID: request.requestID, success: true,
                error: "pinned assets absent", packageVersions: ["qwen-tts": "test"],
                pythonVersion: "3.12", device: "mps", modelAvailable: false,
                tokenizerAvailable: false, renderAttemptable: false)
        case .renderSuccess:
            guard let path = request.outputAudio else { throw CocoaError(.fileNoSuchFile) }
            _ = try MockRendererAdapter().render(
                RendererRequest(testID: "fixture", script: "fixture", language: "en-GB"),
                to: URL(fileURLWithPath: path))
            return QwenWorkerResponse(requestID: request.requestID, success: true,
                outputAudio: path, sampleRate: 48_000, durationSeconds: 1,
                packageVersions: ["qwen-tts": "0.1.1", "torch": "test"],
                pythonVersion: "3.12", osVersion: "macOS test", machineArchitecture: "arm64",
                device: "cpu", modelLoadSeconds: 0.2, generationSeconds: 0.3,
                modelAvailable: true, tokenizerAvailable: true, renderAttemptable: true)
        case .renderFailure:
            return QwenWorkerResponse(requestID: request.requestID, success: false,
                error: "synthetic generation failure", packageVersions: ["qwen-tts": "0.1.1"],
                pythonVersion: "3.12", device: "cpu", modelAvailable: true,
                tokenizerAvailable: true, renderAttemptable: true)
        }
    }
}

private enum InvalidOutputBehavior: Sendable { case missing, empty, invalid, zeroDuration }

private struct InvalidOutputAdapter: RendererAdapter {
    let behavior: InvalidOutputBehavior
    var descriptor: RendererDescriptor {
        RendererDescriptor(id: "invalid-fixture", displayName: "Invalid Fixture", location: .local,
            availability: .available, rendererVersion: "1", capabilities: RendererCapabilities(local: true),
            isTestFixture: true)
    }
    func healthCheck() -> RendererHealth { RendererHealth(status: .healthy, message: "fixture") }
    func render(_ request: RendererRequest, to outputURL: URL) throws -> RenderedAudio {
        switch behavior {
        case .missing: break
        case .empty: try Data().write(to: outputURL)
        case .invalid: try Data("not audio".utf8).write(to: outputURL)
        case .zeroDuration:
            _ = try MockRendererAdapter().render(request, to: outputURL)
            return RenderedAudio(duration: 0)
        }
        return RenderedAudio(duration: 1)
    }
}

private func qwenRequest(testID: String = "C01") throws -> RendererRequest {
    let reference = try temporaryDirectory().appending(path: "reference.wav")
    try Data([1]).write(to: reference)
    return RendererRequest(testID: testID, script: "A neutral clone test.", language: "en-GB",
                           referenceAudioPaths: [reference.path],
                           referenceAudioTranscripts: ["Reference transcript."])
}

private func qwenRunner(behavior: FakeQwenClient.Behavior, root: URL) -> BenchmarkRunner {
    let adapter = Qwen3RendererAdapter(client: FakeQwenClient(behavior: behavior), availabilityOverride: .available)
    return BenchmarkRunner(registry: .standard(overrides: [adapter]), store: BenchStore(rootURL: root))
}

@Test func qwenWorkerRequestEncoding() throws {
    let request = QwenWorkerRequest(operation: .render, requestID: "request-1", text: "Hello",
                                    language: "English", referenceAudio: "/tmp/reference.wav",
                                    referenceText: "Reference", outputAudio: "/tmp/output.wav")
    let encoder = JSONEncoder()
    let object = try #require(JSONSerialization.jsonObject(with: encoder.encode(request)) as? [String: Any])
    #expect(object["protocol_version"] as? Int == 1)
    #expect(object["operation"] as? String == "render")
    #expect(object["model_id"] as? String == Qwen3Constants.modelID)
    #expect(object["reference_audio"] as? String == "/tmp/reference.wav")
}

@Test func qwenWorkerResponseDecoding() throws {
    let json = """
    {"protocol_version":1,"request_id":"r","success":true,"output_audio":"/tmp/o.wav",
    "sample_rate":24000,"duration_seconds":2.5,"model_id":"\(Qwen3Constants.modelID)",
    "model_revision":"\(Qwen3Constants.modelRevision)","tokenizer_id":"\(Qwen3Constants.tokenizerID)",
    "tokenizer_revision":"\(Qwen3Constants.tokenizerRevision)","package_versions":{"torch":"2"},
    "python_version":"3.12","os_version":"macOS","machine_architecture":"arm64","device":"mps",
    "worker_startup_seconds":0.1,"model_load_seconds":1.2,"generation_seconds":3.4,
    "peak_resident_memory_bytes":42,"model_available":true,"tokenizer_available":true,
    "render_attemptable":true,"warnings":[]}
    """
    let decoder = JSONDecoder()
    let response = try decoder.decode(QwenWorkerResponse.self, from: Data(json.utf8))
    #expect(response.success)
    #expect(response.sampleRate == 24_000)
    #expect(response.modelLoadSeconds == 1.2)
    #expect(response.peakResidentMemoryBytes == 42)
}

@Test func qwenUnavailableHealthState() {
    let adapter = Qwen3RendererAdapter(client: FakeQwenClient(behavior: .unavailable), availabilityOverride: .available)
    let health = adapter.healthCheck()
    #expect(health.status == .unavailable)
    #expect(health.details["model_available"] == "false")
    #expect(health.details["compute_device"] == "mps")
}

@Test func qwenSuccessMapsToPersistedResult() throws {
    let root = try temporaryDirectory()
    let result = try qwenRunner(behavior: .renderSuccess, root: root).render(try qwenRequest(), rendererID: "qwen3", runID: "success")
    #expect(result.success)
    #expect(result.outputDuration == 1)
    #expect(result.environmentSnapshot["package_qwen-tts"] == "0.1.1")
    #expect(result.environmentSnapshot["output_sample_rate"] == "48000")
}

@Test func qwenFailureMapsToPersistedResult() throws {
    let root = try temporaryDirectory()
    let runner = qwenRunner(behavior: .renderFailure, root: root)
    let result = try runner.render(try qwenRequest(), rendererID: "qwen3", runID: "failure")
    #expect(!result.success)
    #expect(result.error?.contains("synthetic generation failure") == true)
    #expect(result.environmentSnapshot["qwen_model_revision"] == Qwen3Constants.modelRevision)
    let paths = runner.store.paths(testID: "C01", runID: "failure", rendererID: "qwen3")
    #expect(FileManager.default.fileExists(atPath: paths.resultFile.path))
}

@Test(arguments: [
    (InvalidOutputBehavior.missing, "did not create"),
    (InvalidOutputBehavior.empty, "empty"),
    (InvalidOutputBehavior.invalid, "not a readable"),
    (InvalidOutputBehavior.zeroDuration, "zero or nonsensical")
])
private func invalidSuccessfulOutputIsRejected(behavior: InvalidOutputBehavior, expectedError: String) throws {
    let adapter = InvalidOutputAdapter(behavior: behavior)
    let runner = BenchmarkRunner(registry: RendererRegistry(adapters: [adapter]),
                                 store: BenchStore(rootURL: try temporaryDirectory()))
    let result = try runner.render(RendererRequest(testID: "validation", script: "x", language: "en-GB"),
                                   rendererID: adapter.descriptor.id)
    #expect(!result.success)
    #expect(result.outputAudioPath == nil)
    #expect(result.error?.contains(expectedError) == true)
}

@Test func qwenDescriptorCapabilitySnapshotPersists() throws {
    let root = try temporaryDirectory()
    let result = try qwenRunner(behavior: .renderSuccess, root: root).render(try qwenRequest(), rendererID: "qwen3")
    #expect(result.descriptorSnapshot.modelCheckpoint?.contains(Qwen3Constants.modelRevision) == true)
    #expect(result.capabilitySnapshot.voiceCloning)
    #expect(result.capabilitySnapshot.multilingual)
    #expect(!result.capabilitySnapshot.naturalLanguageDirection)
    #expect(!result.capabilitySnapshot.streaming)
}

@Test func twoQwenRunsDoNotOverwrite() throws {
    let root = try temporaryDirectory()
    let runner = qwenRunner(behavior: .renderSuccess, root: root)
    let request = try qwenRequest()
    let first = try runner.render(request, rendererID: "qwen3")
    let second = try runner.render(request, rendererID: "qwen3")
    #expect(first.runID != second.runID)
    let firstPath = runner.store.paths(testID: "C01", runID: first.runID, rendererID: "qwen3").outputAudioFile
    let secondPath = runner.store.paths(testID: "C01", runID: second.runID, rendererID: "qwen3").outputAudioFile
    #expect(firstPath != secondPath)
    #expect(FileManager.default.fileExists(atPath: firstPath.path))
    #expect(FileManager.default.fileExists(atPath: secondPath.path))
}
