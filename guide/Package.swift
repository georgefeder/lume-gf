// swift-tools-version: 6.2
// Lume GF's pure logic, without Lume's types: the guide (GuideCore, Part 2) and the look (LookCore, Part 3). Tested
// here with `swift test` on GitHub's Mac; the same source files are copied into Lume at build time
// (ci/add-sources.sh) and compile as part of the app.
import PackageDescription

let package = Package(
    name: "GuideCore",
    platforms: [.macOS(.v15), .iOS(.v18), .tvOS(.v18)],
    targets: [
        .target(name: "GuideCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "GuideCoreTests", dependencies: ["GuideCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "LookCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "LookCoreTests", dependencies: ["LookCore"], swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
