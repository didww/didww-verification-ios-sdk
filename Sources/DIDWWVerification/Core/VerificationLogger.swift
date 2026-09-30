import Foundation

/// Opt-in debug logging sink. Implement this to receive SDK log lines (already redacted).
public protocol VerificationLogger: Sendable {
    func log(_ message: String)
}

/// Masks sensitive values before anything reaches a logger.
///
/// Ordering matters: phone numbers are masked BEFORE codes, so the leading digits of a
/// phone number can't be mistaken for a code. Canonical UUIDs are skipped entirely, and both
/// patterns use digit-boundary lookarounds so a longer run isn't partially eaten.
enum Redactor {
    // A phone-ish run: optional '+', then 8–15 digits, not adjacent to other digits.
    private static let phonePattern = "(?<![0-9])\\+?[0-9]{8,15}(?![0-9])"
    // 4–8 digits, not part of a longer run — the OTP code shape; the server picks the length.
    private static let codePattern = "(?<![0-9])[0-9]{4,8}(?![0-9])"
    // Canonical UUIDs only, hyphens required — a bare hex blob is not an identifier here. Bounded on
    // both sides so a UUID glued to more hex/digits (no delimiter) isn't mistaken for one: a real
    // UUID never has extra characters butted directly against it.
    private static let uuidPattern =
        "(?<![0-9A-Fa-f-])[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}(?![0-9A-Fa-f-])"
    private static let uuidRegex = try? NSRegularExpression(pattern: uuidPattern)

    /// A UUID passes through whole: it is an identifier, not a secret, and masking part of one
    /// leaves a token still shaped like an id that no longer equals any record.
    static func redact(_ message: String) -> String {
        guard let uuids = uuidRegex else { return mask(message) }
        let text = message as NSString
        var result = ""
        var cursor = 0
        for match in uuids.matches(in: message, range: NSRange(location: 0, length: text.length)) {
            result += mask(text.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            result += text.substring(with: match.range)
            cursor = match.range.upperBound
        }
        return result + mask(text.substring(from: cursor))
    }

    private static func mask(_ segment: String) -> String {
        var result = replace(segment, pattern: phonePattern, with: "«redacted-number»")
        result = replace(result, pattern: codePattern, with: "«redacted-code»")
        return result
    }

    private static func replace(_ input: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let range = NSRange(input.startIndex..., in: input)
        return regex.stringByReplacingMatches(in: input, range: range, withTemplate: replacement)
    }
}
