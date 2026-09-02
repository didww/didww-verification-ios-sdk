import Foundation
import XCTest
@testable import DIDWWVerification

final class EnvelopeDecodingTests: XCTestCase {
    private func assertUnexpectedResponse(_ error: Error, file: StaticString = #filePath, line: UInt = #line) {
        guard case .unexpectedResponse = (error as? APIError) else {
            return XCTFail("expected .unexpectedResponse, got \(error)", file: file, line: line)
        }
    }

    func testMalformedEnvelopeThrowsUnexpectedResponse() async {
        let mock = MockTransport(httpResponse(#"{"nope":true}"#))
        let client = makeClient(transport: mock)
        do {
            _ = try await client.status(makeHandle())
            XCTFail("expected throw")
        } catch { assertUnexpectedResponse(error) }
    }

    /// An unrecognized `delivery_method` decodes to `.other(raw)` rather than failing the response:
    /// a channel the server adds must not break an already-installed copy.
    func testUnknownDeliveryMethodDecodesFailOpen() async throws {
        let body = #"{"data":{"id":"x","destination":"+1","delivery_method":"carrier_pigeon","status":"pending","expires_at":"2999-01-01T00:00:00Z"}}"#
        let mock = MockTransport(httpResponse(body))
        let client = makeClient(transport: mock)

        let result = try await client.status(makeHandle())

        XCTAssertEqual(result.deliveryMethod, .other("carrier_pigeon"))
        XCTAssertEqual(result.status, .pending)
    }

    func testDeliveryMethodWireValueMapping() {
        XCTAssertEqual(DeliveryMethod(wireValue: "sms"), .sms)
        XCTAssertEqual(DeliveryMethod(wireValue: "callout"), .callout)
        XCTAssertEqual(DeliveryMethod(wireValue: "carrier_pigeon"), .other("carrier_pigeon"))
        // Round-trips: whatever came off the wire is what goes back on a submit.
        XCTAssertEqual(DeliveryMethod.other("carrier_pigeon").wireValue, "carrier_pigeon")
        // `allCases` stays the modelled set — `.other` is decode-only and unbounded.
        XCTAssertEqual(DeliveryMethod.allCases, [.sms, .callout])
    }

    func testSupersededReasonDecodesTyped() async throws {
        // A new `start` for the same (application, number) fails the previously-active
        // verification with "superseded". That one is finished, so this reason is only ever
        // seen via by-id status.
        let mock = MockTransport(httpResponse(Fixtures.failedSuperseded()))
        let client = makeClient(transport: mock)

        let result = try await client.status(makeHandle())

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.reason, .superseded)
    }

    func testReasonWireValueMapping() {
        XCTAssertEqual(Verification.Reason(wireValue: "stale_dispatch"), .numberUnreachable)
        XCTAssertEqual(Verification.Reason(wireValue: "dispatch_failed"), .failedToDeliver)
        XCTAssertEqual(Verification.Reason(wireValue: "expired"), .expired)
        XCTAssertEqual(Verification.Reason(wireValue: "too_many_attempts"), .tooManyAttempts)
        XCTAssertEqual(Verification.Reason(wireValue: "application_deleted"), .applicationDeleted)
        XCTAssertEqual(Verification.Reason(wireValue: "denied_by_callback"), .deniedByCallback)
        XCTAssertEqual(Verification.Reason(wireValue: "denied_missing_callback_url"), .deniedMissingCallbackURL)
        XCTAssertEqual(Verification.Reason(wireValue: "denied_invalid_callback_response"), .deniedInvalidCallbackResponse)
        XCTAssertEqual(Verification.Reason(wireValue: "superseded"), .superseded)
        // The contract has no flat `denied` slug and this enum has no case for it — it fails open
        // like any other unmodeled value.
        XCTAssertEqual(Verification.Reason(wireValue: "denied"), .other("denied"))
        XCTAssertEqual(Verification.Reason(wireValue: "cosmic_rays"), .other("cosmic_rays"))
    }

    /// A denied verification maps to the correct typed `Reason` AND exposes the raw fields.
    func testDeniedByCallbackMapsTypedAndExposesRaw() async throws {
        let mock = MockTransport(httpResponse(
            Fixtures.deniedVerification(errorCode: "denied_by_callback",
                                        errorDetail: "your callback denied the request")))
        let client = makeClient(transport: mock)

        let result = try await client.status(makeHandle())

        XCTAssertEqual(result.status, .denied)
        XCTAssertEqual(result.reason, .deniedByCallback)
        XCTAssertEqual(result.errorCode, "denied_by_callback")
        XCTAssertEqual(result.errorDetail, "your callback denied the request")
    }

    func testDeniedMissingCallbackURLMapsTyped() async throws {
        let mock = MockTransport(httpResponse(
            Fixtures.deniedVerification(errorCode: "denied_missing_callback_url",
                                        errorDetail: "application has no callback_url")))
        let client = makeClient(transport: mock)

        let result = try await client.status(makeHandle())

        XCTAssertEqual(result.reason, .deniedMissingCallbackURL)
        XCTAssertEqual(result.errorCode, "denied_missing_callback_url")
    }

    func testDeniedInvalidCallbackResponseMapsTyped() async throws {
        let mock = MockTransport(httpResponse(
            Fixtures.deniedVerification(errorCode: "denied_invalid_callback_response",
                                        errorDetail: "callback response was invalid")))
        let client = makeClient(transport: mock)

        let result = try await client.status(makeHandle())

        XCTAssertEqual(result.reason, .deniedInvalidCallbackResponse)
        XCTAssertEqual(result.errorCode, "denied_invalid_callback_response")
    }

    /// A healthy (verified) verification carries no outcome slug → both raw carriers are nil.
    func testHealthyRowHasNilErrorFields() async throws {
        let mock = MockTransport(httpResponse(Fixtures.verifiedSMS()))
        let client = makeClient(transport: mock)

        let result = try await client.status(makeHandle())

        XCTAssertNil(result.reason)
        XCTAssertNil(result.errorCode)
        XCTAssertNil(result.errorDetail)
    }

    /// An unknown outcome slug maps to `.other(rawSlug)` and still exposes the raw fields.
    func testUnknownReasonMapsToOtherNotThrow() async throws {
        let body = #"{"data":{"id":"x","destination":"+1","delivery_method":"sms","status":"failed","error_code":"cosmic_rays","error_detail":"who knows","expires_at":"2999-01-01T00:00:00Z","sms":{"template":"t"}}}"#
        let mock = MockTransport(httpResponse(body))
        let client = makeClient(transport: mock)

        let result = try await client.status(makeHandle())

        XCTAssertEqual(result.reason, .other("cosmic_rays"))
        XCTAssertEqual(result.errorCode, "cosmic_rays")
        XCTAssertEqual(result.errorDetail, "who knows")
    }

    func testDetailsNilWhenTheServerSendsNoChannelBlock() async throws {
        let body = #"{"data":{"id":"x","destination":"+15551234567","delivery_method":"sms","status":"verified","expires_at":"2999-01-01T00:00:00Z"}}"#
        let mock = MockTransport(httpResponse(body))
        let client = makeClient(transport: mock)

        let result = try await client.status(makeHandle())

        XCTAssertNil(result.details)
        XCTAssertEqual(result.deliveryMethod, .sms)
    }
}
