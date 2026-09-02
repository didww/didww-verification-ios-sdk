import Foundation

/// How the one-time code is delivered.
///
/// `.other(String)` is a decode-only case: you pick a modelled channel to start a verification, and
/// `.other` only ever reaches you on a response, carrying a channel the server offers but this SDK
/// version doesn't model.
public enum DeliveryMethod: Sendable, Hashable {
    /// SMS text message; the user submits the received `code`.
    case sms
    /// An automated voice call reading out a `code`.
    case callout
    /// A channel this SDK version doesn't know about. Carries the raw wire string.
    case other(String)
}

extension DeliveryMethod: CaseIterable {
    /// The channels you can start a verification with — what a picker wants. `.other` is decode-only
    /// and unbounded, so it isn't enumerable and isn't listed here.
    public static var allCases: [DeliveryMethod] { [.sms, .callout] }
}

extension DeliveryMethod {
    /// The exact string the API expects/returns.
    var wireValue: String {
        switch self {
        case .sms: return "sms"
        case .callout: return "callout"
        case .other(let raw): return raw
        }
    }

    /// Fail-open like `Status`/`Reason`: an unrecognized method keeps its raw string instead of
    /// failing the whole response, so a channel this SDK doesn't model can't break an
    /// already-installed copy. Strictness stays on the request side, where the server validates what
    /// we send.
    init(wireValue: String) {
        switch wireValue {
        case "sms": self = .sms
        case "callout": self = .callout
        default: self = .other(wireValue)
        }
    }
}
