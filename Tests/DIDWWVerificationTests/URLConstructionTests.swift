import Foundation
import XCTest
@testable import DIDWWVerification

final class URLConstructionTests: XCTestCase {
    private func factory(_ base: String, timeout: TimeInterval = 30) -> RequestFactory {
        RequestFactory(baseURL: URL(string: base)!, auth: .public(appKey: "k"), timeout: timeout)
    }

    func testBaseWithoutTrailingSlash() {
        let request = factory("https://verify.example.com").request(method: "GET", path: ["verifications", "abc"])
        XCTAssertEqual(request.url?.absoluteString, "https://verify.example.com/api/v1/verifications/abc")
    }

    func testBaseWithTrailingSlash() {
        let request = factory("https://verify.example.com/").request(method: "GET", path: ["verifications"])
        XCTAssertEqual(request.url?.absoluteString, "https://verify.example.com/api/v1/verifications")
    }

    func testBaseWithEmbeddedPath() {
        let request = factory("https://verify.example.com/gateway").request(method: "GET", path: ["verifications"])
        XCTAssertEqual(request.url?.absoluteString, "https://verify.example.com/gateway/api/v1/verifications")
    }

    func testApplicationAuthHeader() {
        let request = factory("https://x.example").request(method: "GET", path: ["verifications"])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Application k")
    }

    func testBasicAuthHeaderIsBase64() {
        let f = RequestFactory(baseURL: URL(string: "https://x.example")!,
                               auth: .basic(appKey: "key", secret: "secret"), timeout: 30)
        let request = f.request(method: "GET", path: ["verifications"])
        let expected = "Basic " + Data("key:secret".utf8).base64EncodedString()
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), expected)
    }

    func testTimeoutPlumbedIntoRequest() {
        let request = factory("https://x.example", timeout: 12).request(method: "GET", path: ["verifications"])
        XCTAssertEqual(request.timeoutInterval, 12, accuracy: 0.001)
    }

    // MARK: - By-number paths (normalization happens in the client, so these go through it)

    func testByNumberPathIsDigitsOnly() async throws {
        let mock = MockTransport(httpResponse(Fixtures.startSMS()))
        let client = makeClient(transport: mock)

        _ = try await client.status(number: "15551234567")

        XCTAssertEqual(mock.recordedRequests[0].url?.absoluteString,
                       "https://verify.example.com/api/v1/verifications/by_number/15551234567")
    }

    func testFormattedNumbersNormalizeToTheSameURL() async throws {
        // Formatting must never reach the path: a '.' reads as a format suffix and truncates the
        // number, and '+'/'('/')' are left literal by appendPathComponent.
        let mock = MockTransport(results: [
            .success(httpResponse(Fixtures.startSMS())),
            .success(httpResponse(Fixtures.startSMS())),
            .success(httpResponse(Fixtures.startSMS())),
        ])
        let client = makeClient(transport: mock)

        _ = try await client.status(number: "+1 (555) 123-4567")
        _ = try await client.status(number: "+1.555.1234567")
        _ = try await client.status(number: "15551234567")

        let urls = mock.recordedRequests.map { $0.url?.absoluteString }
        XCTAssertEqual(urls, Array(repeating: "https://verify.example.com/api/v1/verifications/by_number/15551234567",
                                   count: 3))
    }
}
