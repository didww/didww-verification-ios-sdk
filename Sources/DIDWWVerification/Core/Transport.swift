import Foundation

/// A minimal HTTP response: status code + raw body bytes.
///
/// A plain `Sendable` value type rather than `HTTPURLResponse` — it crosses async boundaries
/// cleanly under strict concurrency, and a test double can just construct one.
struct HTTPResponse: Sendable, Equatable {
    let statusCode: Int
    let body: Data
    /// The `Retry-After` header, verbatim and unparsed — `nil` when the response sent none.
    let retryAfterHeader: String?

    /// Explicit rather than the synthesized memberwise init, so `retryAfterHeader` can default to
    /// `nil` — a `let` with an inline default is fixed at declaration and gets no initializer
    /// parameter at all, defaulted or otherwise.
    init(statusCode: Int, body: Data, retryAfterHeader: String? = nil) {
        self.statusCode = statusCode
        self.body = body
        self.retryAfterHeader = retryAfterHeader
    }
}

/// The client depends on this protocol, not on `URLSession` directly, so tests can inject a fake
/// transport and never touch the network.
protocol Transport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}
