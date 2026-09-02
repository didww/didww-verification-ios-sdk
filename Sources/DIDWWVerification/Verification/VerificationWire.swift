import Foundation

// Wire models: request bodies, the response DTO, and the DTO → domain mapping.

// MARK: - Request bodies
// Custom `encode` with `encodeIfPresent` so `nil` fields are OMITTED rather than sent as JSON null —
// the server distinguishes absent from present.

/// Per-channel options travel in a block named after the channel they belong to:
/// `{"destination":…,"delivery_method":"callout","callout":{"languages":[…]}}`. Each block is keyed
/// by its own channel, never by `deliveryMethod`: the server reads only the block matching the
/// method and silently drops the rest, including a top-level `languages`.
///
/// The blocks encode themselves, so this type names no channel and no key.
struct StartRequestData: Encodable {
    let destination: String
    let deliveryMethod: String
    /// Already checked against `deliveryMethod` by the caller.
    let channelOptions: [any ChannelOptionsBlock]

    /// Spelled at runtime — the block's key comes from the block itself.
    private struct WireKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ stringValue: String) { self.stringValue = stringValue }
        init?(stringValue: String) { self.init(stringValue) }
        init?(intValue: Int) { nil }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: WireKey.self)
        try c.encode(destination, forKey: WireKey("destination"))
        try c.encode(deliveryMethod, forKey: WireKey("delivery_method"))
        // Omitted when empty — the server distinguishes absent from present.
        for block in channelOptions where !block.isEmpty {
            let key = WireKey(type(of: block).channel.wireValue)
            try block.encodeBlock(to: c.superEncoder(forKey: key))
        }
    }
}

struct SubmitRequestData: Encodable {
    let deliveryMethod: String
    let code: String

    enum CodingKeys: String, CodingKey {
        case deliveryMethod = "delivery_method"
        case code
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(deliveryMethod, forKey: .deliveryMethod)
        try c.encode(code, forKey: .code)
    }
}

// MARK: - Response body

struct VerificationDTO: Decodable {
    let id: String
    let destination: String
    let deliveryMethod: String
    let fee: FlexibleDecimal?
    let status: String
    let errorCode: String?
    let errorDetail: String?
    let expiresAt: String?
    // Only the block matching `delivery_method` is emitted, so at most one is present, and a
    // channel this SDK doesn't model returns none it can read.
    let sms: SMSInfo?
    let callout: CalloutInfo?

    enum CodingKeys: String, CodingKey {
        case id
        case destination
        case deliveryMethod = "delivery_method"
        case fee
        case status
        case errorCode = "error_code"
        case errorDetail = "error_detail"
        case expiresAt = "expires_at"
        case sms
        case callout
    }
}

struct SMSInfo: Decodable {
    let template: String?
    let language: String?
}

struct CalloutInfo: Decodable {
    let language: String?
}

// MARK: - DTO → domain mapping

extension VerificationDTO {
    func toVerification() throws -> Verification {
        // `expires_at` is `NOT NULL` in the database and is assigned unconditionally at creation —
        // including for a verification denied at creation, which differs only in `finished_at`.
        // Its absence is therefore a genuinely malformed response, not a shape to tolerate.
        guard let raw = expiresAt, let parsed = WireDate.parse(raw) else {
            throw APIError.unexpectedResponse("missing or invalid expires_at on start")
        }
        return Verification(
            id: id,
            destination: destination,
            deliveryMethod: DeliveryMethod(wireValue: deliveryMethod),
            expiresAt: parsed,
            // `start` returns the same payload as status, so carry the outcome through: a denial
            // arrives as a 201 with status=denied, and dropping it would hide that behind a handle
            // that looks freshly pending.
            status: Verification.Status(wireValue: status),
            errorCode: errorCode,
            errorDetail: errorDetail,
            fee: fee?.value,
            details: details
        )
    }

    func toResult() -> VerificationResult {
        VerificationResult(
            id: id,
            destination: destination,
            deliveryMethod: DeliveryMethod(wireValue: deliveryMethod),
            fee: fee?.value,
            status: Verification.Status(wireValue: status),
            // One slug feeds both the typed `reason` and the raw carriers.
            reason: errorCode.map(Verification.Reason.init(wireValue:)),
            errorCode: errorCode,
            errorDetail: errorDetail,
            expiresAt: expiresAt.flatMap(WireDate.parse),
            details: details
        )
    }

    /// The one block the server emitted, mapped to its domain case. Keys stay optional even where
    /// the API marks them required — a block short of a key still yields the rest.
    private var details: Verification.Details? {
        if let sms { return .sms(.init(template: sms.template, language: sms.language)) }
        if let callout { return .callout(.init(language: callout.language)) }
        return nil
    }
}
