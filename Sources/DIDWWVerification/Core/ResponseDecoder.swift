import Foundation

/// Turns an `HTTPResponse` into either a decoded, `data`-wrapped payload or a typed `APIError`.
enum ResponseDecoder {
    /// A success status → decode the `data`-wrapped `T`. Anything else → typed `APIError`.
    static func decode<T: Decodable>(_ response: HTTPResponse, successCodes: Set<Int>) throws -> T {
        guard successCodes.contains(response.statusCode) else {
            throw mapError(statusCode: response.statusCode, body: response.body)
        }
        do {
            return try JSONDecoder().decode(ResponseEnvelope<T>.self, from: response.body).data
        } catch {
            throw APIError.unexpectedResponse("could not decode response body: \(error)")
        }
    }

    /// Map a non-success status to a typed error. Any status may carry `{ "errors": [...] }`;
    /// a missing or malformed body just yields no items. 401's body is discarded — see
    /// ``APIError/unauthorized``.
    static func mapError(statusCode: Int, body: Data) -> APIError {
        let items = (try? JSONDecoder().decode(APIErrorBody.self, from: body))?.errors
            .map { APIErrorItem(code: $0.code, detail: $0.detail) } ?? []
        switch statusCode {
        case 400: return .invalidParameters(items)
        case 401: return .unauthorized
        case 402: return .insufficientBalance
        case 404: return .notFound
        case 422: return .validationFailed(items)
        default: return .unexpectedStatus(code: statusCode, items: items)
        }
    }
}
