import Foundation
import XCTest
@testable import DIDWWVerification

final class RedactionTests: XCTestCase {
    func testRedactsPhoneAndCodeButKeepsOtherData() {
        let line = "user +15551234567 submitted 123456 for token abcdef at HTTP 200"
        let redacted = Redactor.redact(line)

        XCTAssertFalse(redacted.contains("+15551234567"), "phone must be masked")
        XCTAssertFalse(redacted.contains("123456"), "code must be masked")
        XCTAssertTrue(redacted.contains("token abcdef"), "non-sensitive token preserved")
        XCTAssertTrue(redacted.contains("HTTP 200"), "runs under four digits stay readable")
    }

    func testRedactsCodeAtEveryServerChosenLength() {
        // The server picks the length per application, 4 to 8. Every one of them must be masked.
        for length in 4...8 {
            let code = String(repeating: "7", count: length)
            let redacted = Redactor.redact("submitted \(code) now")
            XCTAssertFalse(redacted.contains(code), "a \(length)-digit code must be masked")
        }
    }

    func testFourDigitYearIsMaskedAsTheAcceptedCost() {
        // Widening to 4 masks years, ports and millisecond durations too — deliberate.
        let redacted = Redactor.redact("at 2026-07-13T12:00:00")
        XCTAssertFalse(redacted.contains("2026"), "a 4-digit run is masked whatever it means")
        XCTAssertTrue(redacted.contains("-07-13T12:00:00"), "runs under four digits survive")
    }

    func testUUIDPassesThroughIntact() {
        let id = "0198f3c2-7a41-71ce-8f21-419283746501"
        let redacted = Redactor.redact("→ GET https://verify.example.com/api/v1/verifications/\(id)")
        XCTAssertTrue(redacted.contains(id), "a verification id must survive byte-identical")
    }

    func testCodeAndPhoneAreStillMaskedAlongsideAUUID() {
        let id = "0198f3c2-7a41-71ce-8f21-419283746501"
        let redacted = Redactor.redact("id \(id) code 1234 long 12345678 phone +15551234567")

        XCTAssertTrue(redacted.contains(id), "the id survives")
        XCTAssertFalse(redacted.contains("1234 "), "a 4-digit code is still masked")
        XCTAssertFalse(redacted.contains("12345678"), "an 8-digit code is still masked")
        XCTAssertFalse(redacted.contains("+15551234567"), "a phone is still masked")
        XCTAssertTrue(redacted.contains("«redacted-number»"), "a phone keeps the number label")
    }

    func testCodeAdjacentToAUUIDIsStillMasked() {
        let id = "0198f3c2-7a41-71ce-8f21-419283746501"
        let redacted = Redactor.redact("\(id)/1234")
        XCTAssertTrue(redacted.contains(id), "the id survives")
        XCTAssertTrue(redacted.contains("«redacted-code»"), "the trailing code is masked")
    }

    func testBareHexIsNotTreatedAsAUUID() {
        // Hyphens are required: the passthrough is for identifiers, not any hex blob.
        let blob = "0198f3c27a4171ce8f21419283746501"
        XCTAssertFalse(Redactor.redact("blob \(blob)").contains(blob))
    }

    func testDigitsGluedDirectlyOntoAUUIDBreakThePassthrough() {
        // No delimiter between the leading digits and the UUID: a real UUID is never glued directly
        // onto more hex/digits, so this run must not be recognized as "a UUID plus some digits" — it
        // falls through to ordinary digit masking instead, and nothing survives unmasked.
        let id = "0198f3c2-7a41-71ce-8f21-419283746501"
        let glued = "1234" + id
        let redacted = Redactor.redact("blob \(glued) end")

        XCTAssertFalse(redacted.contains(glued), "the glued run must not survive intact")
        XCTAssertFalse(redacted.contains(id), "the embedded id must not pass through unmasked either")
    }

    func testCodeInsideLongerDigitRunIsNotSplit() {
        // An 11-digit run is a phone, not a code — it must be masked as a number, and the code
        // pattern must not carve a shorter chunk out of it.
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
                      "a digit segment in the logged URL should be redacted (not a canonical UUID)")
    }

    func testByNumberURLIsRedactedInLogs() async throws {
        // The client puts the digits-only number in the by-number path; the Redactor's phone
        // pattern (8–15 digit runs) must mask it before it reaches the logger.
        //
        // Known limitation, deliberate: a run over 15 digits escapes both patterns. Under 8 the
        // code pattern still catches it down to 4, so only 1-3 digit garbage reaches the logger
        // unmasked — it 404s server-side, the accepted residual of mirroring backend semantics.
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
