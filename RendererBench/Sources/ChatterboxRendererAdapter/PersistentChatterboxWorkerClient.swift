import Darwin
import Foundation

public final class PersistentChatterboxWorkerClient: ChatterboxWorkerClient, @unchecked Sendable {
    public let pythonURL: URL
    public let workerURL: URL
    public let timeout: TimeInterval
    public let environment: [String: String]

    private let lock = NSLock()
    private var process: Process?
    private var inputHandle, outputHandle, stderrHandle: FileHandle?
    private var stderrURL, scratchURL: URL?
    private var outputBuffer = Data()
    private var internalState: ChatterboxWorkerState = .stopped

    public init(pythonURL: URL, workerURL: URL, timeout: TimeInterval = 1_800,
                environment: [String: String] = [:]) {
        self.pythonURL = pythonURL; self.workerURL = workerURL; self.timeout = timeout
        self.environment = environment
    }

    deinit { lock.lock(); cleanupLocked(force: true); lock.unlock() }

    public var state: ChatterboxWorkerState { lock.lock(); defer { lock.unlock() }; return internalState }
    public var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return process?.isRunning == true }

    public func send(_ request: ChatterboxWorkerRequest) throws -> ChatterboxWorkerResponse {
        lock.lock(); defer { lock.unlock() }
        if request.operation == .shutdown, process?.isRunning != true {
            internalState = .stopped
            return ChatterboxWorkerResponse(requestID: request.requestID, success: true,
                                         workerState: .stopped, workerReused: false)
        }
        do {
            if process?.isRunning != true { try startLocked() }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            var payload = try encoder.encode(request); payload.append(0x0A)
            guard let inputHandle else { throw ChatterboxWorkerClientError.unexpectedExit("stdin is closed") }
            try inputHandle.write(contentsOf: payload)
            let responseData = try readLineLocked(timeout: timeout)
            let response: ChatterboxWorkerResponse
            do { response = try JSONDecoder().decode(ChatterboxWorkerResponse.self, from: responseData) }
            catch { throw ChatterboxWorkerClientError.invalidResponse("\(error.localizedDescription); stderr: \(stderrTailLocked())") }
            guard response.protocolVersion == ChatterboxConstants.workerProtocolVersion else {
                throw ChatterboxWorkerClientError.invalidResponse("unsupported protocol version \(response.protocolVersion)")
            }
            guard response.requestID == request.requestID else {
                throw ChatterboxWorkerClientError.invalidResponse("request ID mismatch")
            }
            internalState = response.workerState ?? (response.success ? .readyUnloaded : .failed)
            if request.operation == .shutdown {
                waitForExitLocked(seconds: 2); cleanupLocked(force: process?.isRunning == true); internalState = .stopped
            } else if internalState == .failed { cleanupLocked(force: true) }
            return response
        } catch {
            internalState = .failed; cleanupLocked(force: true); throw error
        }
    }

    private func startLocked() throws {
        guard FileManager.default.isExecutableFile(atPath: pythonURL.path) else {
            throw ChatterboxWorkerClientError.missingExecutable(pythonURL.path)
        }
        guard FileManager.default.fileExists(atPath: workerURL.path) else {
            throw ChatterboxWorkerClientError.missingWorker(workerURL.path)
        }
        let scratch = FileManager.default.temporaryDirectory.appending(path: "chatterbox-persistent-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let stderrURL = scratch.appending(path: "stderr.log")
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        let inputPipe = Pipe(), outputPipe = Pipe(), process = Process()
        process.executableURL = pythonURL; process.arguments = [workerURL.path, "--persistent"]
        process.standardInput = inputPipe; process.standardOutput = outputPipe; process.standardError = stderrHandle
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, configured in configured }
        do { try process.run() }
        catch {
            try? stderrHandle.close(); try? FileManager.default.removeItem(at: scratch)
            throw ChatterboxWorkerClientError.launch(error.localizedDescription)
        }
        self.process = process; inputHandle = inputPipe.fileHandleForWriting
        outputHandle = outputPipe.fileHandleForReading; self.stderrHandle = stderrHandle
        self.stderrURL = stderrURL; scratchURL = scratch
        outputBuffer.removeAll(keepingCapacity: true); internalState = .starting
    }

    private func readLineLocked(timeout: TimeInterval) throws -> Data {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let newline = outputBuffer.firstIndex(of: 0x0A) {
                let line = outputBuffer[..<newline]; outputBuffer.removeSubrange(...newline); return Data(line)
            }
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { throw ChatterboxWorkerClientError.timeout(timeout) }
            guard let outputHandle else { throw ChatterboxWorkerClientError.unexpectedExit("stdout is closed") }
            var descriptor = pollfd(fd: outputHandle.fileDescriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
            let status = Darwin.poll(&descriptor, 1, Int32(min(remaining * 1_000, 250)))
            if status < 0, errno != EINTR {
                throw ChatterboxWorkerClientError.unexpectedExit(String(cString: strerror(errno)))
            }
            if status > 0, descriptor.revents & Int16(POLLIN | POLLHUP) != 0 {
                var bytes = [UInt8](repeating: 0, count: 65_536)
                let count = Darwin.read(outputHandle.fileDescriptor, &bytes, bytes.count)
                if count < 0, errno == EINTR { continue }
                if count < 0 { throw ChatterboxWorkerClientError.unexpectedExit(String(cString: strerror(errno))) }
                if count == 0 { throw ChatterboxWorkerClientError.unexpectedExit(stderrTailLocked()) }
                outputBuffer.append(contentsOf: bytes.prefix(count))
            } else if process?.isRunning != true {
                throw ChatterboxWorkerClientError.unexpectedExit(stderrTailLocked())
            }
        }
    }

    private func stderrTailLocked() -> String {
        guard let stderrURL, let data = try? Data(contentsOf: stderrURL),
              let text = String(data: data, encoding: .utf8) else { return "no stderr" }
        return String(text.suffix(2_000))
    }

    private func waitForExitLocked(seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while process?.isRunning == true, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
    }

    private func cleanupLocked(force: Bool) {
        try? inputHandle?.close()
        if force, process?.isRunning == true {
            process?.terminate(); waitForExitLocked(seconds: 1)
            if let process, process.isRunning { kill(process.processIdentifier, SIGKILL); waitForExitLocked(seconds: 1) }
        }
        try? outputHandle?.close(); try? stderrHandle?.close()
        if let scratchURL { try? FileManager.default.removeItem(at: scratchURL) }
        process = nil; inputHandle = nil; outputHandle = nil; stderrHandle = nil
        stderrURL = nil; scratchURL = nil; outputBuffer.removeAll(keepingCapacity: false)
    }
}

