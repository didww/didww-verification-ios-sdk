import Foundation

/// Builds `URLRequest`s: owns the `/api/v1` prefix, the auth header, timeout, and JSON body.
///
/// Paths are built by appending components, avoiding the `URL(string:relativeTo:)` trap where a
/// base without a trailing slash silently drops its last path segment.
struct RequestFactory: Sendable {
    let baseURL: URL
    let auth: AuthorizationMethod
    let timeout: TimeInterval

    private func url(_ components: [String]) -> URL {
        var url = baseURL
        url.appendPathComponent("api")
        url.appendPathComponent("v1")
        for component in components {
            url.appendPathComponent(component)
        }
        return url
    }

    /// A request with no body (GET).
    func request(method: String, path components: [String]) -> URLRequest {
        var request = URLRequest(url: url(components), timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue(auth.headerValue, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// A request carrying a JSON body (POST/PUT).
    func request<Body: Encodable>(method: String, path components: [String], jsonBody: Body) throws -> URLRequest {
        var request = self.request(method: method, path: components)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(jsonBody)
        return request
    }
}
