import Foundation
import XCTest
@testable import DIDWWVerification

final class ExpiryTests: XCTestCase {
    func testFractionalSecondsExpiresAtParsesToSameInstantAsReference() async throws {
        let mock = MockTransport(httpResponse(Fixtures.startSMS(expiresAt: Fixtures.fractional), status: 201))
        let client = makeClient(transport: mock)

        let verification = try await client.start(destination: "+15551234567", method: .sms)

        let reference = ISO8601DateFormatter()
        reference.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expected = try XCTUnwrap(reference.date(from: Fixtures.fractional))
        XCTAssertEqual(verification.expiresAt, expected)
    }

    func testPlainSecondsExpiresAtParses() async throws {
        let mock = MockTransport(httpResponse(Fixtures.startSMS(expiresAt: "2999-01-01T00:00:00Z"), status: 201))
        let client = makeClient(transport: mock)

        let verification = try await client.start(destination: "+15551234567", method: .sms)

        XCTAssertFalse(verification.isExpired)
    }

    func testIsExpiredTrueForPast() {
        XCTAssertTrue(makeHandle(expiresAt: Date(timeIntervalSince1970: 0)).isExpired)
    }

    func testIsExpiredFalseForFuture() {
        XCTAssertFalse(makeHandle(expiresAt: Date().addingTimeInterval(600)).isExpired)
    }

    func testStartWithMissingExpiresAtThrows() async {
        let body = #"{"data":{"id":"x","destination":"+1","delivery_method":"sms","status":"pending"}}"#
        let mock = MockTransport(httpResponse(body, status: 201))
        let client = makeClient(transport: mock)
        do {
            _ = try await client.start(destination: "+1", method: .sms)
            XCTFail("expected throw for missing expires_at")
        } catch {
            guard case .unexpectedResponse = (error as? APIError) else {
                return XCTFail("expected .unexpectedResponse, got \(error)")
            }
        }
    }
}
