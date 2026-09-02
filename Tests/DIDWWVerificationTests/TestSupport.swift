import Foundation
import XCTest
@testable import DIDWWVerification

// MARK: - Fake transports

/// Returns canned responses in order and records every request it received. `@unchecked Sendable`
/// because its mutable state is lock-guarded (the compiler can't prove that on its own).
final class MockTransport: Transport, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<HTTPResponse, Error>]
    private var _recordedRequests: [URLRequest] = []

    var recordedRequests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return _recordedRequests
    }

    init(_ response: HTTPResponse) { self.results = [.success(response)] }
    init(results: [Result<HTTPResponse, Error>]) { self.results = results }
    init(error: Error) { self.results = [.failure(error)] }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        // NSLock's lock()/unlock() are banned directly in an async context under Swift 6, so the
        // locked critical section lives in a synchronous helper.
        guard let next = dequeue(recording: request) else {
            throw APIError.unexpectedResponse("mock: no more responses")
        }
        switch next {
        case .success(let response): return response
        case .failure(let error): throw error
        }
    }

    private func dequeue(recording request: URLRequest) -> Result<HTTPResponse, Error>? {
        lock.lock(); defer { lock.unlock() }
        _recordedRequests.append(request)
        return results.isEmpty ? nil : results.removeFirst()
    }
}

/// Suspends inside `send` until the test either completes it or the surrounding Task is cancelled.
/// Used to exercise cancellation end-to-end through the client.
final class SuspendingMockTransport: Transport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<HTTPResponse, Error>?
    /// Fulfilled once `send` is actually suspended, so the test can cancel at the right moment.
    let didSuspend = XCTestExpectation(description: "transport suspended")

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<HTTPResponse, Error>) in
                lock.lock(); continuation = c; lock.unlock()
                didSuspend.fulfill()
            }
        } onCancel: {
            lock.lock(); let c = continuation; continuation = nil; lock.unlock()
            c?.resume(throwing: CancellationError())
        }
    }

    func complete(with response: HTTPResponse) {
        lock.lock(); let c = continuation; continuation = nil; lock.unlock()
        c?.resume(returning: response)
    }
}

/// Collects log lines for assertions.
final class StubLogger: VerificationLogger, @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [String] = []
    var lines: [String] { lock.lock(); defer { lock.unlock() }; return _lines }
    func log(_ message: String) { lock.lock(); _lines.append(message); lock.unlock() }
}

// MARK: - Helpers

func makeClient(
    transport: any Transport,
    configuration: Configuration = .init(),
    auth: AuthorizationMethod = .basic(appKey: "key", secret: "secret"),
    baseURL: String = "https://verify.example.com"
) -> VerificationClient {
    VerificationClient(
        baseURL: URL(string: baseURL)!,
        auth: auth,
        configuration: configuration,
        transport: transport
    )
}

/// Build an `HTTPResponse` from a JSON string.
func httpResponse(_ json: String, status: Int = 200) -> HTTPResponse {
    HTTPResponse(statusCode: status, body: Data(json.utf8))
}

/// Decode the `data` object of a recorded request's JSON body.
func requestBodyData(_ request: URLRequest) -> [String: Any] {
    guard let body = request.httpBody,
          let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
          let data = root["data"] as? [String: Any] else {
        return [:]
    }
    return data
}

/// A `Verification` handle for submit/status tests, without needing a start round-trip.
func makeHandle(id: String = "11111111-1111-1111-1111-111111111111",
                destination: String = "+15551234567",
                method: DeliveryMethod = .sms,
                expiresAt: Date = Date().addingTimeInterval(300)) -> Verification {
    Verification(id: id, destination: destination, deliveryMethod: method, expiresAt: expiresAt)
}
