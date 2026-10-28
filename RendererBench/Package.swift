// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RendererBench",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "RendererBenchCore", targets: ["RendererBenchCore"]),
        .library(name: "Qwen3RendererAdapter", targets: ["Qwen3RendererAdapter"]),
        .library(name: "VoxCPM2RendererAdapter", targets: ["VoxCPM2RendererAdapter"]),
        .library(name: "ChatterboxRendererAdapter", targets: ["ChatterboxRendererAdapter"]),
        .library(name: "RB006Qualification", targets: ["RB006Qualification"]),
        .library(name: "RB007TimingRepair", targets: ["RB007TimingRepair"]),
        .library(name: "BroadcastWave", targets: ["BroadcastWave"]),
        .executable(name: "renderer-bench", targets: ["RendererBenchCLI"]),
        .executable(name: "qwen-session-bench", targets: ["QwenSessionBench"]),
        .executable(name: "voxcpm2-session-bench", targets: ["VoxCPM2SessionBench"]),
        .executable(name: "chatterbox-session-bench", targets: ["ChatterboxSessionBench"]),
        .executable(name: "rb006-qualification-bench", targets: ["RB006QualificationBench"]),
        .executable(name: "rb007-time-repair", targets: ["RB007TimeRepair"])
    ],
    targets: [
        .target(name: "RendererBenchCore"),
        .target(name: "Qwen3RendererAdapter", dependencies: ["RendererBenchCore"]),
        .target(name: "VoxCPM2RendererAdapter", dependencies: ["RendererBenchCore"]),
        .target(name: "ChatterboxRendererAdapter", dependencies: ["RendererBenchCore"]),
        .target(name: "RB006Qualification", dependencies: ["RendererBenchCore"]),
        .target(name: "RB007TimingRepair"),
        // JUJU VO Studio Stage 1: renderer-neutral Broadcast WAV (bext + iXML) writer/reader. No dependencies.
        .target(name: "BroadcastWave"),
        .executableTarget(name: "RendererBenchCLI", dependencies: ["RendererBenchCore", "Qwen3RendererAdapter", "VoxCPM2RendererAdapter", "ChatterboxRendererAdapter"]),
        .executableTarget(name: "QwenSessionBench", dependencies: ["RendererBenchCore", "Qwen3RendererAdapter"]),
        .executableTarget(name: "VoxCPM2SessionBench", dependencies: ["RendererBenchCore", "VoxCPM2RendererAdapter"]),
        .executableTarget(name: "ChatterboxSessionBench", dependencies: ["RendererBenchCore", "ChatterboxRendererAdapter"]),
        .executableTarget(name: "RB006QualificationBench", dependencies: ["RendererBenchCore", "RB006Qualification", "Qwen3RendererAdapter", "VoxCPM2RendererAdapter", "ChatterboxRendererAdapter"]),
        .executableTarget(name: "RB007TimeRepair", dependencies: ["RB007TimingRepair"]),
        .testTarget(name: "RendererBenchCoreTests", dependencies: ["RendererBenchCore", "Qwen3RendererAdapter", "VoxCPM2RendererAdapter", "ChatterboxRendererAdapter", "RB006Qualification", "RB007TimingRepair"]),
        .testTarget(name: "BroadcastWaveTests", dependencies: ["BroadcastWave", "RendererBenchCore"])
    ]
)
