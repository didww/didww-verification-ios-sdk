import Foundation
import XCTest
@testable import DIDWWVerification

/// What happens when the **server changes and this SDK version doesn't**.
///
/// The slug vocabulary, the payload fields, and the HTTP statuses all grow server-side; a shipped
/// app cannot be updated in step. Every case below is a change the server can make unilaterally,
/// and the contract is the same each time: **the call still succeeds, the raw value survives, and
/// only the typed convenience degrades.** `delivery_method` used to be a deliberate fail-closed
/// exception; it isn't any more — see CONVENTIONS.md.
///
/// The sibling suites pin the individual mechanisms (`ErrorMappingTests` for slug exposure,
/// `EnvelopeDecodingTests` for reason mapping, `StatusTests` for unknown statuses); this file exists
/// to answer one question directly — *does a new server value break the SDK?*
final class ForwardCompatibilityTests: XCTestCase {

    // MARK: - New error slugs in the envelope

    /// A slug added server-side after this SDK shipped: typed `known` degrades to nil, the raw code
    /// and detail are intact, and the HTTP status still picks the right `APIError` case.
    func testBrandNewErrorSlugKeepsRawCodeAndDetail() async {
        let body = Fixtures.errorBody([(code: "destination_embargoed", detail: "destination is embargoed")])
        guard case .validationFailed(let items) = await error(status: 422, body: body) else {
            return XCTFail("expected validationFailed")
        }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].code, "destination_embargoed")
        XCTAssertEqual(items[0].detail, "destination is embargoed")
        XCTAssertNil(items[0].known, "an unmodeled slug must not resolve to some other case")
    }

    /// A mix of known and new slugs in one body: neither is lost, and the known one still types.
    func testNewSlugAlongsideAKnownOneKeepsBoth() async {
        let body = Fixtures.errorBody([
            (code: "destination_blank", detail: "destination can't be blank"),
            (code: "destination_embargoed", detail: "destination is embargoed"),
        ])
        guard case .validationFailed(let items) = await error(status: 422, body: body) else {
            return XCTFail("expected validationFailed")
        }
        XCTAssertEqual(items.map(\.code), ["destination_blank", "destination_embargoed"])
        XCTAssertEqual(items[0].known, .destinationBlank)
        XCTAssertNil(items[1].known)
    }

    /// The server adds a field to an error element (a JSON:API-style `source`, a `meta`, …).
    /// Unknown keys are ignored, not fatal.
    func testUnknownKeysInsideAnErrorElementAreIgnored() async {
        let body = Fixtures.rawErrorBody(
            """
            {"code":"code_invalid","detail":"code is invalid","source":{"pointer":"/data/code"},"meta":{"attempt":2}}
            """
        )
        guard case .validationFailed(let items) = await error(status: 422, body: body) else {
            return XCTFail("expected validationFailed")
        }
        XCTAssertEqual(items, [APIErrorItem(code: "code_invalid", detail: "code is invalid")])
        XCTAssertEqual(items[0].known, .codeInvalid)
    }

    /// The server adds a sibling key next to `errors` (a request id, pagination, …).
    func testUnknownTopLevelKeysBesideErrorsAreIgnored() async {
        let body = """
        {"request_id":"01890f3a","errors":[{"code":"not_ready_to_report","detail":"verification is not ready to be reported"}]}
        """
        guard case .validationFailed(let items) = await error(status: 422, body: body) else {
            return XCTFail("expected validationFailed")
        }
        XCTAssertEqual(items[0].known, .notReadyToReport)
    }

    /// An older envelope form — a flat array of strings instead of objects — must degrade to "no
    /// items", never to a crash or to the wrong `APIError` case. The caller can still branch on the
    /// status-derived case.
    func testLegacyStringEnvelopeDegradesToNoItems() async {
        let body = #"{"errors":["Destination can't be blank"]}"#
        let thrown = await error(status: 422, body: body)
        XCTAssertEqual(thrown, .validationFailed([]))
    }

    /// A future HTTP status this SDK doesn't model (429, 409, …) still carries its slugs through.
    func testUnmodeledHTTPStatusStillCarriesItsItems() async {
        let body = Fixtures.errorBody([(code: "rate_limited", detail: "too many requests")])
        let thrown = await error(status: 429, body: body)
        XCTAssertEqual(
            thrown,
            .unexpectedStatus(code: 429, items: [APIErrorItem(code: "rate_limited", detail: "too many requests")])
        )
    }

    // MARK: - New outcome slugs on a 2xx verification

    /// A denial cause added server-side: the typed `reason` degrades to `.other`, but `errorCode`
    /// and `errorDetail` carry the truth — on `status(_:)` and on the `start` handle alike.
    func testNewOutcomeSlugDegradesToOtherOnBothPaths() async throws {
        let body = Fixtures.deniedVerification(errorCode: "denied_by_risk_engine", errorDetail: "risk engine declined")

        let result = try await makeClient(transport: MockTransport(httpResponse(body))).status(makeHandle())
        XCTAssertEqual(result.status, .denied)
        XCTAssertEqual(result.reason, .other("denied_by_risk_engine"))
        XCTAssertEqual(result.errorCode, "denied_by_risk_engine")
        XCTAssertEqual(result.errorDetail, "risk engine declined")

        let started = try await makeClient(transport: MockTransport(httpResponse(body, status: 201)))
            .start(destination: "+15551234567", method: .sms)
        XCTAssertEqual(started.status, .denied)
        XCTAssertEqual(started.reason, .other("denied_by_risk_engine"))
        XCTAssertEqual(started.errorCode, "denied_by_risk_engine")
    }

    /// A partial rollout that ships `error_code` before `error_detail` must not throw.
    func testOutcomeSlugWithoutDetailStillDecodes() async throws {
        let body = """
        {"data":{"id":"11111111-1111-1111-1111-111111111111","destination":"+15551234567",\
        "delivery_method":"sms","status":"failed","error_code":"carrier_rejected",\
        "expires_at":"\(Fixtures.farFuture)"}}
        """
        let result = try await makeClient(transport: MockTransport(httpResponse(body))).status(makeHandle())
        XCTAssertEqual(result.errorCode, "carrier_rejected")
        XCTAssertNil(result.errorDetail)
        XCTAssertEqual(result.reason, .other("carrier_rejected"))
    }

    // MARK: - New fields and statuses on the verification object

    /// New top-level fields on the verification object are ignored, and the known ones still decode.
    func testUnknownFieldsOnTheVerificationObjectAreIgnored() async throws {
        let body = """
        {"data":{"id":"11111111-1111-1111-1111-111111111111","destination":"+15551234567",\
        "delivery_method":"sms","fee":"0.06","status":"pending","error_code":null,"error_detail":null,\
        "attempts_remaining":2,"created_at":"2026-07-28T10:00:00Z",\
        "expires_at":"\(Fixtures.farFuture)","sms":{"template":"default_otp","language":"en-US","sender":"DIDWW"}}}
        """
        let result = try await makeClient(transport: MockTransport(httpResponse(body))).status(makeHandle())
        XCTAssertEqual(result.status, .pending)
        XCTAssertEqual(result.fee, Decimal(string: "0.06"))
        guard case .sms(let sms) = result.details else { return XCTFail("expected an sms block") }
        XCTAssertEqual(sms.template, "default_otp")
    }

    /// A key added inside a block the SDK does decode is ignored, and the modelled keys still come
    /// through — what makes a new channel field additive rather than breaking.
    func testUnknownKeysInsideAChannelBlockAreIgnored() async throws {
        let body = """
        {"data":{"id":"33333333-3333-3333-3333-333333333333","destination":"+15551234567",\
        "delivery_method":"callout","status":"pending","expires_at":"\(Fixtures.farFuture)",\
        "callout":{"language":"pt-BR","voice":"female","speed":0.9}}}
        """
        let result = try await makeClient(transport: MockTransport(httpResponse(body)))
            .status(makeHandle(method: .callout))
        XCTAssertEqual(result.details, .callout(.init(language: "pt-BR")))
    }

    /// The `sms` block as the server serializes it today. This SDK models neither
    /// `interception_timeout` nor `app_hash` (both Android SMS Retriever concerns); pinned so the
    /// keys it does model keep decoding beside them.
    func testTheFullServerSMSBlockDecodesDownToTheKeysWeModel() async throws {
        let body = """
        {"data":{"id":"11111111-1111-1111-1111-111111111111","destination":"+15551234567",\
        "delivery_method":"sms","fee":"0.06","status":"pending","error_code":null,\
        "error_detail":null,"expires_at":"\(Fixtures.farFuture)",\
        "sms":{"template":"default_otp","language":"de-DE","interception_timeout":120,\
        "app_hash":"A1b2C3d4E5f"}}}
        """
        let result = try await makeClient(transport: MockTransport(httpResponse(body))).status(makeHandle())
        XCTAssertEqual(result.details, .sms(.init(template: "default_otp", language: "de-DE")))
    }

    /// A block short of a key the API marks required still yields the rest — the same fail-open
    /// stance the enums take.
    func testAChannelBlockMissingItsKeysStillDecodes() async throws {
        let body = """
        {"data":{"id":"33333333-3333-3333-3333-333333333333","destination":"+15551234567",\
        "delivery_method":"callout","status":"pending","expires_at":"\(Fixtures.farFuture)",\
        "callout":{}}}
        """
        let result = try await makeClient(transport: MockTransport(httpResponse(body)))
            .status(makeHandle(method: .callout))
        XCTAssertEqual(result.details, .callout(.init(language: nil)))
    }

    /// A new status is non-terminal by construction, so a polling caller keeps polling rather than
    /// treating it as a settled outcome.
    func testNewStatusIsNonTerminalAndKeepsItsRawValue() async throws {
        let body = Fixtures.statusWithRawStatus("queued")
        let result = try await makeClient(transport: MockTransport(httpResponse(body))).status(makeHandle())
        XCTAssertEqual(result.status, .other("queued"))
        XCTAssertFalse(result.status.isTerminal)
    }

    /// A channel added server-side decodes to `.other(raw)` on both paths. This was the one
    /// fail-closed value in the SDK; a new channel used to break every installed copy on sight.
    func testNewDeliveryMethodDecodesAndKeepsItsRawValue() async throws {
        let body = """
        {"data":{"id":"11111111-1111-1111-1111-111111111111","destination":"+15551234567",\
        "delivery_method":"whatsapp","status":"pending","expires_at":"\(Fixtures.farFuture)",\
        "whatsapp":{"template":"default_otp"}}}
        """

        let result = try await makeClient(transport: MockTransport(httpResponse(body))).status(makeHandle())
        XCTAssertEqual(result.deliveryMethod, .other("whatsapp"))
        XCTAssertNil(result.details, "an unmodelled channel's block is not decoded, so there is nothing to expose")

        let started = try await makeClient(transport: MockTransport(httpResponse(body, status: 201)))
            .start(destination: "+15551234567", method: .sms)
        XCTAssertEqual(started.deliveryMethod, .other("whatsapp"))
        XCTAssertNil(started.details, "a block the SDK cannot read leaves the start handle's details nil")
    }

    /// …and the handle stays usable: the submit goes out with the raw method echoed back verbatim,
    /// so the server — not the SDK — has the final say on a channel it doesn't model.
    func testAnUnmodelledChannelCanStillBeSubmittedAgainst() async throws {
        let mock = MockTransport(httpResponse(Fixtures.verifiedSMS()))
        _ = try await makeClient(transport: mock)
            .verify(makeHandle(method: .other("whatsapp")), code: "123456")

        let body = requestBodyData(mock.recordedRequests[0])
        XCTAssertEqual(body["delivery_method"] as? String, "whatsapp", "the raw method must be echoed")
        XCTAssertEqual(body["code"] as? String, "123456")
    }

    // MARK: - Helper

    private func error(status: Int, body: String) async -> APIError? {
        let client = makeClient(transport: MockTransport(httpResponse(body, status: status)))
        do {
            _ = try await client.status(makeHandle())
            return nil
        } catch {
            return error as? APIError
        }
    }
}
