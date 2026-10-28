import Foundation
import Qwen3RendererAdapter
import RendererBenchCore

func value(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

func fail(_ message: String) -> Never {
    fputs("error: \(message)\n", stderr); exit(2)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let backend = value(after: "--backend", in: arguments), ["auto", "mps", "cpu"].contains(backend) else {
    fail("--backend must be auto, mps, or cpu")
}
guard let referencePath = value(after: "--reference-audio", in: arguments) else {
    fail("--reference-audio is required")
}
guard let referenceText = value(after: "--reference-text", in: arguments), !referenceText.isEmpty else {
    fail("--reference-text is required for the controlled ICL path")
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let definitionsURL = value(after: "--definitions", in: arguments).map { URL(fileURLWithPath: $0, relativeTo: root).standardizedFileURL }
    ?? root.appending(path: "BenchAssets/benchmarks")
let dataURL = value(after: "--data", in: arguments).map { URL(fileURLWithPath: $0, relativeTo: root).standardizedFileURL }
    ?? root.appending(path: "BenchData")
let referenceURL = URL(fileURLWithPath: referencePath, relativeTo: root).standardizedFileURL
let referenceAssetID = value(after: "--reference-asset-id", in: arguments)
let warmRuns = value(after: "--warm-runs", in: arguments).flatMap(Int.init) ?? 1
guard warmRuns >= 1 else { fail("--warm-runs must be at least 1") }
guard FileManager.default.fileExists(atPath: referenceURL.path) else { fail("reference audio does not exist") }

do {
    let definitions = try BenchCatalog.loadDefinitions(from: definitionsURL)
    guard let a01 = definitions.first(where: { $0.testID == "A01" }),
          let c01 = definitions.first(where: { $0.testID == "C01" }) else {
        fail("definitions directory must contain A01 and C01")
    }
    let adapter = Qwen3AdapterFactory.persistent(projectRoot: root, backend: backend)
    defer { _ = try? adapter.shutdown() }
    let health = adapter.healthCheck()
    guard health.status == .healthy else { fail("health: \(health.message)") }
    print("health: \(health.status.rawValue), requested=\(backend), actual=\(health.details["actual_backend"] ?? health.details["compute_device"] ?? "unknown")")
    let load = try adapter.load()
    let loadState = load.workerState?.rawValue ?? "unknown"
    let importTime = load.pythonImportSeconds.map { String($0) } ?? "n/a"
    let modelTime = load.modelLoadSeconds.map { String($0) } ?? "n/a"
    print("load: state=\(loadState) imports=\(importTime)s model=\(modelTime)s")

    let runner = BenchmarkRunner(registry: .standard(overrides: [adapter]), store: BenchStore(rootURL: dataURL))
    let settings: [String: JSONValue] = [
        "do_sample": .bool(true), "temperature": .number(0.9),
        "top_k": .number(50), "top_p": .number(1.0)
    ].merging(referenceAssetID.map { ["reference_asset_id": .string($0)] } ?? [:]) { current, _ in current }
    func render(_ definition: BenchmarkDefinition, label: String) throws {
        let request = RendererRequest(testID: definition.testID, script: definition.script,
            language: definition.language, directionText: definition.directionText,
            referenceAudioPaths: [referenceURL.path], referenceAudioTranscripts: [referenceText],
            seed: 1_003, rendererSettings: settings)
        let result = try runner.render(request, rendererID: "qwen3")
        guard result.success else { throw Qwen3AdapterError.worker(result.error ?? "unknown render failure") }
        let environment = result.environmentSnapshot
        print("\(label): run=\(result.runID) cold=\(environment["cold_start"] ?? "?") model_reused=\(environment["model_reused"] ?? "?") generation=\(environment["generation_seconds"] ?? "?")s total=\(String(format: "%.3f", result.renderTime))s duration=\(String(format: "%.3f", result.outputDuration ?? 0))s rtf=\(String(format: "%.3f", result.realtimeFactor ?? 0))")
        if let path = result.outputAudioPath { print("  output: \(path)") }
    }

    try render(a01, label: "A01 cold")
    try render(c01, label: "C01 warm")
    for index in 1...warmRuns { try render(a01, label: "A01 warm \(index)") }
    let shutdown = try adapter.shutdown()
    print("shutdown: \(shutdown.workerState?.rawValue ?? "unknown")")
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
