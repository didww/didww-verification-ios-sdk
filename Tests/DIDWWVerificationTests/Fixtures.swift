import Foundation

/// Canned JSON response bodies shaped like the backend's `data`-wrapped envelope.
enum Fixtures {
    static let farFuture = "2999-01-01T00:00:00Z"
    static let farPast = "2000-01-01T00:00:00Z"
    static let fractional = "2026-07-13T12:00:00.123Z"

    static func startSMS(id: String = "11111111-1111-1111-1111-111111111111",
                         destination: String = "+15551234567",
                         expiresAt: String = farFuture) -> String {
        """
        {"data":{"id":"\(id)","destination":"\(destination)","delivery_method":"sms",\
        "status":"pending","expires_at":"\(expiresAt)","sms":{"template":"default_otp","language":"en-US"}}}
        """
    }

    /// The `callout` block carries the announcement language the server settled on.
    static func startCallout(id: String = "33333333-3333-3333-3333-333333333333",
                             destination: String = "+15551234567",
                             language: String = "pt-BR",
                             expiresAt: String = farFuture) -> String {
        """
        {"data":{"id":"\(id)","destination":"\(destination)","delivery_method":"callout",\
        "status":"pending","expires_at":"\(expiresAt)","callout":{"language":"\(language)"}}}
        """
    }

    static func verifiedCallout(language: String = "pt-BR", fee: String = "0.05") -> String {
        """
        {"data":{"id":"33333333-3333-3333-3333-333333333333","destination":"+15551234567",\
        "delivery_method":"callout","fee":"\(fee)","status":"verified","expires_at":"\(farFuture)",\
        "callout":{"language":"\(language)"}}}
        """
    }

    static func verifiedSMS(fee: String = "0.05") -> String {
        """
        {"data":{"id":"11111111-1111-1111-1111-111111111111","destination":"+15551234567",\
        "delivery_method":"sms","fee":"\(fee)","status":"verified","expires_at":"\(farFuture)",\
        "sms":{"template":"default_otp","language":"en-US"}}}
        """
    }

    /// `fee` as a bare JSON number (the alternative wire form to a quoted string).
    static func verifiedSMSNumberFee(fee: String = "0.06") -> String {
        """
        {"data":{"id":"11111111-1111-1111-1111-111111111111","destination":"+15551234567",\
        "delivery_method":"sms","fee":\(fee),"status":"verified","expires_at":"\(farFuture)",\
        "sms":{"template":"default_otp","language":"en-US"}}}
        """
    }

    static func failedTooManyAttempts() -> String {
        """
        {"data":{"id":"11111111-1111-1111-1111-111111111111","destination":"+15551234567",\
        "delivery_method":"sms","status":"failed","error_code":"too_many_attempts",\
        "error_detail":"too many attempts",\
        "expires_at":"\(farFuture)","sms":{"template":"default_otp","language":"en-US"}}}
        """
    }

    static func failedSuperseded() -> String {
        """
        {"data":{"id":"11111111-1111-1111-1111-111111111111","destination":"+15551234567",\
        "delivery_method":"sms","status":"failed","error_code":"superseded",\
        "error_detail":"superseded",\
        "expires_at":"\(farFuture)","sms":{"template":"default_otp","language":"en-US"}}}
        """
    }

    /// A denied verification carrying one of the three denial slugs.
    static func deniedVerification(errorCode: String, errorDetail: String) -> String {
        """
        {"data":{"id":"11111111-1111-1111-1111-111111111111","destination":"+15551234567",\
        "delivery_method":"sms","status":"denied","error_code":"\(errorCode)",\
        "error_detail":"\(errorDetail)",\
        "expires_at":"\(farFuture)","sms":{"template":"default_otp","language":"en-US"}}}
        """
    }

    static func statusWithRawStatus(_ status: String) -> String {
        """
        {"data":{"id":"11111111-1111-1111-1111-111111111111","destination":"+15551234567",\
        "delivery_method":"sms","status":"\(status)","expires_at":"\(farFuture)",\
        "sms":{"template":"default_otp","language":"en-US"}}}
        """
    }

    /// The error envelope shape: `{"errors":[{"code":<slug>,"detail":<text>}]}`.
    static func errorBody(_ items: [(code: String, detail: String)]) -> String {
        let joined = items
            .map { "{\"code\":\"\($0.code)\",\"detail\":\"\($0.detail)\"}" }
            .joined(separator: ",")
        return "{\"errors\":[\(joined)]}"
    }

    /// A raw error-envelope body, verbatim — for malformed/code-less element tests where the exact
    /// (possibly invalid) JSON matters.
    static func rawErrorBody(_ elementsJSON: String) -> String {
        "{\"errors\":[\(elementsJSON)]}"
    }
}
