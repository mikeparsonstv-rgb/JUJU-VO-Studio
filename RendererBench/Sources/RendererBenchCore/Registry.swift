public struct RendererRegistry: Sendable {
    private let adapters: [String: any RendererAdapter]
    public init(adapters: [any RendererAdapter]) {
        self.adapters = Dictionary(uniqueKeysWithValues: adapters.map { ($0.descriptor.id, $0) })
    }
    public func adapter(id: String) -> (any RendererAdapter)? { adapters[id] }
    public var descriptors: [RendererDescriptor] { adapters.values.map(\.descriptor).sorted { $0.id < $1.id } }
    public var activeRendererDescriptors: [RendererDescriptor] { descriptors.filter { !$0.isTestFixture } }

    public static func standard(overrides: [any RendererAdapter] = []) -> RendererRegistry {
        let entries: [(String, String, RendererLocation, RendererCapabilities)] = [
            ("qwen3", "Qwen3-TTS", .local, RendererCapabilities(
                textToSpeech: true, suppliedVoice: true, voiceCloning: true,
                naturalLanguageDirection: true, deterministicSeed: true, multilingual: true, local: true)),
            ("voxcpm2", "VoxCPM2", .local, RendererCapabilities(
                textToSpeech: true, suppliedVoice: true, voiceCloning: true,
                guidePerformanceTransfer: true, naturalLanguageDirection: true, multilingual: true, local: true)),
            ("chatterbox", "Chatterbox Multilingual V3", .local, RendererCapabilities(
                textToSpeech: true, voiceCloning: true, naturalLanguageDirection: true, multilingual: true, local: true)),
            ("moss", "MOSS-TTS", .local, RendererCapabilities(
                textToSpeech: true, suppliedVoice: true, naturalLanguageDirection: true, multilingual: true, local: true)),
            ("microsoft", "Microsoft / Azure Speech", .cloud, RendererCapabilities(
                textToSpeech: true, suppliedVoice: true, structuredDirection: true,
                pronunciationControl: true, pauseControl: true, speedControl: true,
                pitchControl: true, durationControl: true, streaming: true, multilingual: true, cloud: true))
        ]
        let placeholders = entries.map { id, name, location, capabilities in
            UnavailableRendererAdapter(descriptor: RendererDescriptor(
                id: id, displayName: name, location: location, availability: .unavailable,
                rendererVersion: "not-integrated", capabilities: capabilities))
        }
        let overrideIDs = Set(overrides.map { $0.descriptor.id })
        let retained = placeholders.filter { !overrideIDs.contains($0.descriptor.id) }
        return RendererRegistry(adapters: retained + overrides + [MockRendererAdapter()])
    }
}
