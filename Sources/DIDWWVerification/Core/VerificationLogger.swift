import Foundation

/// Opt-in debug logging sink. Implement this to receive SDK log lines (already redacted).
public protocol VerificationLogger: Sendable {
    func log(_ message: String)
}

/// Masks sensitive values before anything reaches a logger.
///
/// Ordering matters: phone numbers are masked BEFORE 6-digit codes, so the leading digits of a
/// phone number can't be mistaken for a code. Both patterns use digit-boundary lookarounds so a
/// longer run (UUID fragment, timestamp, epoch) isn't partially eaten.
enum Redactor {
    // A phone-ish run: optional '+', then 8–15 digits, not adjacent to other digits.
    private static let phonePattern = "(?<![0-9])\\+?[0-9]{8,15}(?![0-9])"
    // Exactly 6 digits, not part of a longer run — the OTP code shape.
    private static let codePattern = "(?<![0-9])[0-9]{6}(?![0-9])"

    static func redact(_ message: String) -> String {
        var result = replace(message, pattern: phonePattern, with: "«redacted-number»")
        result = replace(result, pattern: codePattern, with: "«redacted-code»")
        return result
    }

    private static func replace(_ input: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let range = NSRange(input.startIndex..., in: input)
        return regex.stringByReplacingMatches(in: input, range: range, withTemplate: replacement)
    }
}
