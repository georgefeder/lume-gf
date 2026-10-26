#!/bin/sh
# Compiles the Apple TV upscaler (app/Look/GFEnhancer.swift) against the real Apple TV SDK, with the app's Swift
# settings, through SIL (so missing returns and uninitialised values are caught too, not only types). The simulators'
# SDKs lack Apple's low-latency super resolution, so every other CI build compiles only the upscaler's stand-in, and a
# mistake in the real one would otherwise first show in a TestFlight archive.
# Usage (on a Mac with Xcode): sh ci/device-typecheck.sh
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); OURS="$HERE/.."
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# Lume's Logger.player (Lume/Utils/Logger.swift): a LumeLogger, whose messages take only these privacy options
cat > "$T/Logger.swift" <<'EOF'
import OSLog
nonisolated extension Logger {
    static let player = LumeLogger()
}
nonisolated struct LumeLogger {
    func debug(_ message: @autoclosure () -> LumeLogMessage) {}
    func info(_ message: @autoclosure () -> LumeLogMessage) {}
    func notice(_ message: @autoclosure () -> LumeLogMessage) {}
    func warning(_ message: @autoclosure () -> LumeLogMessage) {}
    func error(_ message: @autoclosure () -> LumeLogMessage) {}
}
nonisolated struct LumeLogPrivacy {
    enum Mask { case hash }
    static let `public` = LumeLogPrivacy(), `private` = LumeLogPrivacy()
    static func `private`(mask: Mask) -> LumeLogPrivacy { LumeLogPrivacy() }
}
nonisolated struct LumeLogMessage: ExpressibleByStringInterpolation, ExpressibleByStringLiteral {
    init(stringLiteral value: String) {}
    init(stringInterpolation: Interpolation) {}
    struct Interpolation: StringInterpolationProtocol {
        init(literalCapacity: Int, interpolationCount: Int) {}
        mutating func appendLiteral(_ literal: String) {}
        mutating func appendInterpolation(_ value: some Any, privacy: LumeLogPrivacy = .public) {}
    }
}
EOF
# the app target's settings: module Lume, Swift 5 mode, MainActor by default, approachable concurrency, member import
# visibility, tvOS 18 and up
xcrun -sdk appletvos swiftc -wmo -emit-sil -o /dev/null -module-name Lume -parse-as-library \
  -target arm64-apple-tvos18.0 -swift-version 5 \
  -default-isolation MainActor \
  -enable-upcoming-feature MemberImportVisibility \
  -enable-upcoming-feature DisableOutwardActorInference \
  -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
  -enable-upcoming-feature InferIsolatedConformances \
  -enable-upcoming-feature InferSendableFromCaptures \
  -enable-upcoming-feature NonisolatedNonsendingByDefault \
  "$OURS/app/Look/GFEnhancer.swift" "$OURS/guide/Sources/LookCore/GFEnhancePlan.swift" "$T/Logger.swift"
echo "device-typecheck: the upscaler compiles for Apple TV"
