import Foundation
import XCTest
@testable import DIDWWVerification

final class StartTests: XCTestCase {
    func testStartSMSBuildsPOSTWithEnvelopeAndAuth() async throws {
        let mock = MockTransport(httpResponse(Fixtures.startSMS(), status: 201))
        let client = makeClient(transport: mock)

        let verification = try await client.start(destination: "+15551234567", method: .sms,
                                                  sms: .init(languages: ["en-US"]))

        let request = try XCTUnwrap(mock.recordedRequests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://verify.example.com/api/v1/verifications")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Basic "), true)

        let body = requestBodyData(request)
        XCTAssertEqual(body["destination"] as? String, "+15551234567")
        XCTAssertEqual(body["delivery_method"] as? String, "sms")
        XCTAssertEqual(body["sms"] as? [String: [String]], ["languages": ["en-US"]])
        // A top-level `languages` is dropped by the server without an error, so sending one would
        // silently fall back to the default template.
        XCTAssertNil(body["languages"], "languages belongs inside the channel block, never top-level")

        XCTAssertEqual(verification.id, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(verification.deliveryMethod, .sms)
        XCTAssertFalse(verification.isExpired)
    }

    // `callout` takes the same language list as `sms`, in its own block.
    func testStartCalloutSendsLanguagesInItsOwnBlock() async throws {
        let mock = MockTransport(httpResponse(Fixtures.startCallout(), status: 201))
        let client = makeClient(transport: mock)

        let verification = try await client.start(destination: "+15551234567", method: .callout,
                                                  callout: .init(languages: ["pt-BR", "pt-PT"]))

        let body = requestBodyData(mock.recordedRequests[0])
        XCTAssertEqual(body["delivery_method"] as? String, "callout")
        XCTAssertEqual(body["callout"] as? [String: [String]], ["languages": ["pt-BR", "pt-PT"]])
        XCTAssertNil(body["sms"], "only the block for the channel being started goes on the wire")
        XCTAssertNil(body["languages"], "languages belongs inside the channel block, never top-level")

        XCTAssertEqual(verification.deliveryMethod, .callout)
    }

    // The server drops a non-matching block and still answers 201, so only this guard surfaces it.
    func testStartRejectsOptionsForAnotherChannelAndSendsNothing() async {
        let cases: [(method: DeliveryMethod, sms: SMSOptions?, callout: CalloutOptions?)] = [
            (.callout, .init(languages: ["de-DE"]), nil),
            (.sms, nil, .init(languages: ["pt-BR"])),
            // An unmodelled channel matches no block either, so both are still a mistake.
            (.other("whatsapp"), .init(languages: ["de-DE"]), nil),
            (.other("whatsapp"), nil, .init(languages: ["pt-BR"])),
            // Both blocks at once can never be right: at most one can match `method`.
            (.sms, .init(languages: ["de-DE"]), .init(languages: ["pt-BR"]))
        ]
        for (method, sms, callout) in cases {
            let mock = MockTransport(httpResponse(Fixtures.startSMS(), status: 201))
            let client = makeClient(transport: mock)

            do {
                _ = try await client.start(destination: "+15551234567", method: method,
                                           sms: sms, callout: callout)
                XCTFail("expected channelMismatch for \(method)")
            } catch {
                XCTAssertEqual(error as? VerificationError, .channelMismatch(expected: method))
            }
            XCTAssertTrue(mock.recordedRequests.isEmpty, "mismatch must be caught before any network call")
        }
    }

    // Guarded on presence, not content: an empty block for the wrong channel is still a mistake.
    func testStartRejectsAnEmptyOptionsBlockForAnotherChannel() async {
        let mock = MockTransport(httpResponse(Fixtures.startSMS(), status: 201))
        let client = makeClient(transport: mock)

        do {
            _ = try await client.start(destination: "+15551234567", method: .sms, callout: .init())
            XCTFail("expected channelMismatch")
        } catch {
            XCTAssertEqual(error as? VerificationError, .channelMismatch(expected: .sms))
        }
        XCTAssertTrue(mock.recordedRequests.isEmpty)
    }

    func testStartOmitsTheChannelBlockWhenThereAreNoOptions() async throws {
        for options in [nil, SMSOptions()] as [SMSOptions?] {
            let mock = MockTransport(httpResponse(Fixtures.startSMS(), status: 201))
            let client = makeClient(transport: mock)

            _ = try await client.start(destination: "+15551234567", method: .sms, sms: options)

            let body = requestBodyData(mock.recordedRequests[0])
            XCTAssertNil(body["sms"], "the channel block must be omitted, not sent empty or null, when there is nothing to put in it")
            XCTAssertNil(body["languages"])
        }
    }

    func testStartOmitsTheCalloutBlockWhenThereAreNoOptions() async throws {
        for options in [nil, CalloutOptions()] as [CalloutOptions?] {
            let mock = MockTransport(httpResponse(Fixtures.startCallout(), status: 201))
            let client = makeClient(transport: mock)

            _ = try await client.start(destination: "+15551234567", method: .callout, callout: options)

            let body = requestBodyData(mock.recordedRequests[0])
            XCTAssertNil(body["callout"], "the channel block must be omitted, not sent empty or null, when there is nothing to put in it")
            XCTAssertNil(body["languages"])
        }
    }

    func testStartCarriesTheHealthyOutcomeSnapshot() async throws {
        let mock = MockTransport(httpResponse(Fixtures.startSMS(), status: 201))
        let client = makeClient(transport: mock)

        let verification = try await client.start(destination: "+15551234567", method: .sms)

        XCTAssertEqual(verification.status, .pending)
        XCTAssertFalse(verification.status.isTerminal)
        XCTAssertNil(verification.errorCode)
        XCTAssertNil(verification.errorDetail)
        XCTAssertNil(verification.reason)
    }

    // A request-callback denial is a 201, not an HTTP error: the outcome must survive on the handle,
    // otherwise a denied start is indistinguishable from a pending one.
    func testStartSurfacesACallbackDenialOnTheHandle() async throws {
        let body = Fixtures.deniedVerification(
            errorCode: "denied_by_callback",
            errorDetail: "your callback denied the request"
        )
        let mock = MockTransport(httpResponse(body, status: 201))
        let client = makeClient(transport: mock)

        let verification = try await client.start(destination: "+15551234567", method: .sms)

        XCTAssertEqual(verification.status, .denied)
        XCTAssertTrue(verification.status.isTerminal)
        XCTAssertEqual(verification.errorCode, "denied_by_callback")
        XCTAssertEqual(verification.errorDetail, "your callback denied the request")
        XCTAssertEqual(verification.reason, .deniedByCallback)
    }

    func testStartSurfacesAMissingCallbackURLDenial() async throws {
        let body = Fixtures.deniedVerification(
            errorCode: "denied_missing_callback_url",
            errorDetail: "application has no callback_url"
        )
        let mock = MockTransport(httpResponse(body, status: 201))
        let client = makeClient(transport: mock)

        let verification = try await client.start(destination: "+15551234567", method: .sms)

        XCTAssertEqual(verification.status, .denied)
        XCTAssertEqual(verification.reason, .deniedMissingCallbackURL)
    }

    func testStartFailsOpenOnAnUnknownOutcomeSlug() async throws {
        let body = Fixtures.deniedVerification(errorCode: "denied_by_moon_phase", errorDetail: "the moon said no")
        let mock = MockTransport(httpResponse(body, status: 201))
        let client = makeClient(transport: mock)

        let verification = try await client.start(destination: "+15551234567", method: .sms)

        // Raw slug survives; the typed convenience degrades to .other rather than failing the decode.
        XCTAssertEqual(verification.errorCode, "denied_by_moon_phase")
        XCTAssertEqual(verification.reason, .other("denied_by_moon_phase"))
    }

    func testStartCarriesTheQuotedFee() async throws {
        let body = """
        {"data":{"id":"11111111-1111-1111-1111-111111111111","destination":"+15551234567",\
        "delivery_method":"sms","fee":"0.06","status":"pending","expires_at":"\(Fixtures.farFuture)",\
        "sms":{"template":"default_otp","language":"en-US"}}}
        """
        let mock = MockTransport(httpResponse(body, status: 201))
        let client = makeClient(transport: mock)

        let verification = try await client.start(destination: "+15551234567", method: .sms)

        XCTAssertEqual(verification.fee, Decimal(string: "0.06"))
    }
}
