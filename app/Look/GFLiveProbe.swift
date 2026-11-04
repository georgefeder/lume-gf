import Foundation

/// How much of a live channel FFmpeg reads to learn its streams before it plays (KSOptions.probesize and
/// maxAnalyzeDuration, set for live channels only: patches/0031). Georgs, 4 Nov, through the Glasgow Pi Admin chat:
/// start channels faster; FFmpeg's defaults read several megabytes and seconds. Test streams of each kind live TV
/// carries (H.264 and HEVC in MPEG-TS, 720p to 4K at up to 25 Mbit/s, with AAC, AC-3 5.1 and MP2, two audio tracks,
/// joined mid-picture) kept every stream, sound included, down to 60 KB (FFmpeg 6.1, 4 Nov): 1 MB leaves room. A
/// channel without its sound would be worse than a slower start: raise these first if one ever loses it.
enum GFLiveProbe {
    /// Bytes.
    nonisolated static let size: Int64 = 1_000_000
    /// Microseconds (FFmpeg's AV_TIME_BASE): one second.
    nonisolated static let duration: Int64 = 1_000_000
}
