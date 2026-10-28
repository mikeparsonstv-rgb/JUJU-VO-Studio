import Foundation
import BroadcastWave

/// Peak envelope for drawing a take's waveform (first channel; PCM 8/16/24/32 or float 32).
public enum WaveformPeaks {
    public static func compute(fileAt url: URL, buckets: Int = 600) -> [Float] {
        guard buckets > 0, let (data, file) = try? WAVReader.load(contentsOf: url) else { return [] }
        let f = file.format
        let bytesPer = Int(f.bitsPerSample) / 8, stride = Int(f.blockAlign)
        let frames = file.audioByteCount / stride
        guard frames > 0 else { return [] }
        let base = file.audioRange.lowerBound
        var peaks = [Float](repeating: 0, count: buckets)
        data.withUnsafeBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            func sample(_ frame: Int) -> Float {
                let o = base + frame * stride
                switch (f.isFloat, bytesPer) {
                case (true, 4): return Float(bitPattern: UInt32(p[o]) | UInt32(p[o+1]) << 8 | UInt32(p[o+2]) << 16 | UInt32(p[o+3]) << 24)
                case (false, 1): return (Float(p[o]) - 128) / 128
                case (false, 2): return Float(Int16(bitPattern: UInt16(p[o]) | UInt16(p[o+1]) << 8)) / 32_768
                case (false, 3): return Float(Int32(bitPattern: (UInt32(p[o]) << 8 | UInt32(p[o+1]) << 16 | UInt32(p[o+2]) << 24)) >> 8) / 8_388_608
                case (false, 4): return Float(Int32(bitPattern: UInt32(p[o]) | UInt32(p[o+1]) << 8 | UInt32(p[o+2]) << 16 | UInt32(p[o+3]) << 24)) / 2_147_483_648
                default: return 0
                }
            }
            let step = max(1, frames / (buckets * 64))   // sample at most ~64 points per bucket
            var i = 0
            while i < frames {
                let b = min(buckets - 1, i * buckets / frames)
                peaks[b] = max(peaks[b], abs(sample(i)))
                i += step
            }
        }
        return peaks.map { min(1, $0) }
    }
}
