import Foundation
import XCTest
@testable import DIDWWVerification

final class ErrorMappingTests: XCTestCase {
    private func expect(status: Int, body: String, toThrow expected: APIError,
                        file: StaticString = #filePath, line: UInt = #line) async {
        let mock = MockTransport(httpResponse(body, status: status))
        let client = makeClient(transport: mock)
        do {
            _ = try await client.status(makeHandle())
            XCTFail("expected error for status \(status)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? APIError, expected, file: file, line: line)
        }
    }

    /// Runs `status` against a mocked error response and returns the thrown `APIError`.
    private func errorFrom(status: Int, body: String,
                           file: StaticString = #filePath, line: UInt = #line) async -> APIError? {
        let mock = MockTransport(httpResponse(body, status: status))
        let client = makeClient(transport: mock)
        do {
            _ = try await client.status(makeHandle())
            XCTFail("expected error for status \(status)", file: file, line: line)
            return nil
        } catch {
            return error as? APIError
        }
    }

    func test400InvalidParameters() async {
        await expect(status: 400,
                     body: Fixtures.errorBody([(code: "parameter_missing", detail: "destination is missing")]),
                     toThrow: .invalidParameters([APIErrorItem(code: "parameter_missing", detail: "destination is missing")]))
    }

    /// 401 carries the coded envelope like every other 4xx; it maps to the payload-free case anyway,
    /// and decoding the body must not throw.
    func test401UnauthorizedWithCodedEnvelope() async {
        await expect(status: 401,
                     body: Fixtures.errorBody([(code: "unauthorized", detail: "unauthorized")]),
                     toThrow: .unauthorized)
    }

    /// Still tolerated: earlier server versions answered 401 with no body at all.
    func test401UnauthorizedEmptyBody() async {
        await expect(status: 401, body: "", toThrow: .unauthorized)
    }

    func test402InsufficientBalance() async {
        await expect(status: 402,
                     body: Fixtures.errorBody([(code: "balance_insufficient", detail: "insufficient balance")]),
                     toThrow: .insufficientBalance)
    }

    func test404NotFound() async {
        await expect(status: 404,
                     body: Fixtures.errorBody([(code: "not_found", detail: "not found")]),
                     toThrow: .notFound)
    }

    func test422ValidationFailed() async {
        await expect(status: 422,
                     body: Fixtures.errorBody([(code: "code_invalid", detail: "invalid code")]),
                     toThrow: .validationFailed([APIErrorItem(code: "code_invalid", detail: "invalid code")]))
    }

    func test500MapsToUnexpectedStatus() async {
        await expect(status: 500, body: "", toThrow: .unexpectedStatus(code: 500, items: []))
    }

    func testTransportErrorSurfacesTyped() async {
        let mock = MockTransport(error: APIError.transport(URLError(.notConnectedToInternet)))
        let client = makeClient(transport: mock)
        do {
            _ = try await client.status(makeHandle())
            XCTFail("expected transport error")
        } catch {
            XCTAssertEqual(error as? APIError, .transport(URLError(.notConnectedToInternet)))
        }
    }

    // MARK: - Raw + typed slug exposure

    /// A known slug decodes to the item with the right code/detail AND the typed `.known`.
    func testKnownSlugExposesTypedKnown() async {
        let body = Fixtures.errorBody([(code: "destination_blank", detail: "destination can't be blank")])
        guard case .validationFailed(let items) = await errorFrom(status: 422, body: body) else {
            return XCTFail("expected .validationFailed")
        }
        XCTAssertEqual(items, [APIErrorItem(code: "destination_blank", detail: "destination can't be blank")])
        XCTAssertEqual(items.first?.known, .destinationBlank)
    }

    /// An unknown slug keeps `code` intact and yields `known == nil`, without throwing.
    func testUnknownSlugKeepsRawCodeWithNilKnown() async {
        let body = Fixtures.errorBody([(code: "future_slug_from_mars", detail: "who knows")])
        guard case .validationFailed(let items) = await errorFrom(status: 422, body: body) else {
            return XCTFail("expected .validationFailed")
        }
        XCTAssertEqual(items.first?.code, "future_slug_from_mars")
        XCTAssertNil(items.first?.known)
    }

    /// A `code`-less element is dropped while its valid siblings survive — one malformed element
    /// must never cost the whole body.
    func testMultiElementBodyDropsCodelessElementKeepsSiblings() async {
        // Middle element has no `code` (only `detail`) → must be dropped; siblings survive.
        let raw = """
        {"code":"destination_blank","detail":"destination can't be blank"},\
        {"detail":"orphaned message with no code"},\
        {"code":"code_invalid","detail":"invalid code"}
        """
        let body = Fixtures.rawErrorBody(raw)
        guard case .validationFailed(let items) = await errorFrom(status: 422, body: body) else {
            return XCTFail("expected .validationFailed")
        }
        XCTAssertEqual(items, [
            APIErrorItem(code: "destination_blank", detail: "destination can't be blank"),
            APIErrorItem(code: "code_invalid", detail: "invalid code"),
        ])
        XCTAssertEqual(items.map(\.known), [.destinationBlank, .codeInvalid])
    }

    /// A missing `detail` on an otherwise-valid element defaults to "" (tolerant), element survives.
    func testElementWithMissingDetailDefaultsToEmptyString() async {
        let body = Fixtures.rawErrorBody(#"{"code":"already_verified"}"#)
        guard case .validationFailed(let items) = await errorFrom(status: 422, body: body) else {
            return XCTFail("expected .validationFailed")
        }
        XCTAssertEqual(items, [APIErrorItem(code: "already_verified", detail: "")])
        XCTAssertEqual(items.first?.known, .alreadyVerified)
    }

    // MARK: - Registry coverage

    /// The server's `ErrorRegistry::Slugs`, verbatim. Every slug must be modelled by exactly one of
    /// the two types — `APIErrorCode` for envelope errors, `Verification.Reason` for the outcome
    /// slug on a 2xx verification. This is the check that would have caught `unauthorized` and
    /// `app_hash_invalid` going missing.
    private static let serverSlugs = [
        "already_verified", "app_hash_invalid", "application_deleted", "balance_insufficient",
        "cli_blank", "cli_invalid", "cli_value_present", "code_blank", "code_invalid",
        "code_value_present", "delivery_method_blank", "delivery_method_inclusion",
        "delivery_method_invalid", "denied_by_callback", "denied_invalid_callback_response",
        "denied_missing_callback_url", "destination_blank", "destination_invalid",
        "destination_not_supported_for_channel", "dispatch_failed", "expired", "internal_error",
        "languages_invalid", "not_found", "not_ready_to_report", "parameter_missing",
        "stale_dispatch", "superseded", "too_many_attempts", "unauthorized", "validation_failed",
    ]

    func testEveryServerSlugIsModelledByExactlyOneType() {
        XCTAssertEqual(Self.serverSlugs.count, 31, "the server registry has 31 slugs")
        for slug in Self.serverSlugs {
            let isEnvelopeError = APIErrorCode(rawValue: slug) != nil
            let isOutcomeReason = Verification.Reason(wireValue: slug) != .other(slug)
            XCTAssertTrue(isEnvelopeError || isOutcomeReason, "'\(slug)' is not modelled by either type")
            XCTAssertFalse(isEnvelopeError && isOutcomeReason, "'\(slug)' is modelled by both types")
        }
        XCTAssertEqual(APIErrorCode.allCases.count, 22)
    }

    /// `app_hash_invalid` is a request-validation slug, so it belongs on the envelope type.
    func test422AppHashInvalidTypesKnown() async {
        let body = Fixtures.errorBody([(code: "app_hash_invalid", detail: "app_hash is invalid")])
        guard case .validationFailed(let items) = await errorFrom(status: 422, body: body) else {
            return XCTFail("expected .validationFailed")
        }
        XCTAssertEqual(items.first?.known, .appHashInvalid)
    }

    /// `unauthorized` types too. It seldom reaches a caller as an item — `APIError.unauthorized`
    /// discards the 401 body on purpose — but the slug is in the registry and must resolve.
    func testUnauthorizedSlugTypesKnown() {
        XCTAssertEqual(APIErrorItem(code: "unauthorized", detail: "unauthorized").known, .unauthorized)
    }
}
