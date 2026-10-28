import Foundation

public struct RunPaths: Equatable, Sendable {
    public let runDirectory, requestFile, rendererDirectory, resultFile, outputAudioFile: URL
}

public struct BenchStore: Sendable {
    public let rootURL: URL
    public init(rootURL: URL) { self.rootURL = rootURL }
    public func paths(testID: String, runID: String, rendererID: String) -> RunPaths {
        let run = rootURL.appending(path: "runs/\(Self.safe(testID))/\(Self.safe(runID))", directoryHint: .isDirectory)
        let renderer = run.appending(path: Self.safe(rendererID), directoryHint: .isDirectory)
        return RunPaths(runDirectory: run, requestFile: run.appending(path: "request.json"),
                        rendererDirectory: renderer, resultFile: renderer.appending(path: "result.json"),
                        outputAudioFile: renderer.appending(path: "output.wav"))
    }
    public func prepare(_ paths: RunPaths) throws {
        try FileManager.default.createDirectory(at: paths.rendererDirectory, withIntermediateDirectories: true)
    }
    public func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
    public func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: Data(contentsOf: url))
    }
    private static func safe(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let result = String(value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" })
        return result.isEmpty ? "untitled" : result
    }
}
