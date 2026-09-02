import Foundation

/// A minimal HTTP response: status code + raw body bytes.
///
/// A plain `Sendable` value type rather than `HTTPURLResponse` — it crosses async boundaries
/// cleanly under strict concurrency, and a test double can just construct one.
struct HTTPResponse: Sendable, Equatable {
    let statusCode: Int
    let body: Data
}

/// The client depends on this protocol, not on `URLSession` directly, so tests can inject a fake
/// transport and never touch the network.
protocol Transport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}
