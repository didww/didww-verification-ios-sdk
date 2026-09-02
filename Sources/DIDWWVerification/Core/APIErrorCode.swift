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
    case codeBlank = "code_blank"
    case codeValuePresent = "code_value_present"
    case cliBlank = "cli_blank"
    case cliValuePresent = "cli_value_present"
    case destinationNotSupportedForChannel = "destination_not_supported_for_channel"
    case codeInvalid = "code_invalid"
    case cliInvalid = "cli_invalid"

    // Domain (422)
    case alreadyVerified = "already_verified"
    case notReadyToReport = "not_ready_to_report"

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
}
