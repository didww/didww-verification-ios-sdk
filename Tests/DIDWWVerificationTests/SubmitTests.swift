import Foundation
import XCTest
@testable import DIDWWVerification

final class SubmitTests: XCTestCase {
    func testVerifyCodeForSMSBuildsPUTWithTheMethodEchoed() async throws {
        let mock = MockTransport(httpResponse(Fixtures.verifiedSMS()))
        let client = makeClient(transport: mock)
        let handle = makeHandle(method: .sms)

        let result = try await client.verify(handle, code: "123456")

        let request = mock.recordedRequests[0]
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.absoluteString,
                       "https://verify.example.com/api/v1/verifications/\(handle.id)")
        let body = requestBodyData(request)
        XCTAssertEqual(body["delivery_method"] as? String, "sms")
        XCTAssertEqual(body["code"] as? String, "123456")
        XCTAssertEqual(result.status, .verified)
    }

    func testVerifyCodeForCalloutEchoesTheCalloutMethod() async throws {
        let mock = MockTransport(httpResponse(Fixtures.verifiedCallout()))
        let client = makeClient(transport: mock)
        let handle = makeHandle(method: .callout)

        let result = try await client.verify(handle, code: "123456")

        let body = requestBodyData(mock.recordedRequests[0])
        XCTAssertEqual(body["delivery_method"] as? String, "callout")
        XCTAssertEqual(body["code"] as? String, "123456")
        XCTAssertEqual(result.status, .verified)
    }

    // MARK: - By number

    func testVerifyByNumberCodeNormalizesTheNumberAndEchoesTheMethod() async throws {
        let mock = MockTransport(httpResponse(Fixtures.verifiedSMS()))
        let client = makeClient(transport: mock)

        let result = try await client.verify(number: "+1 (555) 123-4567", code: "123456", method: .sms)

        let request = mock.recordedRequests[0]
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.absoluteString,
                       "https://verify.example.com/api/v1/verifications/by_number/15551234567")
        let body = requestBodyData(request)
        XCTAssertEqual(body["delivery_method"] as? String, "sms")
        XCTAssertEqual(body["code"] as? String, "123456")
        XCTAssertEqual(result.status, .verified)
    }

    func testVerifyByNumberWithNoDigitsThrowsInvalidNumberAndSendsNothing() async {
        let mock = MockTransport(httpResponse(Fixtures.verifiedSMS()))
        let client = makeClient(transport: mock)

        do {
            _ = try await client.verify(number: "++--", code: "123456", method: .sms)
            XCTFail("expected invalidNumber")
        } catch {
            XCTAssertEqual(error as? VerificationError, .invalidNumber)
        }
        XCTAssertTrue(mock.recordedRequests.isEmpty, "invalidNumber must be caught before any network call")
    }

    func testVerifyByNumberWrongCodeMapsTo422() async {
        let mock = MockTransport(httpResponse(Fixtures.errorBody([(code: "code_invalid", detail: "invalid code")]), status: 422))
        let client = makeClient(transport: mock)

        do {
            _ = try await client.verify(number: "15551234567", code: "000000", method: .sms)
            XCTFail("expected validationFailed")
        } catch {
            XCTAssertEqual(error as? APIError, .validationFailed([APIErrorItem(code: "code_invalid", detail: "invalid code")]))
        }
    }

    func testVerifyByNumberDeliveryMethodMismatchMapsTo422() async {
        // A wrong sms-vs-callout `method:` and a wrong code BOTH surface as the server's 422 —
        // the messages differ, but there is deliberately no typed distinction between them.
        let mock = MockTransport(httpResponse(Fixtures.errorBody([(code: "delivery_method_invalid", detail: "delivery method mismatch")]), status: 422))
        let client = makeClient(transport: mock)

        do {
            _ = try await client.verify(number: "15551234567", code: "123456", method: .callout)
            XCTFail("expected validationFailed")
        } catch {
            XCTAssertEqual(error as? APIError, .validationFailed([APIErrorItem(code: "delivery_method_invalid", detail: "delivery method mismatch")]))
        }
    }

    func testVerifyByNumberNoActiveVerificationMapsTo404() async {
        // An already-verified verification is finished → 404 here, unlike submit-by-id.
        let mock = MockTransport(httpResponse(Fixtures.errorBody([(code: "not_found", detail: "not found")]), status: 404))
        let client = makeClient(transport: mock)

        do {
            _ = try await client.verify(number: "15551234567", code: "123456", method: .sms)
            XCTFail("expected notFound")
        } catch {
            XCTAssertEqual(error as? APIError, .notFound)
        }
    }
}
