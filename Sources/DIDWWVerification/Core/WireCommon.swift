import Foundation

// Shared wire primitives: the `data` envelope, the tolerant money/date decoders, and the error body.

// MARK: - Envelopes
// Every request body and response is wrapped in a top-level `data` key.

struct RequestEnvelope<T: Encodable>: Encodable {
    let data: T
}

struct ResponseEnvelope<T: Decodable>: Decodable {
    let data: T
}

// MARK: - Error body
// The server envelope is `{"errors":[{"code":<slug>,"detail":<text>}]}`, decoded per-element so one
// malformed element never sinks the whole body.

struct APIErrorItemWire: Decodable {
    let code: String            // REQUIRED — load-bearing; a code-less element is dropped
    let detail: String          // tolerant — default "" if missing
    enum CodingKeys: String, CodingKey { case code, detail }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code)                  // throws → element skipped
        detail = (try? c.decode(String.self, forKey: .detail)) ?? ""
    }
}

struct APIErrorBody: Decodable {
    let errors: [APIErrorItemWire]
    // Do NOT replace this with synthesized `[APIErrorItemWire]` decoding — that is all-or-nothing.
    // One element whose `init` throws aborts `Array.init(from:)`, the whole body throws, and
    // `mapError`'s `(try? …) ?? []` swallows it, silently losing every slug. Iterating the
    // unkeyed container and `try?`-ing each element skips only the bad one.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var arr = try c.nestedUnkeyedContainer(forKey: .errors)
        var acc: [APIErrorItemWire] = []
        while !arr.isAtEnd {
            if let item = try? arr.decode(APIErrorItemWire.self) {
                acc.append(item)
            } else {
                _ = try? arr.decode(AnyIgnored.self)   // consume & skip the malformed element
            }
        }
        errors = acc
    }
    enum CodingKeys: String, CodingKey { case errors }
    private struct AnyIgnored: Decodable {             // advances the container past one element
        init(from decoder: Decoder) throws {}          // explicit no-op: never requests a container, never throws
    }
}

// MARK: - Money
// `fee` may arrive as either a JSON string or a JSON number. Try the string first, else decode
// `Decimal` DIRECTLY from the number — never via `Double`, which reintroduces binary-float
// imprecision (0.06 → 0.06000000000000000021).
struct FlexibleDecimal: Decodable, Equatable {
    let value: Decimal

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self), let decimal = Decimal(string: string) {
            value = decimal
            return
        }
        if let decimal = try? container.decode(Decimal.self) {
            value = decimal
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "fee is neither a decimal string nor a number"
        )
    }
}

// MARK: - Date parsing
// The `JSONDecoder` default does NOT parse ISO8601 strings, and `.iso8601` rejects fractional
// seconds. Parse tolerantly: try with fractional seconds first, then without. Formatters are built
// per call to avoid shared-mutable-state concerns under strict concurrency.
enum WireDate {
    static func parse(_ string: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: string) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
