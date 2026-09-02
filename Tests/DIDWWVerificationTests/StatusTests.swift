import Foundation
import XCTest
@testable import DIDWWVerification

final class StatusTests: XCTestCase {
    func testStatusIssuesGETAndDecodesResult() async throws {
        let mock = MockTransport(httpResponse(Fixtures.verifiedSMS()))
        let client = makeClient(transport: mock)
        let handle = makeHandle()

        let result = try await client.status(handle)

        let request = mock.recordedRequests[0]
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString,
                       "https://verify.example.com/api/v1/verifications/\(handle.id)")
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(result.status, .verified)
        XCTAssertEqual(result.fee, Decimal(string: "0.05"))
        XCTAssertEqual(result.details, .sms(.init(template: "default_otp", language: "en-US")))
    }

    func testFeeDecodesFromJSONNumberWithoutFloatDrift() async throws {
        let mock = MockTransport(httpResponse(Fixtures.verifiedSMSNumberFee(fee: "0.06")))
        let client = makeClient(transport: mock)

        let result = try await client.status(makeHandle())

        XCTAssertEqual(result.fee, Decimal(string: "0.06"))
    }

    func testUnknownStatusMapsToOtherWithoutThrowing() async throws {
        let mock = MockTransport(httpResponse(Fixtures.statusWithRawStatus("throttled")))
        let client = makeClient(transport: mock)

        let result = try await client.status(makeHandle())

        XCTAssertEqual(result.status, .other("throttled"))
        XCTAssertFalse(result.status.isTerminal)
    }

    func testFailedResultCarriesTypedReason() async throws {
        let mock = MockTransport(httpResponse(Fixtures.failedTooManyAttempts()))
        let client = makeClient(transport: mock)

        let result = try await client.status(makeHandle())

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.reason, .tooManyAttempts)
    }

    // MARK: - By number

    func testStatusByNumberIssuesGETAndDecodesResult() async throws {
        let mock = MockTransport(httpResponse(Fixtures.startSMS()))
        let client = makeClient(transport: mock)

        let result = try await client.status(number: "+1 (555) 123-4567")

        let request = mock.recordedRequests[0]
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString,
                       "https://verify.example.com/api/v1/verifications/by_number/15551234567")
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(result.status, .pending)
        XCTAssertEqual(result.details, .sms(.init(template: "default_otp", language: "en-US")))
    }

    func testStatusByNumberMapsNoVerificationTo404() async {
        // The server 404s only when no verification exists for the number at all.
        let mock = MockTransport(httpResponse(Fixtures.errorBody([(code: "not_found", detail: "not found")]), status: 404))
        let client = makeClient(transport: mock)

        do {
            _ = try await client.status(number: "15551234567")
            XCTFail("expected notFound")
        } catch {
            XCTAssertEqual(error as? APIError, .notFound)
        }
    }

    func testStatusByNumberDecodesFinishedVerification() async throws {
        // Finished verifications stay addressable by number (polling the outcome after verify/fail).
        let mock = MockTransport(httpResponse(Fixtures.verifiedSMS()))
        let client = makeClient(transport: mock)

        let result = try await client.status(number: "15551234567")

        XCTAssertEqual(result.status, .verified)
    }

    func testStatusByNumberWithNoDigitsThrowsInvalidNumberAndSendsNothing() async {
        let mock = MockTransport(httpResponse(Fixtures.startSMS()))
        let client = makeClient(transport: mock)

        do {
            _ = try await client.status(number: "not a number")
            XCTFail("expected invalidNumber")
        } catch {
            XCTAssertEqual(error as? VerificationError, .invalidNumber)
        }
        XCTAssertTrue(mock.recordedRequests.isEmpty, "invalidNumber must be caught before any network call")
    }

    // MARK: - Channel blocks

    func testCalloutResultCarriesTheAnnouncementLanguage() async throws {
        let mock = MockTransport(httpResponse(Fixtures.verifiedCallout(language: "pt-BR")))
        let client = makeClient(transport: mock)

        let result = try await client.status(makeHandle(method: .callout))

        XCTAssertEqual(result.deliveryMethod, .callout)
        XCTAssertEqual(result.details, .callout(.init(language: "pt-BR")))
    }

    // A tag with no recording falls back to en-US server-side and still answers 201, so comparing
    // what came back against what was asked is the only way to know. `ka-GE` is a real instance.
    func testStartHandleReportsTheServerFallbackRatherThanWhatWasAsked() async throws {
        let mock = MockTransport(httpResponse(Fixtures.startCallout(language: "en-US"), status: 201))
        let client = makeClient(transport: mock)

        let verification = try await client.start(destination: "+15551234567", method: .callout,
                                                  callout: .init(languages: ["ka-GE"]))

        guard case .callout(let callout) = verification.details else {
            return XCTFail("expected a callout block on the start handle")
        }
        XCTAssertEqual(callout.language, "en-US", "the requested tag has no recording, so it fell back")
    }

    func testStartHandleCarriesTheSMSBlock() async throws {
        let mock = MockTransport(httpResponse(Fixtures.startSMS(), status: 201))
        let client = makeClient(transport: mock)

        let verification = try await client.start(destination: "+15551234567", method: .sms,
                                                  sms: .init(languages: ["en-US"]))

        XCTAssertEqual(verification.details, .sms(.init(template: "default_otp", language: "en-US")))
    }

    func testSMSResultCarriesTheTemplateLanguage() async throws {
        let mock = MockTransport(httpResponse(Fixtures.verifiedSMS()))
        let client = makeClient(transport: mock)

        let result = try await client.status(makeHandle())

        guard case .sms(let sms) = result.details else { return XCTFail("expected an sms block") }
        XCTAssertEqual(sms.language, "en-US")
        XCTAssertEqual(sms.template, "default_otp")
    }
}
