/// Lume GF's iCloud (Part 4, docs/superpowers/specs/2026-10-02-lume-gf-4-icloud-design.md): names shared by the app,
/// its tests and the CI layout.
nonisolated enum GFCloudConfig {
    /// false turns our iCloud off again: every device keeps its data to itself, as in build 11.
    static let enabled = true
    /// Georgs' own container (Lume's is `iCloud.bilipp.Lume`, which our signing may not use).
    static let containerID = "iCloud.lv.georgefeder.lume"
    /// The continue banner's one record in the private database (default zone).
    static let lastPlayedRecordType = "GFLastPlayed"
    static let lastPlayedRecordName = "last-played"
    /// Settings in the iCloud key-value store: `gf.settings.<group>.<key>`.
    static let settingsPrefix = "gf.settings."
}
