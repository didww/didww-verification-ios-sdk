import Foundation

/// Tunable client behavior.
public struct Configuration: Sendable {
    /// Per-request timeout in seconds. Maps to `URLRequest.timeoutInterval`.
    public var timeout: TimeInterval

    /// Debug logger; `nil` means logging is off. Messages are redacted of codes and phone numbers
    /// before they reach it.
    public var logger: (any VerificationLogger)?

    public init(timeout: TimeInterval = 30, logger: (any VerificationLogger)? = nil) {
        self.timeout = timeout
        self.logger = logger
    }
}
