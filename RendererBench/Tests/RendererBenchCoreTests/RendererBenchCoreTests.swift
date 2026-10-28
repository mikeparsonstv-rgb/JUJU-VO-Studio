import Foundation
import Testing
@testable import RendererBenchCore

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "RendererBenchTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(T.self, from: encoder.encode(value))
}

@Test func requestSerializationRoundTrip() throws {
    let request = RendererRequest(testID: "B01", script: "New boosters", language: "en-GB",
        directionText: "Articulate boosters", referenceAudioPaths: ["voice.wav"],
        guideAudioPath: "guide.wav", seed: 42, targetDuration: 1.5,
        rendererSettings: ["temperature": .number(0.4), "enabled": .bool(true)])
    #expect(try roundTrip(request) == request)
}

@Test func resultSerializationRoundTrip() throws {
    let descriptor = MockRendererAdapter().descriptor
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let result = RendererResult(schemaVersion: 1, runID: "run", testID: "A01", rendererID: "mock",
        rendererVersion: "1", modelCheckpoint: nil, settingsSnapshot: [:], descriptorSnapshot: descriptor,
        capabilitySnapshot: descriptor.capabilities, outputAudioPath: "/tmp/output.wav", outputDuration: 1,
        renderStartedAt: date, renderCompletedAt: date, renderTime: 0.1, firstAudioLatency: nil,
        realtimeFactor: 0.1, success: true, error: nil, environmentSnapshot: ["os": "test"])
    #expect(try roundTrip(result) == result)
}

@Test func capabilitySerialization() throws {
    let value = RendererCapabilities(textToSpeech: true, guidePerformanceTransfer: true,
                                     deterministicSeed: true, multilingual: true, local: true)
    #expect(try roundTrip(value) == value)
}

@Test func registryLookupAndActiveLimit() {
    let registry = RendererRegistry.standard()
    #expect(registry.adapter(id: "qwen3") != nil)
    #expect(registry.adapter(id: "mock") != nil)
    #expect(registry.adapter(id: "unknown") == nil)
    #expect(registry.activeRendererDescriptors.map(\.id) == ["chatterbox", "microsoft", "moss", "qwen3", "voxcpm2"])
}

@Test func mockRenderProducesValidWAV() throws {
    let output = try temporaryDirectory().appending(path: "output.wav")
    let rendered = try MockRendererAdapter().render(RendererRequest(testID: "A01", script: "Test", language: "en-GB"), to: output)
    let data = try Data(contentsOf: output)
    #expect(data.count == 96_044)
    #expect(String(data: data[0..<4], encoding: .ascii) == "RIFF")
    #expect(String(data: data[8..<12], encoding: .ascii) == "WAVE")
    #expect(rendered.duration == 1)
}

@Test func requestAndResultPersistence() throws {
    let store = try BenchStore(rootURL: temporaryDirectory())
    let runner = BenchmarkRunner(registry: .standard(), store: store)
    let request = RendererRequest(testID: "A01", script: "Test", language: "en-GB")
    let result = try runner.render(request, rendererID: "mock", runID: "run-one")
    let paths = store.paths(testID: "A01", runID: "run-one", rendererID: "mock")
    #expect(FileManager.default.fileExists(atPath: paths.requestFile.path))
    #expect(FileManager.default.fileExists(atPath: paths.resultFile.path))
    #expect(try store.read(RendererRequest.self, from: paths.requestFile) == request)
    #expect(try store.read(RendererResult.self, from: paths.resultFile) == result)
}

@Test func failedRendererIsCapturedAndPersisted() throws {
    let store = try BenchStore(rootURL: temporaryDirectory())
    let runner = BenchmarkRunner(registry: .standard(), store: store)
    let request = RendererRequest(testID: "A01", script: "Test", language: "en-GB")
    let result = try runner.render(request, rendererID: "qwen3", runID: "failure")
    #expect(!result.success)
    #expect(result.error?.contains("unavailable") == true)
    #expect(result.outputAudioPath == nil)
    let paths = store.paths(testID: "A01", runID: "failure", rendererID: "qwen3")
    #expect(FileManager.default.fileExists(atPath: paths.resultFile.path))
}

@Test func sequentialRunsDoNotOverwrite() throws {
    let store = try BenchStore(rootURL: temporaryDirectory())
    let runner = BenchmarkRunner(registry: .standard(), store: store)
    let request = RendererRequest(testID: "A01", script: "Test", language: "en-GB")
    let first = try runner.render(request, rendererID: "mock")
    let second = try runner.render(request, rendererID: "mock")
    #expect(first.runID != second.runID)
    let firstPaths = store.paths(testID: "A01", runID: first.runID, rendererID: "mock")
    let secondPaths = store.paths(testID: "A01", runID: second.runID, rendererID: "mock")
    #expect(firstPaths.resultFile != secondPaths.resultFile)
    #expect(FileManager.default.fileExists(atPath: firstPaths.outputAudioFile.path))
    #expect(FileManager.default.fileExists(atPath: secondPaths.outputAudioFile.path))
}
