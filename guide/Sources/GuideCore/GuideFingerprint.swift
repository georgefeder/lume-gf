import Foundation

/// A stable 64-bit fingerprint of a guide programme's content (FNV-1a over its fields). It tells whether a
/// programme with the same channel and start changed between two guide builds. Stable across launches and devices,
/// unlike Swift's `Hasher`, so it can also be stored.
nonisolated enum GuideFingerprint {
    private static let offset: UInt64 = 0xCBF2_9CE4_8422_2325
    private static let prime: UInt64 = 0x0000_0100_0000_01B3

    static func of(end: Date, title: String, subtitle: String?, category: String?, description: String) -> UInt64 {
        var hash = offset
        for field in [String(Int64(end.timeIntervalSince1970)), title, subtitle ?? "\u{0}", category ?? "\u{0}",
                      description] {
            for byte in field.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* prime
            }
            hash ^= 0x1F // unit separator between fields: "ab"+"c" and "a"+"bc" differ
            hash = hash &* prime
        }
        return hash
    }

    /// A stable fingerprint of a set of channel ids, whatever their order: whether a source's channels changed since
    /// its last import.
    static func ofSet(_ ids: Set<String>) -> UInt64 {
        var hash = offset
        for id in ids.sorted() {
            for byte in id.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* prime
            }
            hash ^= 0x1F
            hash = hash &* prime
        }
        return hash
    }

    /// Lume stores a programme's categories joined like this (`EPGSyncManager`); both sides of a comparison use it.
    static func category(_ categories: [String]) -> String? {
        categories.isEmpty ? nil : categories.joined(separator: ", ")
    }
}
