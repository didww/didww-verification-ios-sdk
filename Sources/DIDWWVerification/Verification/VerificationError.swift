import Foundation

/// Usage guards the SDK raises itself, before any network call. Anything coming back from the API
/// is an ``APIError`` instead, so callers catch two flat types.
public enum VerificationError: Error, Sendable, Equatable {
    /// Options were passed for a channel other than the one being started — the server reads only
    /// the block matching `delivery_method` and silently drops the rest, so this guard is the only
    /// signal. `expected` echoes the `method:` you passed to `start`.
    case channelMismatch(expected: DeliveryMethod)
    /// A by-number call was given a string with no digits in it.
    case invalidNumber
}
