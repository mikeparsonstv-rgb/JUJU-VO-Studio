import Foundation
import RendererBenchCore
import Qwen3RendererAdapter
import VoxCPM2RendererAdapter
import ChatterboxRendererAdapter

func usage() {
    print("""
    Renderer Bench v0.1
      renderer-bench list
      renderer-bench health <renderer-id>
      renderer-bench render --script <text> [--test-id <id>] [--language <tag>]
                            [--direction <text>] [--renderer <id>] [--data <path>]
                            [--reference-audio <path>] [--reference-text <text>]
      renderer-bench play <output.wav>

    The working RB-001 renderer is 'mock'. The five candidate descriptors are placeholders.
    """)
}
func value(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

let arguments = Array(CommandLine.arguments.dropFirst())
let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let registry = RendererRegistry.standard(overrides: [
    Qwen3AdapterFactory.live(projectRoot: projectRoot),
    VoxCPM2AdapterFactory.live(projectRoot: projectRoot),
    ChatterboxAdapterFactory.live(projectRoot: projectRoot)
])
guard let command = arguments.first else { usage(); exit(0) }

switch command {
case "list":
    for descriptor in registry.descriptors {
        let fixture = descriptor.isTestFixture ? " [test fixture]" : ""
        print("\(descriptor.id)\t\(descriptor.availability.rawValue)\t\(descriptor.location.rawValue)\t\(descriptor.displayName)\(fixture)")
    }
case "health":
    guard arguments.count == 2 else { usage(); exit(2) }
    guard let adapter = registry.adapter(id: arguments[1]) else {
        fputs("error: unknown renderer '\(arguments[1])'\n", stderr); exit(2)
    }
    let health = adapter.healthCheck()
    print("status: \(health.status.rawValue)")
    print("message: \(health.message)")
    for key in health.details.keys.sorted() { print("\(key): \(health.details[key]!)") }
    exit(health.status == .healthy ? 0 : 1)
case "render":
    guard let script = value(after: "--script", in: arguments), !script.isEmpty else {
        fputs("error: --script is required\n", stderr); exit(2)
    }
    let referenceAudio = value(after: "--reference-audio", in: arguments)
    let referenceText = value(after: "--reference-text", in: arguments)
    let request = RendererRequest(
        testID: value(after: "--test-id", in: arguments) ?? "RB001-manual",
        script: script,
        language: value(after: "--language", in: arguments) ?? "en-GB",
        directionText: value(after: "--direction", in: arguments) ?? "",
        referenceAudioPaths: referenceAudio.map { [URL(fileURLWithPath: $0).standardizedFileURL.path] } ?? [],
        referenceAudioTranscripts: referenceText.map { [$0] })
    let rendererID = value(after: "--renderer", in: arguments) ?? "mock"
    let dataPath = value(after: "--data", in: arguments) ?? "BenchData"
    let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let dataURL = URL(fileURLWithPath: dataPath, relativeTo: base).standardizedFileURL
    let runner = BenchmarkRunner(registry: registry, store: BenchStore(rootURL: dataURL))
    do {
        let result = try runner.render(request, rendererID: rendererID)
        print("status: \(result.success ? "success" : "error")")
        print("run id: \(result.runID)")
        print("render time: \(String(format: "%.4f", result.renderTime)) s")
        if let duration = result.outputDuration { print("duration: \(String(format: "%.3f", duration)) s") }
        if let path = result.outputAudioPath { print("audio: \(path)") }
        if let error = result.error { print("error: \(error)") }
        exit(result.success ? 0 : 1)
    } catch {
        fputs("error: \(error.localizedDescription)\n", stderr); exit(2)
    }
case "play":
    guard arguments.count == 2 else { usage(); exit(2) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
    process.arguments = [arguments[1]]
    do { try process.run(); process.waitUntilExit(); exit(process.terminationStatus) }
    catch { fputs("error: \(error.localizedDescription)\n", stderr); exit(2) }
default:
    usage(); exit(2)
}
