import Foundation

/// Reduces a phone number to its ASCII digits, mirroring the server's own normalization. Filters
/// `unicodeScalars` rather than `Character.isNumber`, which would admit non-ASCII digits the server
/// strips.
///
/// Digits-only is load-bearing, not hygiene: a `.` in a path segment is read as a format suffix and
/// silently truncates the number, and the log ``Redactor`` only masks digits-only runs — so a
/// formatted number in a URL would leak past it.
enum PhoneNumberNormalizer {
    static func normalize(_ raw: String) -> String {
        String(raw.unicodeScalars.filter { ("0"..."9").contains($0) })
    }
}
