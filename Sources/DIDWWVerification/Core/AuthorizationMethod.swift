import Foundation

/// How the client authenticates to the API.
///
/// The API ranks three auth modes, and each application carries a configured minimum:
/// `public` (`Application <appKey>`), `basic` (`Basic base64(appKey:secret)`), and a signed
/// `application` (`Application <appKey>:<signature>` plus `x-timestamp`). The header token is
/// `Application` for two of them, so these cases are named for the mode.
///
/// The signed mode is intentionally not implemented: it needs the shared secret on the device,
/// the same extraction risk that makes ``basic(appKey:secret:)`` development-only. Raising an
/// application's minimum above `public` therefore rejects every call this SDK makes.
public enum AuthorizationMethod: Sendable {
    /// The `public` mode. Header: `Authorization: Application <appKey>`.
    ///
    /// Requires the application to have a `callback_url` configured — by design, not a
    /// limitation: an app key is copyable out of any binary, so the server asks your callback to
    /// authorize each start. Without one a start is **not** rejected at the HTTP level; it
    /// returns `201` with `status: "denied"`, which surfaces on ``Verification/status``. See README.
    case `public`(appKey: String)
    /// App key + secret (development). Header: `Authorization: Basic base64(appKey:secret)`.
    case basic(appKey: String, secret: String)
}

extension AuthorizationMethod {
    /// The value for the HTTP `Authorization` header.
    var headerValue: String {
        switch self {
        case .public(let appKey):
            return "Application \(appKey)"
        case .basic(let appKey, let secret):
            let token = Data("\(appKey):\(secret)".utf8).base64EncodedString()
            return "Basic \(token)"
        }
    }
}
