import Foundation
import RendererBenchCore
import VoxCPM2RendererAdapter

func value(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

func fail(_ message: String) -> Never { fputs("error: \(message)\n", stderr); exit(2) }

let arguments = Array(CommandLine.arguments.dropFirst())
guard let referencePath = value(after: "--reference-audio", in: arguments) else {
    fail("--reference-audio is required")
}
guard let referenceText = value(after: "--reference-text", in: arguments), !referenceText.isEmpty else {
    fail("--reference-text is required for continuation cloning")
}
guard let referenceAssetID = value(after: "--reference-asset-id", in: arguments), !referenceAssetID.isEmpty else {
    fail("--reference-asset-id is required")
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let definitionsURL = value(after: "--definitions", in: arguments).map {
    URL(fileURLWithPath: $0, relativeTo: root).standardizedFileURL
} ?? root.appending(path: "BenchAssets/benchmarks")
let dataURL = value(after: "--data", in: arguments).map {
    URL(fileURLWithPath: $0, relativeTo: root).standardizedFileURL
} ?? root.appending(path: "BenchData")
let referenceURL = URL(fileURLWithPath: referencePath, relativeTo: root).standardizedFileURL
let warmRuns = value(after: "--warm-runs", in: arguments).flatMap(Int.init) ?? 1
guard warmRuns >= 1 else { fail("--warm-runs must be at least 1") }
guard FileManager.default.fileExists(atPath: referenceURL.path) else { fail("reference audio does not exist") }

do {
    let definitions = try BenchCatalog.loadDefinitions(from: definitionsURL)
    guard let a01 = definitions.first(where: { $0.testID == "A01" }),
          let c01 = definitions.first(where: { $0.testID == "C01" }) else {
        fail("definitions directory must contain A01 and C01")
    }
    let adapter = VoxCPM2AdapterFactory.live(projectRoot: root)
    defer { _ = try? adapter.shutdown() }
    let health = adapter.healthCheck()
    guard health.status == .healthy else { fail("health: \(health.message)") }
    print("health: \(health.status.rawValue), actual=\(health.details["actual_backend"] ?? "unknown"), metal=\(health.details["metal_available"] ?? "unknown")")
    print("runtime: mlx=\(health.details["package_mlx"] ?? "unknown") mlx-audio=\(health.details["package_mlx-audio"] ?? "unknown") python=\(health.details["python_version"] ?? "unknown")")
    let load = try adapter.load()
    let loadState = load.workerState?.rawValue ?? "unknown"
    let importTime = load.pythonImportSeconds.map { String($0) } ?? "n/a"
    let modelTime = load.modelLoadSeconds.map { String($0) } ?? "n/a"
    let peakMemory = load.peakResidentMemoryBytes.map { String($0) } ?? "n/a"
    print("load: state=\(loadState) imports=\(importTime)s model=\(modelTime)s peak=\(peakMemory)")

    let runner = BenchmarkRunner(registry: .standard(overrides: [adapter]),
                                 store: BenchStore(rootURL: dataURL))
    let settings: [String: JSONValue] = [
        "inference_timesteps": .number(10),
        "cfg_value": .number(2.0),
        "warmup_patches": .number(0),
        "max_tokens": .number(2000),
        "reference_asset_id": .string(referenceAssetID)
    ]
    func render(_ definition: BenchmarkDefinition, label: String) throws {
        let request = RendererRequest(
            testID: definition.testID, script: definition.script, language: definition.language,
            directionText: definition.directionText, referenceAudioPaths: [referenceURL.path],
            referenceAudioTranscripts: [referenceText], rendererSettings: settings)
        let result = try runner.render(request, rendererID: "voxcpm2")
        guard result.success else { throw VoxCPM2AdapterError.worker(result.error ?? "unknown render failure") }
        let environment = result.environmentSnapshot
        print("\(label): run=\(result.runID) cold=\(environment["cold_start"] ?? "?") model_reused=\(environment["model_reused"] ?? "?") generation=\(environment["generation_seconds"] ?? "?")s total=\(String(format: "%.3f", result.renderTime))s duration=\(String(format: "%.3f", result.outputDuration ?? 0))s rtf=\(String(format: "%.3f", result.realtimeFactor ?? 0)) sr=\(environment["output_sample_rate"] ?? "?")")
        if let path = result.outputAudioPath { print("  output: \(path)") }
    }

    try render(a01, label: "A01 cold")
    try render(c01, label: "C01 warm")
    for index in 1...warmRuns { try render(a01, label: "A01 warm \(index)") }
    let shutdown = try adapter.shutdown()
    print("shutdown: \(shutdown.workerState?.rawValue ?? "unknown")")
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr); exit(1)
}
