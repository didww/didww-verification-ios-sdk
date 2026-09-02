import Foundation

/// Which DIDWW verification backend to target.
///
/// `.custom(url)` takes any scheme+host — a local backend, a proxy, or a test server. The SDK
/// appends `/api/v1` itself, so pass only the host (optionally with a base path).
public enum VerifyEnvironment: Sendable, Equatable {
    case production
    case sandbox
    case custom(URL)

    var baseURL: URL {
        switch self {
        case .production:      return URL(string: "https://verification.didww.com")!
        case .sandbox:         return URL(string: "https://verification-sandbox.didww.com")!
        case .custom(let url): return url
        }
    }
}
