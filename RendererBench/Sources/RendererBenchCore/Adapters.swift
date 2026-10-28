import Foundation

public protocol RendererAdapter: Sendable {
    var descriptor: RendererDescriptor { get }
    func healthCheck() -> RendererHealth
    func render(_ request: RendererRequest, to outputURL: URL) throws -> RenderedAudio
}

public protocol RendererFailureMetadata: Error {
    var environmentSnapshot: [String: String] { get }
}

public enum RendererAdapterError: Error, LocalizedError, Equatable {
    case unavailable(rendererID: String, reason: String)
    public var errorDescription: String? {
        switch self {
        case .unavailable(let id, let reason): "Renderer '\(id)' is unavailable: \(reason)"
        }
    }
}

public struct UnavailableRendererAdapter: RendererAdapter {
    public let descriptor: RendererDescriptor
    private let reason: String
    public init(descriptor: RendererDescriptor, reason: String = "Adapter is a placeholder in RB-001") {
        self.descriptor = descriptor; self.reason = reason
    }
    public func healthCheck() -> RendererHealth { RendererHealth(status: .unavailable, message: reason) }
    public func render(_ request: RendererRequest, to outputURL: URL) throws -> RenderedAudio {
        throw RendererAdapterError.unavailable(rendererID: descriptor.id, reason: reason)
    }
}

public struct MockRendererAdapter: RendererAdapter {
    public let descriptor = RendererDescriptor(
        id: "mock", displayName: "Deterministic Mock (test fixture)", location: .local,
        availability: .available, rendererVersion: "1.0.0",
        capabilities: RendererCapabilities(textToSpeech: true, deterministicSeed: true, local: true),
        isTestFixture: true
    )
    public init() {}
    public func healthCheck() -> RendererHealth {
        RendererHealth(status: .healthy, message: "Built-in deterministic WAV generator is ready")
    }
    public func render(_ request: RendererRequest, to outputURL: URL) throws -> RenderedAudio {
        let duration = 1.0, frequency = 440.0
        let sampleRate = 48_000, sampleCount = 48_000
        var pcm = Data(capacity: sampleCount * 2)
        for sample in 0..<sampleCount {
            let envelope = min(1.0, Double(sample) / 480.0, Double(sampleCount - sample) / 480.0)
            let wave = sin(2.0 * .pi * frequency * Double(sample) / Double(sampleRate))
            var value = Int16(wave * envelope * Double(Int16.max) * 0.2).littleEndian
            Swift.withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
        }
        var wav = Data()
        wav.appendASCII("RIFF"); wav.appendUInt32LE(UInt32(36 + pcm.count)); wav.appendASCII("WAVEfmt ")
        wav.appendUInt32LE(16); wav.appendUInt16LE(1); wav.appendUInt16LE(1)
        wav.appendUInt32LE(UInt32(sampleRate)); wav.appendUInt32LE(UInt32(sampleRate * 2))
        wav.appendUInt16LE(2); wav.appendUInt16LE(16); wav.appendASCII("data")
        wav.appendUInt32LE(UInt32(pcm.count)); wav.append(pcm)
        try wav.write(to: outputURL, options: .atomic)
        return RenderedAudio(duration: duration)
    }
}

private extension Data {
    mutating func appendASCII(_ value: String) { append(value.data(using: .ascii)!) }
    mutating func appendUInt16LE(_ number: UInt16) {
        var number = number.littleEndian
        Swift.withUnsafeBytes(of: &number) { append(contentsOf: $0) }
    }
    mutating func appendUInt32LE(_ number: UInt32) {
        var number = number.littleEndian
        Swift.withUnsafeBytes(of: &number) { append(contentsOf: $0) }
    }
}
