/// The SDK's own version, matching `DIDWWVerification.podspec`'s `s.version` — asserted equal by
/// `SDKVersionTests` so the two cannot drift. Bump both together as part of a release.
enum SDKVersion {
    static let current = "1.1.0"

    /// Sent as the `User-Agent` of every request.
    static let userAgent = "didww-verification-ios/\(current)"
}
