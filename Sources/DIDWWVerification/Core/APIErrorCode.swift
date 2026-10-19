import Foundation

/// The error slugs carried by an ``APIErrorItem`` on a thrown ``APIError``.
///
/// Fail-open by construction: there is no `.other` case (Swift forbids a raw type plus an
/// associated value), so an unrecognized slug just makes `APIErrorCode(rawValue:)` return `nil`
/// while the raw string survives on ``APIErrorItem/code``. Switch on ``APIErrorItem/known`` and
/// fall back to `code`.
public enum APIErrorCode: String, Sendable, Equatable, CaseIterable {
    // Validation (422)
    case destinationBlank = "destination_blank"
    case destinationInvalid = "destination_invalid"
    case deliveryMethodBlank = "delivery_method_blank"
    case deliveryMethodInclusion = "delivery_method_inclusion"
    case deliveryMethodInvalid = "delivery_method_invalid"
    case languagesInvalid = "languages_invalid"
    case appHashInvalid = "app_hash_invalid"
    case autofillInvalid = "autofill_invalid"
    case customTooLong = "custom_too_long"
    case codeBlank = "code_blank"
    /// No longer sent by the API; kept for source compatibility.
    case codeValuePresent = "code_value_present"
    /// No longer sent by the API; kept for source compatibility.
    case cliBlank = "cli_blank"
    /// No longer sent by the API; kept for source compatibility.
    case cliValuePresent = "cli_value_present"
    // Kept for compatibility: a destination the channel can't reach now comes back as a `201`
    // with ``Verification/Reason/destinationNotSupportedForChannel``.
    case destinationNotSupportedForChannel = "destination_not_supported_for_channel"
    case codeInvalid = "code_invalid"
    /// No longer sent by the API; kept for source compatibility.
    case cliInvalid = "cli_invalid"

    // Domain (422)
    case alreadyVerified = "already_verified"
    case notReadyToReport = "not_ready_to_report"
    case templateGroupNotFound = "template_group_not_found"
    case smsDomainNotConfigured = "sms_domain_not_configured"

    // Generic fallback (422)
    case validationFailed = "validation_failed"

    // Controller / status-coded
    case parameterMissing = "parameter_missing"       // 400
    // 401. Seldom seen as an item — ``APIError/unauthorized`` discards the body on purpose — but the
    // slug is in the server's registry, so it types when it does turn up.
    case unauthorized = "unauthorized"                 // 401
    case notFound = "not_found"                        // 404
    case balanceInsufficient = "balance_insufficient"  // 402
    case internalError = "internal_error"              // 422 / 500
    // A verification for this destination was requested too recently. Still maps to
    // ``APIError/unexpectedStatus(code:items:)`` — a dedicated `APIError` case is deferred.
    case destinationInCooldown = "destination_in_cooldown"  // 429
    // The application reached its daily or monthly verification limit for the delivery method.
    case volumeLimitReached = "volume_limit_reached"        // 429
    // Too many requests (or failed authentications) from this IP address or for this account.
    case rateLimitPerIP = "rate_limit_per_ip"                          // 429
    case rateLimitFailedAuth = "rate_limit_failed_auth"                // 429
    case rateLimitPerAccount = "rate_limit_per_account"                // 429
    case rateLimitPublicPerAccount = "rate_limit_public_per_account"  // 429
}
