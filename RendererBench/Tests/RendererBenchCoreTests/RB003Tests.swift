import Foundation
import Testing
@testable import Qwen3RendererAdapter
@testable import RendererBenchCore

private func projectRoot() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

private func fakeWorkerScript(_ body: String) throws -> URL {
    let directory = try temporaryDirectory()
    let url = directory.appending(path: "worker.py")
    try Data(body.utf8).write(to: url)
    return url
}

private func protocolWorkerScript() -> String {
    """
    import json,sys
    state="ready_unloaded"
    loaded=False
    renders=0
    session="fake-session"
    for line in sys.stdin:
        req=json.loads(line)
        op=req["operation"]
        reused=loaded
        if op=="load": state="ready_loaded"; loaded=True
        elif op=="render": state="ready_loaded"; renders+=1
        elif op=="shutdown": state="stopped"
        response={
          "protocol_version":1,"request_id":req["request_id"],"success":True,"error":None,
          "output_audio":None,"sample_rate":None,"duration_seconds":None,
          "model_id":"\(Qwen3Constants.modelID)","model_revision":"\(Qwen3Constants.modelRevision)",
          "tokenizer_id":"\(Qwen3Constants.tokenizerID)","tokenizer_revision":"\(Qwen3Constants.tokenizerRevision)",
          "package_versions":{},"python_version":"test","os_version":"test",
          "machine_architecture":"arm64","device":"cpu","warnings":[],
          "worker_state":state,"worker_session_id":session,"worker_reused":True,
          "model_reused":reused,"cold_start":renders==1 if op=="render" else None,
          "requested_backend":req.get("requested_backend","cpu"),"actual_backend":"cpu",
          "render_index":renders-1 if op=="render" else None,"reference_prompt_reused":False
        }
        print(json.dumps(response),flush=True)
        if op=="shutdown": break
    """
}

private func persistentClient(script: URL, timeout: TimeInterval = 2) -> PersistentQwenWorkerClient {
    PersistentQwenWorkerClient(pythonURL: URL(fileURLWithPath: "/usr/bin/python3"),
                               workerURL: script, timeout: timeout,
                               environment: ["QWEN3_DEVICE": "cpu"])
}

private final class StatefulFakeQwenClient: QwenWorkerClient, @unchecked Sendable {
    private let lock = NSLock()
    private var loaded = false
    private var renders = 0

    func send(_ request: QwenWorkerRequest) throws -> QwenWorkerResponse {
        lock.lock(); defer { lock.unlock() }
        switch request.operation {
        case .health:
            return response(request, state: loaded ? .readyLoaded : .readyUnloaded,
                            modelReused: loaded, cold: nil, renderIndex: nil)
        case .load:
            let reused = loaded; loaded = true
            return response(request, state: .readyLoaded, modelReused: reused,
                            cold: nil, renderIndex: nil, modelLoad: reused ? 0 : 0.25)
        case .render:
            let reused = loaded; loaded = true
            guard let path = request.outputAudio else { throw CocoaError(.fileNoSuchFile) }
            _ = try MockRendererAdapter().render(
                RendererRequest(testID: "fixture", script: "fixture", language: "en-GB"),
                to: URL(fileURLWithPath: path))
            let index = renders; renders += 1
            var value = response(request, state: .readyLoaded, modelReused: reused,
                                 cold: index == 0, renderIndex: index, modelLoad: reused ? 0 : 0.25)
            value.outputAudio = path; value.sampleRate = 48_000; value.durationSeconds = 1
            value.generationSeconds = 0.5
            return value
        case .shutdown:
            return response(request, state: .stopped, modelReused: loaded, cold: nil, renderIndex: nil)
        }
    }

    private func response(_ request: QwenWorkerRequest, state: QwenWorkerState,
                          modelReused: Bool, cold: Bool?, renderIndex: Int?,
                          modelLoad: Double? = nil) -> QwenWorkerResponse {
        QwenWorkerResponse(requestID: request.requestID, success: true,
            packageVersions: ["qwen-tts": "test"], pythonVersion: "3.12",
            osVersion: "test", machineArchitecture: "arm64", device: "cpu",
            modelLoadSeconds: modelLoad, modelAvailable: true, tokenizerAvailable: true,
            renderAttemptable: true, workerState: state, workerSessionID: "stateful-session",
            workerReused: true, modelReused: modelReused, coldStart: cold,
            requestedBackend: request.requestedBackend, actualBackend: "cpu",
            pythonImportSeconds: 0.1, renderIndex: renderIndex, referencePromptReused: false)
    }
}

@Test func persistentProtocolFramingPreservesRequestIDs() throws {
    let client = persistentClient(script: try fakeWorkerScript(protocolWorkerScript()))
    let health = try client.send(QwenWorkerRequest(operation: .health, requestID: "health", requestedBackend: "cpu"))
    let load = try client.send(QwenWorkerRequest(operation: .load, requestID: "load", requestedBackend: "cpu"))
    #expect(health.requestID == "health")
    #expect(load.requestID == "load")
    #expect(health.workerSessionID == load.workerSessionID)
    _ = try client.send(QwenWorkerRequest(operation: .shutdown, requestID: "shutdown", requestedBackend: "cpu"))
}

@Test func persistentWorkerStateTransitions() throws {
    let client = persistentClient(script: try fakeWorkerScript(protocolWorkerScript()))
    #expect(client.state == .stopped)
    let health = try client.send(QwenWorkerRequest(operation: .health, requestID: "h", requestedBackend: "cpu"))
    #expect(health.workerState == .readyUnloaded)
    let load = try client.send(QwenWorkerRequest(operation: .load, requestID: "l", requestedBackend: "cpu"))
    #expect(load.workerState == .readyLoaded)
    let render = try client.send(QwenWorkerRequest(operation: .render, requestID: "r", requestedBackend: "cpu"))
    #expect(render.workerState == .readyLoaded)
    let stopped = try client.send(QwenWorkerRequest(operation: .shutdown, requestID: "s", requestedBackend: "cpu"))
    #expect(stopped.workerState == .stopped)
    #expect(client.state == .stopped)
}

@Test func loadThenMultipleRendersDoesNotLogicallyReload() throws {
    let client = persistentClient(script: try fakeWorkerScript(protocolWorkerScript()))
    let load = try client.send(QwenWorkerRequest(operation: .load, requestID: "l", requestedBackend: "cpu"))
    let first = try client.send(QwenWorkerRequest(operation: .render, requestID: "r1", requestedBackend: "cpu"))
    let second = try client.send(QwenWorkerRequest(operation: .render, requestID: "r2", requestedBackend: "cpu"))
    #expect(load.modelReused == false)
    #expect(first.modelReused == true)
    #expect(second.modelReused == true)
    #expect(first.renderIndex == 0)
    #expect(second.renderIndex == 1)
    _ = try client.send(QwenWorkerRequest(operation: .shutdown, requestID: "s", requestedBackend: "cpu"))
}

@Test func gracefulShutdownTerminatesWorker() throws {
    let client = persistentClient(script: try fakeWorkerScript(protocolWorkerScript()))
    _ = try client.send(QwenWorkerRequest(operation: .health, requestID: "h", requestedBackend: "cpu"))
    #expect(client.isRunning)
    let response = try client.send(QwenWorkerRequest(operation: .shutdown, requestID: "s", requestedBackend: "cpu"))
    #expect(response.workerState == .stopped)
    #expect(!client.isRunning)
}

@Test func malformedPersistentResponseFailsSafely() throws {
    let script = try fakeWorkerScript("import sys\nsys.stdin.readline()\nprint('{bad json',flush=True)\n")
    let client = persistentClient(script: script)
    #expect(throws: QwenWorkerClientError.self) {
        _ = try client.send(QwenWorkerRequest(operation: .health, requestID: "h", requestedBackend: "cpu"))
    }
    #expect(!client.isRunning)
    #expect(client.state == .failed)
}

@Test func unexpectedPersistentWorkerExitFailsSafely() throws {
    let script = try fakeWorkerScript("import sys\nsys.stdin.readline()\nsys.stderr.write('planned exit')\n")
    let client = persistentClient(script: script)
    #expect(throws: QwenWorkerClientError.self) {
        _ = try client.send(QwenWorkerRequest(operation: .health, requestID: "h", requestedBackend: "cpu"))
    }
    #expect(!client.isRunning)
}

@Test func timeoutTerminatesAndNextRequestRestarts() throws {
    let marker = try temporaryDirectory().appending(path: "marker").path
    let escapedMarker = marker.replacingOccurrences(of: "'", with: "\\'")
    let responseScript = protocolWorkerScript()
    let script = try fakeWorkerScript("""
    import os,sys,time
    marker='\(escapedMarker)'
    if not os.path.exists(marker):
        open(marker,'w').close()
        sys.stdin.readline()
        time.sleep(2)
    else:
    \(responseScript.split(separator: "\n").map { "    " + $0 }.joined(separator: "\n"))
    """)
    // Keep ample process-launch margin under the full parallel suite while remaining far below the scripted 2 s hang.
    let client = persistentClient(script: script, timeout: 0.5)
    #expect(throws: QwenWorkerClientError.self) {
        _ = try client.send(QwenWorkerRequest(operation: .health, requestID: "first", requestedBackend: "cpu"))
    }
    #expect(!client.isRunning)
    let restarted = try client.send(QwenWorkerRequest(operation: .health, requestID: "second", requestedBackend: "cpu"))
    #expect(restarted.success)
    _ = try client.send(QwenWorkerRequest(operation: .shutdown, requestID: "s", requestedBackend: "cpu"))
}

@Test func requestedAndActualBackendPersist() throws {
    let fake = StatefulFakeQwenClient()
    let adapter = Qwen3RendererAdapter(client: fake, availabilityOverride: .available, requestedBackend: "cpu")
    let runner = BenchmarkRunner(registry: .standard(overrides: [adapter]),
                                 store: BenchStore(rootURL: try temporaryDirectory()))
    let request = try qwenRequestForRB003()
    let result = try runner.render(request, rendererID: "qwen3")
    #expect(result.environmentSnapshot["requested_backend"] == "cpu")
    #expect(result.environmentSnapshot["actual_backend"] == "cpu")
}

@Test func coldWarmTimingMetadataSerializes() throws {
    let response = QwenWorkerResponse(requestID: "r", success: true, device: "mps",
        workerStartupSeconds: 0.2, modelLoadSeconds: 1.1, generationSeconds: 2.2,
        workerState: .readyLoaded, workerSessionID: "session", workerReused: true,
        modelReused: true, coldStart: false, requestedBackend: "mps", actualBackend: "mps",
        pythonImportSeconds: 0.7, renderIndex: 2, referencePromptReused: false)
    let decoded = try JSONDecoder().decode(QwenWorkerResponse.self, from: JSONEncoder().encode(response))
    #expect(decoded == response)
    #expect(decoded.environmentSnapshot["cold_start"] == "false")
    #expect(decoded.environmentSnapshot["python_import_seconds"] == "0.7")
}

@Test func referenceAssetMetadataSerialization() throws {
    let metadata = ReferenceAssetMetadata(assetID: "engineering-voice-1", displayName: "Engineering Voice",
        source: "rights-cleared recording", licence: "CC0-1.0", redistributionPermitted: true,
        language: "en-GB", speakerDescription: "adult neutral voice", transcript: "Known text",
        sampleRate: 24_000, channels: 1, duration: 4.2, notes: "fixture", dateAdded: "2026-08-08")
    let decoded = try JSONDecoder().decode(ReferenceAssetMetadata.self, from: JSONEncoder().encode(metadata))
    #expect(decoded == metadata)
}

@Test func benchmarkDefinitionsLoadA01AndC01() throws {
    let definitions = try BenchCatalog.loadDefinitions(from: projectRoot().appending(path: "BenchAssets/benchmarks"))
    #expect(definitions.map(\.testID) == ["A01", "C01"])
    #expect(definitions.allSatisfy { $0.referenceRequired })
    #expect(definitions.allSatisfy { !$0.script.isEmpty })
}

@Test func repeatedWarmRendersKeepUniqueEvidence() throws {
    let fake = StatefulFakeQwenClient()
    let adapter = Qwen3RendererAdapter(client: fake, availabilityOverride: .available, requestedBackend: "cpu")
    _ = try adapter.load()
    let store = BenchStore(rootURL: try temporaryDirectory())
    let runner = BenchmarkRunner(registry: .standard(overrides: [adapter]), store: store)
    let request = try qwenRequestForRB003()
    let first = try runner.render(request, rendererID: "qwen3")
    let second = try runner.render(request, rendererID: "qwen3")
    #expect(first.runID != second.runID)
    #expect(first.environmentSnapshot["model_reused"] == "true")
    #expect(second.environmentSnapshot["model_reused"] == "true")
    #expect(first.environmentSnapshot["render_index"] == "0")
    #expect(second.environmentSnapshot["render_index"] == "1")
    #expect(FileManager.default.fileExists(atPath: store.paths(testID: "C01", runID: first.runID, rendererID: "qwen3").resultFile.path))
    #expect(FileManager.default.fileExists(atPath: store.paths(testID: "C01", runID: second.runID, rendererID: "qwen3").resultFile.path))
}

private func qwenRequestForRB003() throws -> RendererRequest {
    let reference = try temporaryDirectory().appending(path: "reference.wav")
    try Data([1]).write(to: reference)
    return RendererRequest(testID: "C01", script: "Persistent fixture.", language: "en-GB",
        referenceAudioPaths: [reference.path], referenceAudioTranscripts: ["Reference transcript."])
}
