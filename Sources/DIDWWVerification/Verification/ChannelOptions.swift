import Foundation

// Options that apply to one delivery method only. Each channel gets its own type and its own
// `start` parameter, since the server reads only the block matching `delivery_method` and drops the
// rest. Each block encodes itself, so a new key stays in this file; a new channel adds a type here
// plus a `start` parameter.

/// A per-channel option block, keyed on the wire by the channel it belongs to.
///
/// Not `Encodable`: a public type conforming to it has to make `encode(to:)` public, which would
/// freeze the request JSON into the public API.
protocol ChannelOptionsBlock: Sendable {
    /// The channel these options belong to, and the JSON key the block travels under.
    static var channel: DeliveryMethod { get }
    /// Nothing to send — an all-`nil` block is omitted rather than sent empty.
    var isEmpty: Bool { get }
    /// Write this block's keys into `encoder`, already positioned at the block's own object.
    func encodeBlock(to encoder: Encoder) throws
}

/// Options for an `sms` verification, passed as `start(…, sms:)`.
public struct SMSOptions: Sendable, Equatable {
    /// Preferred message-template languages as BCP-47 tags, most preferred first. Matched exactly,
    /// so a region subtag is required (`"pl"` does not match `pl-PL`); unmatched tags fall back to
    /// `en-US`. The tag used comes back as ``Verification/Details/SMS/language``.
    public var languages: [String]?

    public init(languages: [String]? = nil) {
        self.languages = languages
    }
}

extension SMSOptions: ChannelOptionsBlock {
    static var channel: DeliveryMethod { .sms }

    var isEmpty: Bool { languages == nil }

    enum WireKey: String, CodingKey {
        case languages
    }

    // `encodeIfPresent` so a nil key is omitted rather than sent as JSON null — the server
    // distinguishes absent from present.
    func encodeBlock(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: WireKey.self)
        try c.encodeIfPresent(languages, forKey: .languages)
    }
}

/// Options for a `callout` verification, passed as `start(…, callout:)`.
public struct CalloutOptions: Sendable, Equatable {
    /// Preferred announcement languages as BCP-47 tags, most preferred first — the same tags and
    /// semantics as ``SMSOptions/languages``, so one list serves both channels. The tag used comes
    /// back as ``Verification/Details/Callout/language``.
    ///
    /// The catalogues differ, though: a tag with a template but no recording (or the reverse) is
    /// accepted and falls back to `en-US`. Only a malformed tag is rejected, so a device's preferred
    /// languages can be passed through verbatim.
    public var languages: [String]?

    public init(languages: [String]? = nil) {
        self.languages = languages
    }
}

extension CalloutOptions: ChannelOptionsBlock {
    static var channel: DeliveryMethod { .callout }

    var isEmpty: Bool { languages == nil }

    enum WireKey: String, CodingKey {
        case languages
    }

    func encodeBlock(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: WireKey.self)
        try c.encodeIfPresent(languages, forKey: .languages)
    }
}
