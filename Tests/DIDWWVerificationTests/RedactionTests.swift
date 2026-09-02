import Foundation
import XCTest
@testable import DIDWWVerification

final class RedactionTests: XCTestCase {
    func testRedactsPhoneAndCodeButKeepsOtherData() {
        let line = "user +15551234567 submitted 123456 for token abcdef-1234 at 2026-07-13T12:00:00"
        let redacted = Redactor.redact(line)

        XCTAssertFalse(redacted.contains("+15551234567"), "phone must be masked")
        XCTAssertFalse(redacted.contains("123456"), "code must be masked")
        XCTAssertTrue(redacted.contains("token abcdef-1234"), "non-sensitive token preserved")
        XCTAssertTrue(redacted.contains("2026-07-13T12:00:00"), "timestamp preserved")
    }

    func testCodeInsideLongerDigitRunIsNotSplit() {
        // An 11-digit run is a phone, not a code — it must be masked as a number, and the code
        // pattern must not carve a 6-digit chunk out of it.
        let redacted = Redactor.redact("call 15551234567 now")
        XCTAssertFalse(redacted.contains("15551234567"))
        XCTAssertFalse(redacted.contains("«redacted-code»"), "must not treat part of a phone as a code")
    }

    func testLoggerEmitsRedactedOutputWhenSet() async throws {
        let logger = StubLogger()
        let mock = MockTransport(httpResponse(Fixtures.verifiedSMS()))
        let client = makeClient(transport: mock, configuration: .init(logger: logger))

        _ = try await client.status(makeHandle(id: "123456-aaaa"))

        XCTAssertFalse(logger.lines.isEmpty, "logger should receive lines when set")
        XCTAssertTrue(logger.lines.contains { $0.contains("«redacted-code»") },
                      "a 6-digit id segment in the logged URL should be redacted")
    }

    func testByNumberURLIsRedactedInLogs() async throws {
        // The client puts the digits-only number in the by-number path; the Redactor's phone
        // pattern (8–15 digit runs) must mask it before it reaches the logger.
        //
        // Known limitations, deliberate: runs under 8 or over 15 digits escape the pattern. In
        // particular sub-8-digit garbage input (e.g. "12345") passes the client's has-digits guard,
        // is NOT redacted, and 404s server-side — the accepted residual of mirroring backend
        // semantics rather than validating stricter than the backend.
        let logger = StubLogger()
        let mock = MockTransport(httpResponse(Fixtures.startSMS()))
        let client = makeClient(transport: mock, configuration: .init(logger: logger))

        _ = try await client.status(number: "+1 (555) 123-4567")

        let urlLine = logger.lines.first { $0.contains("by_number") }
        XCTAssertNotNil(urlLine, "the request URL line should be logged")
        XCTAssertTrue(urlLine?.contains("«redacted-number»") == true, "number must be masked")
        XCTAssertFalse(urlLine?.contains("15551234567") == true, "raw digits must not reach the logger")
    }

    func testRedactMasksNumberInByNumberURLString() {
        // Pure-string check of the same invariant, independent of the client plumbing. The
        // Redactor's pattern itself must not change for by-number — digits-only path segments are
        // exactly the shape it already masks.
        let redacted = Redactor.redact("→ GET https://verify.example.com/api/v1/verifications/by_number/15551234567")

        XCTAssertFalse(redacted.contains("15551234567"))
        XCTAssertTrue(redacted.contains("by_number/«redacted-number»"))
    }

    func testNoLoggerMeansNoLoggingPath() async throws {
        // With logger nil (default), the SDK must not attempt logging. No observable sink; this
        // exercises the guard path and asserts the call still succeeds.
        let mock = MockTransport(httpResponse(Fixtures.verifiedSMS()))
        let client = makeClient(transport: mock)
        let result = try await client.status(makeHandle())
        XCTAssertEqual(result.status, .verified)
    }
}
