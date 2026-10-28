import Foundation
import Testing
@testable import Qwen3RendererAdapter
@testable import RendererBenchCore
@testable import ChatterboxRendererAdapter

private func rb005Root() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

private func rb005WorkerScript(_ body: String) throws -> URL {
    let directory = try temporaryDirectory()
    let url = directory.appending(path: "chatterbox_worker.py")
    try Data(body.utf8).write(to: url)
    return url
}

private func rb005ProtocolScript() -> String {
    """
    import json,sys
    state="ready_unloaded"; loaded=False; renders=0; session="chatterbox-session"
    for line in sys.stdin:
        req=json.loads(line); op=req["operation"]; reused=loaded
        if op=="load": state="ready_loaded"; loaded=True
        elif op=="render": state="ready_loaded"; loaded=True; renders+=1
        elif op=="shutdown": state="stopped"
        response={
          "protocol_version":1,"request_id":req["request_id"],"success":True,"error":None,
          "output_audio":None,"sample_rate":None,"duration_seconds":None,
          "model_id":"\(ChatterboxConstants.modelID)","model_revision":"\(ChatterboxConstants.modelRevision)",
          "source_revision":"\(ChatterboxConstants.sourceRevision)",
          "variant":"\(ChatterboxConstants.variant)","t3_model":"v3",
          "t3_filename":"\(ChatterboxConstants.t3Filename)",
          "runtime_id":"\(ChatterboxConstants.runtimeID)","runtime_revision":"\(ChatterboxConstants.runtimeRevision)",
          "package_versions":{},"python_version":"test","os_version":"test",
          "machine_architecture":"arm64","requested_backend":"mps","actual_backend":"mps",
          "mps_available":True,"mps_built":True,
          "worker_state":state,"worker_session_id":session,"worker_reused":True,
          "model_reused":reused,"cold_start":renders==1 if op=="render" else None,
          "model_available":True,"render_attemptable":True,"warnings":[],
          "render_index":renders-1 if op=="render" else None,
          "clone_mode":"zero_shot_reference_audio" if op=="render" else None,
          "actual_settings":{},"watermark_expected":True,"watermark_enabled":True,
          "watermark_system":"PerTh implicit","watermark_version":"1.0.1",
          "reference_transcript_used":False
        }
        print(json.dumps(response),flush=True)
        if op=="shutdown": break
    """
}

private func rb005PersistentClient(script: URL, timeout: TimeInterval = 2) -> PersistentChatterboxWorkerClient {
    PersistentChatterboxWorkerClient(pythonURL: URL(fileURLWithPath: "/usr/bin/python3"),
                                  workerURL: script, timeout: timeout)
}

private final class StatefulFakeChatterboxClient: ChatterboxWorkerClient, @unchecked Sendable {
    private let lock = NSLock()
    private var loaded = false
    private var renders = 0

    func send(_ request: ChatterboxWorkerRequest) throws -> ChatterboxWorkerResponse {
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
            value.outputAudio = path; value.sampleRate = 24_000; value.durationSeconds = 1
            value.generationSeconds = 0.7
            value.cloneMode = "zero_shot_reference_audio"
            value.actualSettings = ["exaggeration": .number(0.5), "cfg_weight": .number(0.5)]
            value.watermarkEnabled = true
            return value
        case .shutdown:
            return response(request, state: .stopped, modelReused: loaded)
        }
    }

    private func response(_ request: ChatterboxWorkerRequest, state: ChatterboxWorkerState,
                          modelReused: Bool, cold: Bool? = nil, renderIndex: Int? = nil,
                          modelLoad: Double? = nil) -> ChatterboxWorkerResponse {
        ChatterboxWorkerResponse(requestID: request.requestID, success: true,
            packageVersions: ["chatterbox-tts": "0.1.7", "torch": "2.6.0", "resemble-perth": "1.0.1"],
            pythonVersion: "3.12", osVersion: "test", machineArchitecture: "arm64",
            requestedBackend: "mps", actualBackend: "mps", mpsAvailable: true, mpsBuilt: true,
            workerStartupSeconds: 0.01,
            pythonImportSeconds: 0.2, modelLoadSeconds: modelLoad, modelAvailable: true,
            renderAttemptable: true, workerState: state, workerSessionID: "stateful-chatterbox",
            workerReused: true, modelReused: modelReused, coldStart: cold,
            renderIndex: renderIndex, watermarkExpected: true, watermarkEnabled: true,
            watermarkSystem: "PerTh implicit", watermarkVersion: "1.0.1",
            referenceTranscriptUsed: false)
    }
}

private struct ThrowingChatterboxClient: ChatterboxWorkerClient {
    func send(_ request: ChatterboxWorkerRequest) throws -> ChatterboxWorkerResponse {
        throw ChatterboxWorkerClientError.missingExecutable("/missing/python")
    }
}

private func rb005Request(assetID: String = "reference-001") throws -> RendererRequest {
    let reference = try temporaryDirectory().appending(path: "reference.wav")
    try Data([1]).write(to: reference)
    return RendererRequest(testID: "C01", script: "Persistent Chatterbox fixture.", language: "en-GB",
        referenceAudioPaths: [reference.path], referenceAudioTranscripts: ["Reference transcript."],
        rendererSettings: ["reference_asset_id": .string(assetID),
                           "exaggeration": .number(0.5), "cfg_weight": .number(0.5)])
}

@Test func chatterboxWorkerRequestEncoding() throws {
    let request = ChatterboxWorkerRequest(operation: .render, requestID: "chatterbox-request",
        text: "New speech", languageID: "en-GB", referenceAudio: "/tmp/reference.wav",
        outputAudio: "/tmp/output.wav", settings: ["cfg_weight": .number(0.5)])
    let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
    #expect(object["operation"] as? String == "render")
    #expect(object["model_revision"] as? String == ChatterboxConstants.modelRevision)
    #expect(object["source_revision"] as? String == ChatterboxConstants.sourceRevision)
    #expect(object["variant"] as? String == "Multilingual V3")
    #expect(object["t3_model"] as? String == "v3")
}

@Test func chatterboxWorkerResponseDecoding() throws {
    let original = ChatterboxWorkerResponse(requestID: "r", success: true,
        actualBackend: "mps", mpsAvailable: true, workerState: .readyLoaded,
        actualSettings: ["cfg_value": .number(2)])
    let decoded = try JSONDecoder().decode(ChatterboxWorkerResponse.self, from: JSONEncoder().encode(original))
    #expect(decoded == original)
}

@Test func chatterboxPersistentFramingAndRequestIDs() throws {
    let client = rb005PersistentClient(script: try rb005WorkerScript(rb005ProtocolScript()))
    let health = try client.send(ChatterboxWorkerRequest(operation: .health, requestID: "health"))
    let load = try client.send(ChatterboxWorkerRequest(operation: .load, requestID: "load"))
    #expect(health.requestID == "health")
    #expect(load.requestID == "load")
    #expect(health.workerSessionID == load.workerSessionID)
    _ = try client.send(ChatterboxWorkerRequest(operation: .shutdown, requestID: "shutdown"))
}

@Test func chatterboxPersistentStateTransitionsAndLoadState() throws {
    let client = rb005PersistentClient(script: try rb005WorkerScript(rb005ProtocolScript()))
    #expect(client.state == .stopped)
    #expect(try client.send(ChatterboxWorkerRequest(operation: .health, requestID: "h")).workerState == .readyUnloaded)
    #expect(try client.send(ChatterboxWorkerRequest(operation: .load, requestID: "l")).workerState == .readyLoaded)
    #expect(try client.send(ChatterboxWorkerRequest(operation: .render, requestID: "r")).workerState == .readyLoaded)
    #expect(try client.send(ChatterboxWorkerRequest(operation: .shutdown, requestID: "s")).workerState == .stopped)
}

@Test func chatterboxHealthUnavailableState() {
    let adapter = ChatterboxRendererAdapter(client: ThrowingChatterboxClient(), availabilityOverride: .unavailable)
    let health = adapter.healthCheck()
    #expect(health.status == .unavailable)
    #expect(health.message.contains("setup-chatterbox"))
}

@Test func chatterboxLoadAndMultipleRendersReuseModel() throws {
    let client = StatefulFakeChatterboxClient()
    let adapter = ChatterboxRendererAdapter(client: client, availabilityOverride: .available)
    let load = try adapter.load()
    let runner = BenchmarkRunner(registry: .standard(overrides: [adapter]),
                                 store: BenchStore(rootURL: try temporaryDirectory()))
    let first = try runner.render(try rb005Request(), rendererID: "chatterbox")
    let second = try runner.render(try rb005Request(), rendererID: "chatterbox")
    #expect(load.modelReused == false)
    #expect(first.environmentSnapshot["model_reused"] == "true")
    #expect(second.environmentSnapshot["model_reused"] == "true")
    #expect(first.environmentSnapshot["render_index"] == "0")
    #expect(second.environmentSnapshot["render_index"] == "1")
}

@Test func chatterboxGracefulShutdownTerminatesWorker() throws {
    let client = rb005PersistentClient(script: try rb005WorkerScript(rb005ProtocolScript()))
    _ = try client.send(ChatterboxWorkerRequest(operation: .health, requestID: "h"))
    #expect(client.isRunning)
    _ = try client.send(ChatterboxWorkerRequest(operation: .shutdown, requestID: "s"))
    #expect(!client.isRunning)
    #expect(client.state == .stopped)
}

@Test func chatterboxMalformedResponseFailsSafely() throws {
    let client = rb005PersistentClient(script: try rb005WorkerScript(
        "import sys\nsys.stdin.readline()\nprint('{bad json',flush=True)\n"))
    #expect(throws: ChatterboxWorkerClientError.self) {
        _ = try client.send(ChatterboxWorkerRequest(operation: .health, requestID: "h"))
    }
    #expect(!client.isRunning)
}

@Test func chatterboxUnexpectedExitFailsSafely() throws {
    let client = rb005PersistentClient(script: try rb005WorkerScript(
        "import sys\nsys.stdin.readline()\nsys.stderr.write('planned exit')\n"))
    #expect(throws: ChatterboxWorkerClientError.self) {
        _ = try client.send(ChatterboxWorkerRequest(operation: .health, requestID: "h"))
    }
    #expect(!client.isRunning)
}

@Test func chatterboxTimeoutFailsSafely() throws {
    let client = rb005PersistentClient(script: try rb005WorkerScript(
        "import sys,time\nsys.stdin.readline()\ntime.sleep(2)\n"), timeout: 0.2)
    #expect(throws: ChatterboxWorkerClientError.self) {
        _ = try client.send(ChatterboxWorkerRequest(operation: .health, requestID: "h"))
    }
    #expect(!client.isRunning)
}

@Test func chatterboxLineageMetadataPersists() throws {
    let adapter = ChatterboxRendererAdapter(client: StatefulFakeChatterboxClient(), availabilityOverride: .available)
    let result = try BenchmarkRunner(registry: .standard(overrides: [adapter]),
        store: BenchStore(rootURL: try temporaryDirectory())).render(try rb005Request(), rendererID: "chatterbox")
    #expect(result.environmentSnapshot["chatterbox_model_revision"] == ChatterboxConstants.modelRevision)
    #expect(result.environmentSnapshot["chatterbox_source_revision"] == ChatterboxConstants.sourceRevision)
    #expect(result.environmentSnapshot["chatterbox_variant"] == "Multilingual V3")
    #expect(result.environmentSnapshot["chatterbox_t3_model"] == "v3")
    #expect(result.environmentSnapshot["chatterbox_runtime_revision"] == ChatterboxConstants.runtimeRevision)
}

@Test func chatterboxLegacyV2CannotBeSilentlySelected() throws {
    #expect(ChatterboxConstants.variant == "Multilingual V3")
    #expect(ChatterboxConstants.t3Model == "v3")
    #expect(ChatterboxConstants.t3Filename == "t3_mtl23ls_v3.safetensors")
    let worker = try String(contentsOf: rb005Root().appending(path: "Workers/Chatterbox/chatterbox_worker.py"),
                            encoding: .utf8)
    #expect(worker.contains("V2/Turbo/Nano are forbidden"))
    #expect(worker.contains("t3_model=T3_MODEL"))
}

@Test func chatterboxDescriptorCapabilitySnapshotPersistsTruthfully() throws {
    let adapter = ChatterboxRendererAdapter(client: StatefulFakeChatterboxClient(), availabilityOverride: .available)
    let result = try BenchmarkRunner(registry: .standard(overrides: [adapter]),
        store: BenchStore(rootURL: try temporaryDirectory())).render(try rb005Request(), rendererID: "chatterbox")
    #expect(result.descriptorSnapshot.id == "chatterbox")
    #expect(result.capabilitySnapshot.voiceCloning)
    #expect(result.capabilitySnapshot.multilingual)
    #expect(!result.capabilitySnapshot.streaming)
    #expect(!result.capabilitySnapshot.naturalLanguageDirection)
    #expect(!result.capabilitySnapshot.deterministicSeed)
}

@Test func chatterboxReferenceAssetIDPersists() throws {
    let adapter = ChatterboxRendererAdapter(client: StatefulFakeChatterboxClient(), availabilityOverride: .available)
    let result = try BenchmarkRunner(registry: .standard(overrides: [adapter]),
        store: BenchStore(rootURL: try temporaryDirectory())).render(
            try rb005Request(assetID: "reference-001"), rendererID: "chatterbox")
    #expect(result.environmentSnapshot["reference_asset_id"] == "reference-001")
    #expect(result.settingsSnapshot["reference_asset_id"] == .string("reference-001"))
    #expect(result.environmentSnapshot["reference_transcript_available"] == "true")
    #expect(result.environmentSnapshot["reference_transcript_used"] == "false")
}

@Test func chatterboxNativeSettingsLanguageAndWatermarkPersist() throws {
    let adapter = ChatterboxRendererAdapter(client: StatefulFakeChatterboxClient(), availabilityOverride: .available)
    let result = try BenchmarkRunner(registry: .standard(overrides: [adapter]),
        store: BenchStore(rootURL: try temporaryDirectory())).render(try rb005Request(), rendererID: "chatterbox")
    #expect(result.settingsSnapshot["exaggeration"] == .number(0.5))
    #expect(result.settingsSnapshot["cfg_weight"] == .number(0.5))
    #expect(result.environmentSnapshot["requested_language"] == "en-GB")
    #expect(result.environmentSnapshot["watermark_expected"] == "true")
    #expect(result.environmentSnapshot["watermark_enabled"] == "true")
    #expect(result.environmentSnapshot["watermark_system"] == "PerTh implicit")
    #expect(result.environmentSnapshot["watermark_version"] == "1.0.1")
}

@Test func chatterboxUnsupportedGenericDirectionIsRejected() throws {
    let adapter = ChatterboxRendererAdapter(client: StatefulFakeChatterboxClient(), availabilityOverride: .available)
    var request = try rb005Request()
    request.directionText = "Make it more intimate"
    #expect(throws: ChatterboxAdapterError.self) {
        _ = try adapter.render(request, to: try temporaryDirectory().appending(path: "output.wav"))
    }
}

@Test func commonValidatorAcceptsValidChatterboxFixture() throws {
    let output = try temporaryDirectory().appending(path: "chatterbox.wav")
    let rendered = try MockRendererAdapter().render(
        RendererRequest(testID: "V48", script: "fixture", language: "en-GB"), to: output)
    let validated = try AudioFileValidator.validateWAV(at: output, reportedDuration: rendered.duration)
    #expect(validated.sampleRate == 48_000)
    #expect(validated.channels == 1)
}

@Test func twoChatterboxRunsDoNotOverwrite() throws {
    let adapter = ChatterboxRendererAdapter(client: StatefulFakeChatterboxClient(), availabilityOverride: .available)
    let store = BenchStore(rootURL: try temporaryDirectory())
    let runner = BenchmarkRunner(registry: .standard(overrides: [adapter]), store: store)
    let first = try runner.render(try rb005Request(), rendererID: "chatterbox")
    let second = try runner.render(try rb005Request(), rendererID: "chatterbox")
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

@Test func threeRendererIDsShareCanonicalBenchmarkWithoutCollision() throws {
    let store = BenchStore(rootURL: try temporaryDirectory())
    let registry = RendererRegistry(adapters: [FixtureAdapter(id: "qwen3"), FixtureAdapter(id: "voxcpm2"), FixtureAdapter(id: "chatterbox")])
    let runner = BenchmarkRunner(registry: registry, store: store)
    let request = RendererRequest(testID: "A01", script: "same", language: "en-GB")
    let qwen = try runner.render(request, rendererID: "qwen3", runID: "comparison")
    let vox = try runner.render(request, rendererID: "voxcpm2", runID: "comparison")
    let chatterbox = try runner.render(request, rendererID: "chatterbox", runID: "comparison")
    #expect(qwen.outputAudioPath != chatterbox.outputAudioPath)
    #expect(vox.outputAudioPath != chatterbox.outputAudioPath)
    #expect(FileManager.default.fileExists(atPath: qwen.outputAudioPath!))
    #expect(FileManager.default.fileExists(atPath: chatterbox.outputAudioPath!))
}

@Test func threeWayComparisonHarnessUsesStableDefinitionsAndLocalIdentity() throws {
    let script = try String(contentsOf: rb005Root().appending(path: "scripts/compare-qwen-voxcpm2-chatterbox.sh"),
                            encoding: .utf8)
    let definitions = try BenchCatalog.loadDefinitions(from: rb005Root().appending(path: "BenchAssets/benchmarks"))
    #expect(script.contains("local-assets.json"))
    #expect(script.contains("qwen-session-bench"))
    #expect(script.contains("voxcpm2-session-bench"))
    #expect(script.contains("chatterbox-session-bench"))
    #expect(script.contains("listening-bundle"))
    #expect(definitions.map(\.testID) == ["A01", "C01"])
}
