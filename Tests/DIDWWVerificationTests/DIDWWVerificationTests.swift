import XCTest
@testable import DIDWWVerification

// Smoke test — proves the test target links against the library and that `swift test` runs.
// The behavioural suites live alongside it: Start, Submit, Status, ErrorMapping,
// EnvelopeDecoding, Expiry, URLConstruction, Cancellation, Redaction, ForwardCompatibility.
final class DIDWWVerificationTests: XCTestCase {
    func testTargetLinksLibrary() {
        XCTAssertTrue(true)
    }
}
