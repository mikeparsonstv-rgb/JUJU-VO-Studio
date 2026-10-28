import Darwin
import Foundation

public protocol QwenWorkerClient: Sendable {
    func send(_ request: QwenWorkerRequest) throws -> QwenWorkerResponse
}

public enum QwenWorkerClientError: Error, LocalizedError {
    case missingExecutable(String)
    case missingWorker(String)
    case launch(String)
    case timeout(TimeInterval)
    case invalidResponse(String)
    case unexpectedExit(String)

    public var errorDescription: String? {
        switch self {
        case .missingExecutable(let path): "Qwen Python environment is missing at \(path). Run scripts/setup-qwen3.sh."
        case .missingWorker(let path): "Qwen worker script is missing at \(path)."
        case .launch(let reason): "Qwen worker could not launch: \(reason)"
        case .timeout(let seconds): "Qwen worker exceeded its \(Int(seconds))-second timeout"
        case .invalidResponse(let reason): "Qwen worker returned invalid protocol output: \(reason)"
        case .unexpectedExit(let reason): "Qwen worker exited unexpectedly: \(reason)"
        }
    }
}

public struct LiveQwenWorkerClient: QwenWorkerClient {
    public let pythonURL: URL
    public let workerURL: URL
    public let timeout: TimeInterval
    public let environment: [String: String]

    public init(pythonURL: URL, workerURL: URL, timeout: TimeInterval = 900,
                environment: [String: String] = [:]) {
        self.pythonURL = pythonURL; self.workerURL = workerURL; self.timeout = timeout
        self.environment = environment
    }

    public func send(_ request: QwenWorkerRequest) throws -> QwenWorkerResponse {
        guard FileManager.default.isExecutableFile(atPath: pythonURL.path) else {
            throw QwenWorkerClientError.missingExecutable(pythonURL.path)
        }
        guard FileManager.default.fileExists(atPath: workerURL.path) else {
            throw QwenWorkerClientError.missingWorker(workerURL.path)
        }
        let scratch = FileManager.default.temporaryDirectory.appending(path: "qwen-worker-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let stdoutURL = scratch.appending(path: "stdout.json")
        let stderrURL = scratch.appending(path: "stderr.log")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer { try? stdoutHandle.close(); try? stderrHandle.close() }

        let inputPipe = Pipe()
        let process = Process()
        process.executableURL = pythonURL
        process.arguments = [workerURL.path, "--one-shot"]
        process.standardInput = inputPipe
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, configured in configured }
        do { try process.run() } catch { throw QwenWorkerClientError.launch(error.localizedDescription) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try inputPipe.fileHandleForWriting.write(contentsOf: encoder.encode(request))
        try inputPipe.fileHandleForWriting.write(contentsOf: Data([0x0A]))
        try inputPipe.fileHandleForWriting.close()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            process.terminate()
            let terminationDeadline = Date().addingTimeInterval(2)
            while process.isRunning && Date() < terminationDeadline { Thread.sleep(forTimeInterval: 0.05) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            throw QwenWorkerClientError.timeout(timeout)
        }
        try stdoutHandle.synchronize(); try stderrHandle.synchronize()
        let stdout = try Data(contentsOf: stdoutURL)
        let stderr = String(data: try Data(contentsOf: stderrURL), encoding: .utf8) ?? ""
        guard !stdout.isEmpty else {
            throw QwenWorkerClientError.invalidResponse("empty stdout; stderr: \(stderr.suffix(2_000))")
        }
        do {
            let decoder = JSONDecoder()
            let response = try decoder.decode(QwenWorkerResponse.self, from: stdout)
            guard response.protocolVersion == Qwen3Constants.workerProtocolVersion else {
                throw QwenWorkerClientError.invalidResponse("unsupported protocol version \(response.protocolVersion)")
            }
            guard response.requestID == request.requestID else {
                throw QwenWorkerClientError.invalidResponse("request ID mismatch")
            }
            return response
        } catch let error as QwenWorkerClientError { throw error }
        catch {
            throw QwenWorkerClientError.invalidResponse("\(error.localizedDescription); stderr: \(stderr.suffix(2_000))")
        }
    }
}
