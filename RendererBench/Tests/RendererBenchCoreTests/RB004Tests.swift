import Foundation
import Testing
@testable import Qwen3RendererAdapter
@testable import RendererBenchCore
@testable import VoxCPM2RendererAdapter

private func rb004Root() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

private func rb004WorkerScript(_ body: String) throws -> URL {
    let directory = try temporaryDirectory()
    let url = directory.appending(path: "voxcpm2_worker.py")
    try Data(body.utf8).write(to: url)
    return url
}

private func rb004ProtocolScript() -> String {
    """
    import json,sys
    state="ready_unloaded"; loaded=False; renders=0; session="vox-session"
    for line in sys.stdin:
        req=json.loads(line); op=req["operation"]; reused=loaded
        if op=="load": state="ready_loaded"; loaded=True
        elif op=="render": state="ready_loaded"; loaded=True; renders+=1
        elif op=="shutdown": state="stopped"
        response={
          "protocol_version":1,"request_id":req["request_id"],"success":True,"error":None,
          "output_audio":None,"sample_rate":None,"duration_seconds":None,
          "model_id":"\(VoxCPM2Constants.modelID)","model_revision":"\(VoxCPM2Constants.modelRevision)",
          "upstream_model_id":"\(VoxCPM2Constants.upstreamModelID)",
          "upstream_model_revision":"\(VoxCPM2Constants.upstreamModelRevision)",
          "runtime_id":"\(VoxCPM2Constants.runtimeID)","runtime_revision":"\(VoxCPM2Constants.runtimeRevision)",
          "package_versions":{},"python_version":"test","os_version":"test",
          "machine_architecture":"arm64","actual_backend":"mlx-metal","metal_available":True,
          "worker_state":state,"worker_session_id":session,"worker_reused":True,
          "model_reused":reused,"cold_start":renders==1 if op=="render" else None,
          "model_available":True,"render_attemptable":True,"warnings":[],
          "render_index":renders-1 if op=="render" else None,
          "clone_mode":"continuation_prompt_audio_transcript" if op=="render" else None,
          "actual_settings":{}
        }
        print(json.dumps(response),flush=True)
        if op=="shutdown": break
    """
}

private func rb004PersistentClient(script: URL, timeout: TimeInterval = 2) -> PersistentVoxCPM2WorkerClient {
    PersistentVoxCPM2WorkerClient(pythonURL: URL(fileURLWithPath: "/usr/bin/python3"),
                                  workerURL: script, timeout: timeout)
}

private final class StatefulFakeVoxClient: VoxCPM2WorkerClient, @unchecked Sendable {
    private let lock = NSLock()
    private var loaded = false
    private var renders = 0

    func send(_ request: VoxCPM2WorkerRequest) throws -> VoxCPM2WorkerResponse {
        lock.lock(); defer { lock.unlock() }
        switch request.operation {
        case .health:
            return response(request, state: loaded ? .readyLoaded : .readyUnloaded,
                            modelReused: loaded)
        case .load:
            let reused = loaded; loaded = true
            return response(request, state: .readyLoaded, modelReused: reused,
                            modelLoad: reused ? 0 : 0.4)
        case .render:
            let reused = loaded; loaded = true
            guard let path = request.outputAudio else { throw CocoaError(.fileNoSuchFile) }
            _ = try MockRendererAdapter().render(
                RendererRequest(testID: "fixture", script: "fixture", language: "en-GB"),
                to: URL(fileURLWithPath: path))
            let index = renders; renders += 1
            var value = response(request, state: .readyLoaded, modelReused: reused,
                                 cold: index == 0, renderIndex: index,
                                 modelLoad: reused ? 0 : 0.4)
            value.outputAudio = path; value.sampleRate = 48_000; value.durationSeconds = 1
            value.generationSeconds = 0.7
            value.cloneMode = "continuation_prompt_audio_transcript"
            value.actualSettings = ["inference_timesteps": .number(10), "cfg_value": .number(2)]
            return value
        case .shutdown:
            return response(request, state: .stopped, modelReused: loaded)
        }
    }

    private func response(_ request: VoxCPM2WorkerRequest, state: VoxCPM2WorkerState,
                          modelReused: Bool, cold: Bool? = nil, renderIndex: Int? = nil,
                          modelLoad: Double? = nil) -> VoxCPM2WorkerResponse {
        VoxCPM2WorkerResponse(requestID: request.requestID, success: true,
            packageVersions: ["mlx": "test", "mlx-audio": "0.4.6"],
            pythonVersion: "3.12", osVersion: "test", machineArchitecture: "arm64",
            actualBackend: "mlx-metal", metalAvailable: true, workerStartupSeconds: 0.01,
            pythonImportSeconds: 0.2, modelLoadSeconds: modelLoad, modelAvailable: true,
            renderAttemptable: true, workerState: state, workerSessionID: "stateful-vox",
            workerReused: true, modelReused: modelReused, coldStart: cold,
            renderIndex: renderIndex)
    }
}

private struct ThrowingVoxClient: VoxCPM2WorkerClient {
    func send(_ request: VoxCPM2WorkerRequest) throws -> VoxCPM2WorkerResponse {
        throw VoxCPM2WorkerClientError.missingExecutable("/missing/python")
    }
}

private func rb004Request(assetID: String = "reference-001") throws -> RendererRequest {
    let reference = try temporaryDirectory().appending(path: "reference.wav")
    try Data([1]).write(to: reference)
    return RendererRequest(testID: "C01", script: "Persistent Vox fixture.", language: "en-GB",
        referenceAudioPaths: [reference.path], referenceAudioTranscripts: ["Reference transcript."],
        rendererSettings: ["reference_asset_id": .string(assetID),
                           "inference_timesteps": .number(10), "cfg_value": .number(2)])
}

@Test func voxcpmWorkerRequestEncoding() throws {
    let request = VoxCPM2WorkerRequest(operation: .render, requestID: "vox-request",
        text: "New speech", language: "en-GB", referenceAudio: "/tmp/reference.wav",
        referenceText: "Reference", outputAudio: "/tmp/output.wav",
        settings: ["inference_timesteps": .number(10)])
    let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
    #expect(object["operation"] as? String == "render")
    #expect(object["model_revision"] as? String == VoxCPM2Constants.modelRevision)
    #expect(object["upstream_model_revision"] as? String == VoxCPM2Constants.upstreamModelRevision)
}

@Test func voxcpmWorkerResponseDecoding() throws {
    let original = VoxCPM2WorkerResponse(requestID: "r", success: true,
        actualBackend: "mlx-metal", metalAvailable: true, workerState: .readyLoaded,
        actualSettings: ["cfg_value": .number(2)])
    let decoded = try JSONDecoder().decode(VoxCPM2WorkerResponse.self, from: JSONEncoder().encode(original))
    #expect(decoded == original)
}

@Test func voxcpmPersistentFramingAndRequestIDs() throws {
    let client = rb004PersistentClient(script: try rb004WorkerScript(rb004ProtocolScript()))
    let health = try client.send(VoxCPM2WorkerRequest(operation: .health, requestID: "health"))
    let load = try client.send(VoxCPM2WorkerRequest(operation: .load, requestID: "load"))
    #expect(health.requestID == "health")
    #expect(load.requestID == "load")
    #expect(health.workerSessionID == load.workerSessionID)
    _ = try client.send(VoxCPM2WorkerRequest(operation: .shutdown, requestID: "shutdown"))
}

@Test func voxcpmPersistentStateTransitionsAndLoadState() throws {
    let client = rb004PersistentClient(script: try rb004WorkerScript(rb004ProtocolScript()))
    #expect(client.state == .stopped)
    #expect(try client.send(VoxCPM2WorkerRequest(operation: .health, requestID: "h")).workerState == .readyUnloaded)
    #expect(try client.send(VoxCPM2WorkerRequest(operation: .load, requestID: "l")).workerState == .readyLoaded)
    #expect(try client.send(VoxCPM2WorkerRequest(operation: .render, requestID: "r")).workerState == .readyLoaded)
    #expect(try client.send(VoxCPM2WorkerRequest(operation: .shutdown, requestID: "s")).workerState == .stopped)
}

@Test func voxcpmHealthUnavailableState() {
    let adapter = VoxCPM2RendererAdapter(client: ThrowingVoxClient(), availabilityOverride: .unavailable)
    let health = adapter.healthCheck()
    #expect(health.status == .unavailable)
    #expect(health.message.contains("setup-voxcpm2"))
}

@Test func voxcpmLoadAndMultipleRendersReuseModel() throws {
    let client = StatefulFakeVoxClient()
    let adapter = VoxCPM2RendererAdapter(client: client, availabilityOverride: .available)
    let load = try adapter.load()
    let runner = BenchmarkRunner(registry: .standard(overrides: [adapter]),
                                 store: BenchStore(rootURL: try temporaryDirectory()))
    let first = try runner.render(try rb004Request(), rendererID: "voxcpm2")
    let second = try runner.render(try rb004Request(), rendererID: "voxcpm2")
    #expect(load.modelReused == false)
    #expect(first.environmentSnapshot["model_reused"] == "true")
    #expect(second.environmentSnapshot["model_reused"] == "true")
    #expect(first.environmentSnapshot["render_index"] == "0")
    #expect(second.environmentSnapshot["render_index"] == "1")
}

@Test func voxcpmGracefulShutdownTerminatesWorker() throws {
    let client = rb004PersistentClient(script: try rb004WorkerScript(rb004ProtocolScript()))
    _ = try client.send(VoxCPM2WorkerRequest(operation: .health, requestID: "h"))
    #expect(client.isRunning)
    _ = try client.send(VoxCPM2WorkerRequest(operation: .shutdown, requestID: "s"))
    #expect(!client.isRunning)
    #expect(client.state == .stopped)
}

@Test func voxcpmMalformedResponseFailsSafely() throws {
    let client = rb004PersistentClient(script: try rb004WorkerScript(
        "import sys\nsys.stdin.readline()\nprint('{bad json',flush=True)\n"))
    #expect(throws: VoxCPM2WorkerClientError.self) {
        _ = try client.send(VoxCPM2WorkerRequest(operation: .health, requestID: "h"))
    }
    #expect(!client.isRunning)
}

@Test func voxcpmUnexpectedExitFailsSafely() throws {
    let client = rb004PersistentClient(script: try rb004WorkerScript(
        "import sys\nsys.stdin.readline()\nsys.stderr.write('planned exit')\n"))
    #expect(throws: VoxCPM2WorkerClientError.self) {
        _ = try client.send(VoxCPM2WorkerRequest(operation: .health, requestID: "h"))
    }
    #expect(!client.isRunning)
}

@Test func voxcpmTimeoutFailsSafely() throws {
    let client = rb004PersistentClient(script: try rb004WorkerScript(
        "import sys,time\nsys.stdin.readline()\ntime.sleep(2)\n"), timeout: 0.2)
    #expect(throws: VoxCPM2WorkerClientError.self) {
        _ = try client.send(VoxCPM2WorkerRequest(operation: .health, requestID: "h"))
    }
    #expect(!client.isRunning)
}

@Test func voxcpmLineageMetadataPersists() throws {
    let adapter = VoxCPM2RendererAdapter(client: StatefulFakeVoxClient(), availabilityOverride: .available)
    let result = try BenchmarkRunner(registry: .standard(overrides: [adapter]),
        store: BenchStore(rootURL: try temporaryDirectory())).render(try rb004Request(), rendererID: "voxcpm2")
    #expect(result.environmentSnapshot["voxcpm2_conversion_model_revision"] == VoxCPM2Constants.modelRevision)
    #expect(result.environmentSnapshot["voxcpm2_upstream_model_revision"] == VoxCPM2Constants.upstreamModelRevision)
    #expect(result.environmentSnapshot["voxcpm2_runtime_revision"] == VoxCPM2Constants.runtimeRevision)
}

@Test func voxcpmDescriptorCapabilitySnapshotPersistsTruthfully() throws {
    let adapter = VoxCPM2RendererAdapter(client: StatefulFakeVoxClient(), availabilityOverride: .available)
    let result = try BenchmarkRunner(registry: .standard(overrides: [adapter]),
        store: BenchStore(rootURL: try temporaryDirectory())).render(try rb004Request(), rendererID: "voxcpm2")
    #expect(result.descriptorSnapshot.id == "voxcpm2")
    #expect(result.capabilitySnapshot.voiceCloning)
    #expect(result.capabilitySnapshot.multilingual)
    #expect(!result.capabilitySnapshot.streaming)
    #expect(!result.capabilitySnapshot.naturalLanguageDirection)
    #expect(!result.capabilitySnapshot.deterministicSeed)
}

@Test func voxcpmReferenceAssetIDPersists() throws {
    let adapter = VoxCPM2RendererAdapter(client: StatefulFakeVoxClient(), availabilityOverride: .available)
    let result = try BenchmarkRunner(registry: .standard(overrides: [adapter]),
        store: BenchStore(rootURL: try temporaryDirectory())).render(
            try rb004Request(assetID: "reference-001"), rendererID: "voxcpm2")
    #expect(result.environmentSnapshot["reference_asset_id"] == "reference-001")
    #expect(result.settingsSnapshot["reference_asset_id"] == .string("reference-001"))
}

@Test func commonValidatorAccepts48kVoxFixture() throws {
    let output = try temporaryDirectory().appending(path: "voxcpm.wav")
    let rendered = try MockRendererAdapter().render(
        RendererRequest(testID: "V48", script: "fixture", language: "en-GB"), to: output)
    let validated = try AudioFileValidator.validateWAV(at: output, reportedDuration: rendered.duration)
    #expect(validated.sampleRate == 48_000)
    #expect(validated.channels == 1)
}

@Test func twoVoxRunsDoNotOverwrite() throws {
    let adapter = VoxCPM2RendererAdapter(client: StatefulFakeVoxClient(), availabilityOverride: .available)
    let store = BenchStore(rootURL: try temporaryDirectory())
    let runner = BenchmarkRunner(registry: .standard(overrides: [adapter]), store: store)
    let first = try runner.render(try rb004Request(), rendererID: "voxcpm2")
    let second = try runner.render(try rb004Request(), rendererID: "voxcpm2")
    #expect(first.runID != second.runID)
    #expect(FileManager.default.fileExists(atPath: first.outputAudioPath!))
    #expect(FileManager.default.fileExists(atPath: second.outputAudioPath!))
}

private struct FixtureAdapter: RendererAdapter {
    let id: String
    var descriptor: RendererDescriptor {
        RendererDescriptor(id: id, displayName: id, location: .local, availability: .available,
            rendererVersion: "fixture", capabilities: RendererCapabilities(textToSpeech: true, local: true))
    }
    func healthCheck() -> RendererHealth { RendererHealth(status: .healthy, message: "fixture") }
    func render(_ request: RendererRequest, to outputURL: URL) throws -> RenderedAudio {
        try MockRendererAdapter().render(request, to: outputURL)
    }
}

@Test func differentRendererIDsShareCanonicalBenchmarkWithoutCollision() throws {
    let store = BenchStore(rootURL: try temporaryDirectory())
    let registry = RendererRegistry(adapters: [FixtureAdapter(id: "qwen3"), FixtureAdapter(id: "voxcpm2")])
    let runner = BenchmarkRunner(registry: registry, store: store)
    let request = RendererRequest(testID: "A01", script: "same", language: "en-GB")
    let qwen = try runner.render(request, rendererID: "qwen3", runID: "comparison")
    let vox = try runner.render(request, rendererID: "voxcpm2", runID: "comparison")
    #expect(qwen.outputAudioPath != vox.outputAudioPath)
    #expect(FileManager.default.fileExists(atPath: qwen.outputAudioPath!))
    #expect(FileManager.default.fileExists(atPath: vox.outputAudioPath!))
}

@Test func comparisonHarnessUsesStableDefinitionsAndLocalIdentity() throws {
    let script = try String(contentsOf: rb004Root().appending(path: "scripts/compare-qwen-voxcpm2.sh"),
                            encoding: .utf8)
    let definitions = try BenchCatalog.loadDefinitions(from: rb004Root().appending(path: "BenchAssets/benchmarks"))
    #expect(script.contains("local-assets.json"))
    #expect(script.contains("qwen-session-bench"))
    #expect(script.contains("voxcpm2-session-bench"))
    #expect(definitions.map(\.testID) == ["A01", "C01"])
}
