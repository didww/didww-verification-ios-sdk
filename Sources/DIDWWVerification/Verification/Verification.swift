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
        /// Deprecated: the `stale_dispatch` slug, which the service no longer sends. These
        /// verifications now arrive as ``failedToDeliver``. Removed in the next major version.
        // Not `@available(*, deprecated)`: `init(wireValue:)` still maps the slug, and the attribute
        // would warn on that use in every build of the package.
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
        /// The application is paused. Status `denied`.
        case applicationPaused
        /// The destination's country is disabled in the account settings. Status `denied`.
        case destinationCountryDisabled
        /// The destination can't be reached over the requested channel. Status `failed`.
        case destinationNotSupportedForChannel
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
            case "application_paused": self = .applicationPaused
            case "destination_country_disabled": self = .destinationCountryDisabled
            case "destination_not_supported_for_channel": self = .destinationNotSupportedForChannel
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
            /// The OTP code length, 4–8, set per application. Size a code-entry input from it.
            public let codeLength: Int?
            /// The autofill marker the message carries; `nil` when it carries none.
            public let autofill: Autofill?
            /// The template group applied, or `nil` when none was.
            public let templateGroup: String?
            /// Whether the message was rendered from ``templateGroup``'s template.
            public let templateGroupUsed: Bool?
            /// Why the group's template was not used; `nil` when it was, or when no template group
            /// applies at all (then ``templateGroupUsed`` is `false`).
            public let templateFallbackReason: TemplateFallbackReason?

            init(template: String?, language: String?, codeLength: Int?, autofill: Autofill? = nil,
                 templateGroup: String? = nil, templateGroupUsed: Bool? = nil,
                 templateFallbackReason: TemplateFallbackReason? = nil) {
                self.template = template
                self.language = language
                self.codeLength = codeLength
                self.autofill = autofill
                self.templateGroup = templateGroup
                self.templateGroupUsed = templateGroupUsed
                self.templateFallbackReason = templateFallbackReason
            }

            /// The autofill marker the server stored for the message.
            public struct Autofill: Sendable, Equatable {
                public let type: Kind
                /// The Android app hash, or the domain for ``Kind/domain``.
                public let value: String

                /// Fail-open: a marker added by the server later decodes as `.other`.
                public enum Kind: Sendable, Equatable {
                    /// Android SMS Retriever framing — set by a request from an Android app.
                    case appHash
                    /// The domain-bound line iOS reads to suggest the code.
                    case domain
                    /// A marker this SDK version doesn't know about. Carries the raw wire string.
                    case other(String)

                    init(wireValue: String) {
                        switch wireValue {
                        case "app_hash": self = .appHash
                        case "domain": self = .domain
                        default: self = .other(wireValue)
                        }
                    }
                }

                init(type: Kind, value: String) {
                    self.type = type
                    self.value = value
                }

                /// `nil` when the block is short of either key.
                init?(dto: AutofillInfo) {
                    guard let type = dto.type, let value = dto.value else { return nil }
                    self.init(type: Kind(wireValue: type), value: value)
                }
            }
        }

        public struct Callout: Sendable, Equatable {
            /// The tag the code is announced in — your first matching ``CalloutOptions/languages``,
            /// or the server's `en-US` fallback. Compare with what you asked for to spot a fallback.
            public let language: String?
            /// The OTP code length, 4–8, set per application. Size a code-entry input from it.
            public let codeLength: Int?
            /// The template group applied, or `nil` when none was.
            public let templateGroup: String?
            /// Whether the call was announced from ``templateGroup``'s template.
            public let templateGroupUsed: Bool?
            /// Why the group's template was not used; `nil` when it was, or when no template group
            /// applies at all (then ``templateGroupUsed`` is `false`).
            public let templateFallbackReason: TemplateFallbackReason?

            init(language: String?, codeLength: Int?, templateGroup: String? = nil,
                 templateGroupUsed: Bool? = nil, templateFallbackReason: TemplateFallbackReason? = nil) {
                self.language = language
                self.codeLength = codeLength
                self.templateGroup = templateGroup
                self.templateGroupUsed = templateGroupUsed
                self.templateFallbackReason = templateFallbackReason
            }
        }
    }
}

// MARK: - TemplateFallbackReason

extension Verification {
    /// Why a requested template group's template was not used, so the default one was. Fail-open
    /// like ``Status``: an unknown reason decodes to `.other`.
    public enum TemplateFallbackReason: Sendable, Equatable {
        /// The group has no template in the language used.
        case languageMissing
        /// The group's template is still awaiting review.
        case versionPending
        /// The group's template was rejected in review.
        case versionRejected
        /// The group's callout template has no recording yet.
        case audioNotReady
        /// The group no longer exists.
        case groupMissing
        /// A reason this SDK version doesn't recognize.
        case other(String)

        init(wireValue: String) {
            switch wireValue {
            case "language_missing": self = .languageMissing
            case "version_pending": self = .versionPending
            case "version_rejected": self = .versionRejected
            case "audio_not_ready": self = .audioNotReady
            case "group_missing": self = .groupMissing
            default: self = .other(wireValue)
            }
        }
    }
}
