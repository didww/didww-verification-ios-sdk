import Foundation
import XCTest
@testable import DIDWWVerification

/// Guards against the podspec and `SDKVersion.current` drifting apart — nothing else compares
/// them, since a Swift target cannot read a `.podspec` at build time.
final class SDKVersionTests: XCTestCase {
    func testCurrentMatchesPodspecVersion() throws {
        // #filePath is Tests/DIDWWVerificationTests/SDKVersionTests.swift; the podspec lives at
        // the package root, two directories up.
        let podspecURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("DIDWWVerification.podspec")
        let contents = try String(contentsOf: podspecURL, encoding: .utf8)

        let regex = try NSRegularExpression(pattern: #"s\.version\s*=\s*'([^']+)'"#)
        let range = NSRange(contents.startIndex..., in: contents)
        guard let match = regex.firstMatch(in: contents, range: range),
              let versionRange = Range(match.range(at: 1), in: contents) else {
            XCTFail("could not find s.version in \(podspecURL.path)")
            return
        }

        XCTAssertEqual(SDKVersion.current, String(contents[versionRange]),
                       "SDKVersion.current and DIDWWVerification.podspec's s.version must match")
    }
}
