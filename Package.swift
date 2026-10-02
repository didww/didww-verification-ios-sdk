// swift-tools-version:6.1
// swift-tools-version = the minimum toolchain that can BUILD this package (≈ Xcode 16.3). It is
// the BUILD floor only, and is independent of the iOS 15 runtime DEPLOYMENT floor declared below:
// building the package needs a recent Xcode, the library it produces runs on iOS 15.
//
// Language mode: the toolchain default (Swift 6 strict concurrency). The URLSession
// cancellation shim therefore carries an explicit `@unchecked Sendable`, lock-guarded task box —
// which is the correct design in ANY language mode (the cancel race is a runtime concern, not a
// compile flag), so there is no benefit to pinning Swift 5 mode.

import PackageDescription

let package = Package(
    name: "DIDWWVerification",
    // Deployment floors. iOS 15 is the product floor, the lowest Xcode 27 can target. macOS 10.15
    // is declared so the library, the tests and SampleCLI build and run on a macOS host via
    // `swift test` / `swift run`; it is the floor of Swift's back-deployed concurrency runtime.
    platforms: [
        .iOS(.v15),
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
