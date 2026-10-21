// swift-tools-version:5.10
// MRTKit: code shared by the iOS app, its widget, and the tvOS app.
//   MRTCore   - Foundation-only logic (formerly MovieRouletteTuesday/RouletteCore). Also builds on Linux.
// Swift settings mirror the app targets: Swift 5 language mode plus the upcoming
// features that SWIFT_APPROACHABLE_CONCURRENCY = YES turns on; default actor
// isolation stays nonisolated (the SwiftPM default), as in the app.
import PackageDescription

let approachableConcurrency: [SwiftSetting] = [
    .enableUpcomingFeature("DisableOutwardActorInference"),
    .enableUpcomingFeature("GlobalActorIsolatedTypesUsability"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("InferSendableFromCaptures"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
    name: "MRTKit",
    platforms: [.iOS(.v17), .tvOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MRTCore", targets: ["MRTCore"]),
    ],
    targets: [
        .target(name: "MRTCore", swiftSettings: approachableConcurrency),
    ],
    swiftLanguageVersions: [.v5]
)
