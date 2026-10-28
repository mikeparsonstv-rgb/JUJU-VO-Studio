import Foundation

public protocol VoxCPM2WorkerClient: Sendable {
    func send(_ request: VoxCPM2WorkerRequest) throws -> VoxCPM2WorkerResponse
}

public enum VoxCPM2WorkerClientError: Error, LocalizedError {
    case missingExecutable(String), missingWorker(String), launch(String)
    case timeout(TimeInterval), invalidResponse(String), unexpectedExit(String)

    public var errorDescription: String? {
        switch self {
        case .missingExecutable(let path): "VoxCPM2 Python environment is missing at \(path). Run scripts/setup-voxcpm2.sh."
        case .missingWorker(let path): "VoxCPM2 worker script is missing at \(path)."
        case .launch(let reason): "VoxCPM2 worker could not launch: \(reason)"
        case .timeout(let seconds): "VoxCPM2 worker exceeded its \(Int(seconds))-second timeout"
        case .invalidResponse(let reason): "VoxCPM2 worker returned invalid protocol output: \(reason)"
        case .unexpectedExit(let reason): "VoxCPM2 worker exited unexpectedly: \(reason)"
        }
    }
}
