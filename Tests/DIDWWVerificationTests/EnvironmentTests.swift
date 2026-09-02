import Foundation
import XCTest
@testable import DIDWWVerification

final class EnvironmentTests: XCTestCase {
    func testNamedEnvironmentsMapToExpectedHosts() {
        XCTAssertEqual(VerifyEnvironment.production.baseURL, URL(string: "https://verification.didww.com"))
        XCTAssertEqual(VerifyEnvironment.sandbox.baseURL, URL(string: "https://verification-sandbox.didww.com"))
    }

    func testCustomEnvironmentPassesThroughURL() {
        let url = URL(string: "https://verify.example.com")!
        XCTAssertEqual(VerifyEnvironment.custom(url).baseURL, url)
    }

    /// The public API takes a `VerifyEnvironment`, not a URL — assert a request really is routed to
    /// the selected environment's host.
    func testClientRoutesRequestToSelectedEnvironmentHost() async throws {
        let mock = MockTransport(httpResponse(Fixtures.startSMS(), status: 201))
        let client = VerificationClient(
            environment: .sandbox,
            auth: .basic(appKey: "key", secret: "secret"),
            transport: mock
        )

        _ = try await client.start(destination: "+15551234567", method: .sms)

        XCTAssertEqual(mock.recordedRequests.first?.url?.absoluteString,
                       "https://verification-sandbox.didww.com/api/v1/verifications")
    }
}
