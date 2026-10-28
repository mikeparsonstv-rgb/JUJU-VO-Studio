import ChatterboxRendererAdapter
import Foundation
import Qwen3RendererAdapter
import RB006Qualification
import RendererBenchCore
import VoxCPM2RendererAdapter

func value(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}
func fail(_ message: String) -> Never { fputs("error: \(message)\n", stderr); exit(2) }

let arguments = Array(CommandLine.arguments.dropFirst())
let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let manifestURL = URL(fileURLWithPath: value(after: "--manifest", in: arguments) ?? "BenchAssets/qualifications/RB006-Birmingham.json", relativeTo: projectRoot).standardizedFileURL
let localURL = URL(fileURLWithPath: value(after: "--local-assets", in: arguments) ?? "BenchAssets/rb006-local-assets.json", relativeTo: projectRoot).standardizedFileURL
let dataURL = URL(fileURLWithPath: value(after: "--data", in: arguments) ?? "BenchData/qualifications/RB006-Birmingham-Baseline/authoritative", relativeTo: projectRoot).standardizedFileURL
let selectedRenderer = value(after: "--renderer", in: arguments)
guard selectedRenderer == nil || ["qwen3", "voxcpm2", "chatterbox"].contains(selectedRenderer!) else {
    fail("--renderer must be qwen3, voxcpm2, or chatterbox")
}

do {
    let manifest = try QualificationManifest.load(from: manifestURL)
    try manifest.validate()
    let localAssets = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: localURL))
    try QualificationProvenance.verify(manifest: manifest, localAssets: localAssets, root: projectRoot)
    let transcriptMap = Dictionary(uniqueKeysWithValues: try manifest.transcripts.map { transcript in
        let url = URL(fileURLWithPath: transcript.path, relativeTo: projectRoot).standardizedFileURL
        return (transcript.id, try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
    })
    try FileManager.default.createDirectory(at: dataURL.appending(path: "metadata"), withIntermediateDirectories: true)

    func requests(settings: [String: JSONValue], seed: UInt64?) throws -> [(CrossHoldoutDirection, Int, RendererRequest)] {
        var values: [(CrossHoldoutDirection, Int, RendererRequest)] = []
        for direction in manifest.directions {
            guard let reference = localAssets[direction.conditioningAssetID],
                  let referenceText = transcriptMap[direction.conditioningTranscriptID],
                  let targetText = transcriptMap[direction.targetTranscriptID] else {
                throw QualificationError.missingMapping(direction.id)
            }
            for run in 1...manifest.runsPerDirection {
                var native = settings
                native["reference_asset_id"] = .string(direction.conditioningAssetID)
                values.append((direction, run, RendererRequest(
                    testID: direction.id, script: targetText, language: manifest.language,
                    referenceAudioPaths: [reference], referenceAudioTranscripts: [referenceText],
                    seed: seed, rendererSettings: native)))
            }
        }
        return values
    }

    func perform(adapter: any RendererAdapter, rendererID: String,
                 loadEnvironment: [String: String], settings: [String: JSONValue], seed: UInt64?) throws {
        let storeRoot = dataURL.appending(path: "renders/\(rendererID)")
        let runner = BenchmarkRunner(registry: .standard(overrides: [adapter]), store: BenchStore(rootURL: storeRoot))
        var records: [[String: Any]] = []
        for (direction, iteration, request) in try requests(settings: settings, seed: seed) {
            let result = try runner.render(request, rendererID: rendererID)
            guard result.success, let output = result.outputAudioPath else {
                throw NSError(domain: "RB006", code: 1, userInfo: [NSLocalizedDescriptionKey: result.error ?? "render failed"])
            }
            let record: [String: Any] = [
                "direction_id": direction.id, "iteration": iteration,
                "run_id": result.runID, "renderer_id": rendererID,
                "conditioning_asset_id": direction.conditioningAssetID,
                "conditioning_transcript_id": direction.conditioningTranscriptID,
                "target_transcript_id": direction.targetTranscriptID,
                "ground_truth_asset_id": direction.groundTruthAssetID,
                "output_audio": output, "duration_seconds": result.outputDuration ?? 0,
                "render_time_seconds": result.renderTime, "realtime_factor": result.realtimeFactor ?? 0,
                "result_json": storeRoot.appending(path: "runs/\(direction.id)/\(result.runID)/\(rendererID)/result.json").path
            ]
            records.append(record)
            print("\(rendererID) \(direction.id) run\(iteration): id=\(result.runID) time=\(String(format: "%.3f", result.renderTime))s duration=\(String(format: "%.3f", result.outputDuration ?? 0))s")
        }
        let summary: [String: Any] = [
            "schema_version": 1, "qualification_id": manifest.qualificationID,
            "renderer_id": rendererID, "baseline_policy": manifest.baselinePolicy,
            "load_environment": loadEnvironment, "renders": records
        ]
        let data = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: dataURL.appending(path: "metadata/\(rendererID)-session.json"), options: .atomic)
    }

    for rendererID in manifest.rendererIDs where selectedRenderer == nil || selectedRenderer == rendererID {
        switch rendererID {
        case "qwen3":
            let adapter = Qwen3AdapterFactory.persistent(projectRoot: projectRoot, backend: "mps")
            let health = adapter.healthCheck(); guard health.status == .healthy else { fail(health.message) }
            let load = try adapter.load()
            try perform(adapter: adapter, rendererID: rendererID, loadEnvironment: load.environmentSnapshot,
                        settings: ["do_sample": .bool(true), "temperature": .number(0.9), "top_k": .number(50), "top_p": .number(1.0)], seed: 1_003)
            _ = try adapter.shutdown()
        case "voxcpm2":
            let adapter = VoxCPM2AdapterFactory.live(projectRoot: projectRoot)
            let health = adapter.healthCheck(); guard health.status == .healthy else { fail(health.message) }
            let load = try adapter.load()
            try perform(adapter: adapter, rendererID: rendererID, loadEnvironment: load.environmentSnapshot,
                        settings: ["inference_timesteps": .number(10), "cfg_value": .number(2), "warmup_patches": .number(0), "max_tokens": .number(2000)], seed: nil)
            _ = try adapter.shutdown()
        case "chatterbox":
            let adapter = ChatterboxAdapterFactory.live(projectRoot: projectRoot)
            let health = adapter.healthCheck(); guard health.status == .healthy else { fail(health.message) }
            let load = try adapter.load()
            try perform(adapter: adapter, rendererID: rendererID, loadEnvironment: load.environmentSnapshot,
                        settings: ["exaggeration": .number(0.5), "cfg_weight": .number(0.5), "temperature": .number(0.8), "repetition_penalty": .number(1.2), "min_p": .number(0.05), "top_p": .number(1.0)], seed: nil)
            _ = try adapter.shutdown()
        default: fatalError("validated renderer escaped policy")
        }
    }
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr); exit(1)
}
