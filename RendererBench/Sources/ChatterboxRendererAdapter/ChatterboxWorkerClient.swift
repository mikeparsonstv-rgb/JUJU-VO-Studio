import Foundation

public protocol ChatterboxWorkerClient: Sendable {
    func send(_ request: ChatterboxWorkerRequest) throws -> ChatterboxWorkerResponse
}

public enum ChatterboxWorkerClientError: Error, LocalizedError {
    case missingExecutable(String), missingWorker(String), launch(String)
    case timeout(TimeInterval), invalidResponse(String), unexpectedExit(String)

    public var errorDescription: String? {
        switch self {
        case .missingExecutable(let path): "Chatterbox Python environment is missing at \(path). Run scripts/setup-chatterbox.sh."
        case .missingWorker(let path): "Chatterbox worker script is missing at \(path)."
        case .launch(let reason): "Chatterbox worker could not launch: \(reason)"
        case .timeout(let seconds): "Chatterbox worker exceeded its \(Int(seconds))-second timeout"
        case .invalidResponse(let reason): "Chatterbox worker returned invalid protocol output: \(reason)"
        case .unexpectedExit(let reason): "Chatterbox worker exited unexpectedly: \(reason)"
        }
    }
}

