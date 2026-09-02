import Foundation

/// A handle to a started verification — pass it to `verify(_:code:)` / `status(_:)`.
///
/// The domain vocabulary (``Status``, ``Reason``, ``Details``) is nested on this type so it reads
/// with its owner: `Verification.Status`.
public struct Verification: Sendable, Equatable {
    /// Server id (a UUID string) — used as the path component for submit/status.
    public let id: String
    /// The destination the code was sent to (echoed back by the server).
    public let destination: String
    /// Which channel this verification uses — the code is delivered over it, and it goes back on
    /// the wire on every submit.
    public let deliveryMethod: DeliveryMethod
    /// When the verification expires. `start(...)` always provides this.
    public let expiresAt: Date

    /// The status at creation — a snapshot from the `start` response, never updated. Call
    /// `status(_:)` for the live state.
    ///
    /// ⚠️ Usually `.pending`, but a start can come back already settled: a denial is an ordinary
    /// `201 Created` carrying `"status": "denied"`, not an HTTP error, so nothing throws. Check
    /// this before showing a code-entry screen.
    public let status: Status
    /// The raw outcome slug at creation (`error_code`), or `nil` on a healthy start. Survives even
    /// when ``reason`` is `.other`.
    public let errorCode: String?
    /// The raw outcome text at creation (`error_detail`), or `nil`.
    public let errorDetail: String?
    /// The verification fee quoted at creation, VAT included.
    ///
    /// A quote, not a charge: it is billed only on a `.verified` outcome, and every outcome reports
    /// the same figure. It is not the total cost either — delivering the SMS or call is billed
    /// separately as ordinary traffic, so a verification that was dispatched and then
    /// `failed`/`expired` still costs the message, just not this fee. `Decimal`, never `Double`.
    public let fee: Decimal?
    /// The channel-specific block from the `start` response; `nil` when the server returned none
    /// this SDK version models. Carries the language the server settled on, so a fallback shows
    /// here rather than only after a `status(_:)` call.
    public let details: Details?

    /// Typed convenience over ``errorCode`` — an unknown slug maps to `.other(rawSlug)`.
    public var reason: Reason? { errorCode.map(Reason.init(wireValue:)) }

    /// Convenience: whether the expiry has passed (client clock).
    public var isExpired: Bool { Date() >= expiresAt }

    /// The outcome fields default to a healthy `.pending` start.
    public init(
        id: String,
        destination: String,
        deliveryMethod: DeliveryMethod,
        expiresAt: Date,
        status: Status = .pending,
        errorCode: String? = nil,
        errorDetail: String? = nil,
        fee: Decimal? = nil,
        details: Details? = nil
    ) {
        self.id = id
        self.destination = destination
        self.deliveryMethod = deliveryMethod
        self.expiresAt = expiresAt
        self.status = status
        self.errorCode = errorCode
        self.errorDetail = errorDetail
        self.fee = fee
        self.details = details
    }
}

// MARK: - Status

extension Verification {
    /// The lifecycle state of a verification.
    ///
    /// `.other(String)` exists so a status added by the server later decodes instead of throwing —
    /// your `switch` keeps compiling and polling keeps working. Treat it as non-terminal.
    public enum Status: Sendable, Equatable {
        case pending
        case verified
        case failed
        case expired
        case denied
        /// A status this SDK version doesn't know about. Carries the raw wire string.
        case other(String)

        init(wireValue: String) {
            switch wireValue {
            case "pending": self = .pending
            case "verified": self = .verified
            case "failed": self = .failed
            case "expired": self = .expired
            case "denied": self = .denied
            default: self = .other(wireValue)
            }
        }

        /// True once the verification can no longer change (terminal states).
        public var isTerminal: Bool {
            switch self {
            case .verified, .failed, .expired, .denied: return true
            case .pending, .other: return false
            }
        }
    }
}

// MARK: - Reason

extension Verification {
    /// Why a verification ended the way it did. Informational result data on a
    /// `failed`/`denied`/`expired` outcome — not an error, since a non-verified outcome is still a
    /// successful HTTP call. Fail-open like ``Status``: an unknown slug decodes to `.other`.
    public enum Reason: Sendable, Equatable {
        case numberUnreachable
        case failedToDeliver
        case expired
        case tooManyAttempts
        case applicationDeleted
        // No flat `denied` case: the server always names *why* it denied, with the three slugs
        // below. A bare `"denied"` would decode to `.other("denied")`.
        /// The application's callback actively denied the request.
        case deniedByCallback
        /// The application has no `callback_url` configured, which public auth requires.
        case deniedMissingCallbackURL
        /// The application's callback returned a response the server could not use.
        case deniedInvalidCallbackResponse
        /// A newer `start` for the same number replaced this verification. Only ever seen via
        /// by-id `status(_:)` — by-number always resolves the newest verification.
        case superseded
        /// A slug this SDK version doesn't recognize.
        case other(String)

        init(wireValue: String) {
            switch wireValue {
            case "stale_dispatch": self = .numberUnreachable
            case "dispatch_failed": self = .failedToDeliver
            case "expired": self = .expired
            case "too_many_attempts": self = .tooManyAttempts
            case "application_deleted": self = .applicationDeleted
            case "denied_by_callback": self = .deniedByCallback
            case "denied_missing_callback_url": self = .deniedMissingCallbackURL
            case "denied_invalid_callback_response": self = .deniedInvalidCallbackResponse
            case "superseded": self = .superseded
            default: self = .other(wireValue)
            }
        }
    }
}

// MARK: - Details

extension Verification {
    /// Delivery-method-specific result payload — a nested block keyed by the active
    /// `delivery_method` (`"sms": { "template": …, "language": … }`).
    ///
    /// No `.other` case here, unlike ``Status``/``Reason``, and none is needed: this enum models the
    /// blocks the SDK knows how to read, and a block for a channel it doesn't model is never decoded
    /// at all — ``VerificationResult/details`` is simply `nil`. There is nothing an `.other` case
    /// could carry. Both known channels are seeded up front so new keys arrive as struct fields,
    /// not as a source-breaking enum case.
    public enum Details: Sendable, Equatable {
        case sms(SMS)
        case callout(Callout)

        public struct SMS: Sendable, Equatable {
            public let template: String?
            /// The tag the message was rendered in — your first matching ``SMSOptions/languages``,
            /// or the server's `en-US` fallback. Compare with what you asked for to spot a fallback.
            public let language: String?
        }

        public struct Callout: Sendable, Equatable {
            /// The tag the code is announced in — your first matching ``CalloutOptions/languages``,
            /// or the server's `en-US` fallback. Compare with what you asked for to spot a fallback.
            public let language: String?
        }
    }
}
