#!/bin/sh
# Type-checks the Apple TV upscaler (app/Look/GFEnhancer.swift) against the real Apple TV SDK, with the app's Swift
# settings. The simulators' SDKs lack Apple's low-latency super resolution, so every other CI build compiles only the
# upscaler's stand-in, and a mistake in the real one would otherwise first show in a TestFlight archive.
# Usage (on a Mac with Xcode): sh ci/device-typecheck.sh
set -eu
CI=$(cd "$(dirname "$0")" && pwd); OURS="$CI/.."
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# Lume's Logger.player (Lume/Utils/Logger.swift), as far as the upscaler uses it
cat > "$T/Logger.swift" <<'EOF'
import OSLog
nonisolated extension Logger {
    static let player = Logger(subsystem: "lv.georgefeder.lume", category: "Player")
}
EOF
# the app target's settings: Swift 5 mode, MainActor by default, approachable concurrency, member import visibility
xcrun -sdk appletvos swiftc -typecheck -parse-as-library -target arm64-apple-tvos18.0 -swift-version 5 \
  -default-isolation MainActor \
  -enable-upcoming-feature MemberImportVisibility \
  -enable-upcoming-feature DisableOutwardActorInference \
  -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
  -enable-upcoming-feature InferIsolatedConformances \
  -enable-upcoming-feature InferSendableFromCaptures \
  -enable-upcoming-feature NonisolatedNonsendingByDefault \
  "$OURS/app/Look/GFEnhancer.swift" "$OURS/guide/Sources/LookCore/GFEnhancePlan.swift" "$T/Logger.swift"
echo "device-typecheck: the upscaler compiles for Apple TV"
