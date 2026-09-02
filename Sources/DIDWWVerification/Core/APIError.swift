import Foundation

/// Every network/HTTP failure the SDK surfaces. Branch on the typed cases, never on message
/// strings.
///
/// Client-side usage guards the SDK raises itself live in ``VerificationError`` instead, so callers
/// catch two flat types.
public enum APIError: Error, Sendable, Equatable {
    /// HTTP 400 — malformed/invalid request parameters. Carries the server's error items.
    case invalidParameters([APIErrorItem])
    /// HTTP 401 — authentication failed. Carries no items on purpose: the server answers every
    /// cause (bad key, wrong secret, disabled account, insufficient auth mode, no plan) with the
    /// single `unauthorized` slug so the response can't leak which one it was.
    case unauthorized
    /// HTTP 402 — insufficient balance.
    case insufficientBalance
    /// HTTP 404 — resource not found.
    case notFound
    /// HTTP 422 — validation/report failure. Carries the server's error items.
    case validationFailed([APIErrorItem])
    /// Any other non-2xx status. Carries the code and any server error items.
    case unexpectedStatus(code: Int, items: [APIErrorItem])
    /// A response we couldn't make sense of (bad envelope, unknown enum, missing required field).
    case unexpectedResponse(String)
    /// A transport-level failure (offline, DNS, TLS, timeout). Cancellation is surfaced separately
    /// as Swift's `CancellationError`, not here.
    case transport(URLError)
}

/// One element of the server's `{"errors":[{"code":…,"detail":…}]}` envelope.
///
/// ``code`` is the raw slug and always survives; ``known`` is its typed form when this SDK version
/// recognizes it. Branch on `code` or `known`, never on `detail`.
public struct APIErrorItem: Sendable, Equatable {
    /// The raw slug, always present.
    public let code: String
    /// Human-readable text for the slug.
    public let detail: String

    public init(code: String, detail: String) {
        self.code = code
        self.detail = detail
    }

    /// The typed slug when this SDK version recognizes it, else `nil`. Computed, so it takes no
    /// part in `Equatable`.
    public var known: APIErrorCode? { APIErrorCode(rawValue: code) }
}
