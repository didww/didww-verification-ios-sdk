// swift-tools-version:6.1
// swift-tools-version = the minimum toolchain that can BUILD this package (≈ Xcode 16.3). It is
// the BUILD floor only, and is independent of the iOS 13 runtime DEPLOYMENT floor declared below:
// building the package needs a recent Xcode, the library it produces runs on iOS 13.
//
// Language mode: the toolchain default (Swift 6 strict concurrency). The iOS-13 URLSession
// cancellation shim therefore carries an explicit `@unchecked Sendable`, lock-guarded task box —
// which is the correct design in ANY language mode (the cancel race is a runtime concern, not a
// compile flag), so there is no benefit to pinning Swift 5 mode.

import PackageDescription

let package = Package(
    name: "DIDWWVerification",
    // Deployment floors. iOS 13 is the product floor. macOS 10.15 is declared so the library,
    // the tests and SampleCLI build and run on a macOS host via `swift test` / `swift run`.
    // 10.15 (Catalina) is also the floor where Swift's back-deployed
    // concurrency runtime (async/await) is available — the contemporaneous macOS to iOS 13.
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
    ],
    products: [
        // The one thing consumers import: `import DIDWWVerification`.
        .library(name: "DIDWWVerification", targets: ["DIDWWVerification"]),
    ],
    targets: [
        // The SDK itself. Zero dependencies — Foundation (URLSession + Codable) only.
        .target(name: "DIDWWVerification"),

        // A macOS command-line demo of the full flow. Run it with `swift run SampleCLI`.
        .executableTarget(
            name: "SampleCLI",
            dependencies: ["DIDWWVerification"]
        ),

        // Unit tests. `@testable import` lets them reach internal types (e.g. the transport seam).
        .testTarget(
            name: "DIDWWVerificationTests",
            dependencies: ["DIDWWVerification"]
        ),
    ]
)
