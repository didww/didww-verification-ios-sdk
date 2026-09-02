import Foundation

/// The current state of a verification, returned by `verify(...)` and `status(...)`.
public struct VerificationResult: Sendable, Equatable {
    public let id: String
    public let destination: String
    public let deliveryMethod: DeliveryMethod
    /// The verification fee quoted at creation, VAT included.
    ///
    /// A quote, not a charge: it is billed only on a `.verified` outcome, yet every outcome reports
    /// the same figure — so pair it with `status` rather than summing it. It is not the total cost
    /// either: delivering the SMS or call is billed separately as ordinary traffic, so a dispatched
    /// verification that ends `.failed`/`.expired` still costs the message, just not this fee.
    /// `Decimal`, never `Double`.
    public let fee: Decimal?
    public let status: Verification.Status
    /// Why a non-verified outcome ended that way. Informational, not an error. Typed convenience
    /// over ``errorCode`` — an unknown slug maps to `.other(rawSlug)`.
    public let reason: Verification.Reason?
    /// The raw outcome slug (`error_code`), or `nil` on a healthy verification. Survives even when
    /// ``reason`` is `.other`.
    public let errorCode: String?
    /// The raw outcome text (`error_detail`), or `nil` on a healthy verification.
    public let errorDetail: String?
    public let expiresAt: Date?
    /// The channel-specific block, keyed by `delivery_method`; `nil` when the server returned none
    /// this SDK version models. Read it with `if case .sms(let sms) = result.details { … }`.
    public let details: Verification.Details?

    public init(
        id: String,
        destination: String,
        deliveryMethod: DeliveryMethod,
        fee: Decimal?,
        status: Verification.Status,
        reason: Verification.Reason?,
        errorCode: String?,
        errorDetail: String?,
        expiresAt: Date?,
        details: Verification.Details?
    ) {
        self.id = id
        self.destination = destination
        self.deliveryMethod = deliveryMethod
        self.fee = fee
        self.status = status
        self.reason = reason
        self.errorCode = errorCode
        self.errorDetail = errorDetail
        self.expiresAt = expiresAt
        self.details = details
    }
}
