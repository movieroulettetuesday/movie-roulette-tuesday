#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
IOS="${1:?}"; OUT="${2:?}"
G="${TMPDIR:-/tmp}/mrt-vector-gen-$$"
rm -rf "$G"; mkdir -p "$G/Sources/MRTCore" "$G/Sources/VectorGen" "$OUT"
cp "$IOS"/MovieRouletteTuesday/RouletteCore/*.swift "$G/Sources/MRTCore/"
cp "$HERE/main.swift" "$G/Sources/VectorGen/main.swift"
cat > "$G/Package.swift" <<'PKG'
// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "VectorGen", platforms: [.macOS(.v14)],
  targets: [.target(name: "MRTCore"), .executableTarget(name: "VectorGen", dependencies: ["MRTCore"])])
PKG
COMMIT="$(git -C "$IOS" rev-parse --short HEAD)"
(cd "$G" && xcrun swift build -c release 2>&1 | tee "$OUT/../build.log" | tail -15)
"$G/.build/release/VectorGen" "$OUT" "$IOS" "$COMMIT"
rm -rf "$G"
