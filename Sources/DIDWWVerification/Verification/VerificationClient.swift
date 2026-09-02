import Foundation

/// The DIDWW phone-verification client.
///
/// Usage:
/// ```swift
/// let client = VerificationClient(
///     environment: .production,
///     auth: .basic(appKey: "…", secret: "…")
/// )
/// let v = try await client.start(destination: "+15551234567", method: .sms)
/// let result = try await client.verify(v, code: "123456")
/// ```
public struct VerificationClient: Sendable {
    private let factory: RequestFactory
    private let transport: any Transport
    private let logger: (any VerificationLogger)?

    /// Create a client targeting a ``VerifyEnvironment``. Defaults to `.production`; pass `.sandbox`
    /// for testing or `.custom(url)` for another host.
    public init(environment: VerifyEnvironment = .production, auth: AuthorizationMethod, configuration: Configuration = .init()) {
        self.init(environment: environment, auth: auth, configuration: configuration, transport: URLSessionTransport())
    }

    /// Test-only: resolves the environment to its base URL and injects a transport.
    init(environment: VerifyEnvironment, auth: AuthorizationMethod, configuration: Configuration = .init(), transport: any Transport) {
        self.init(baseURL: environment.baseURL, auth: auth, configuration: configuration, transport: transport)
    }

    /// Test-only designated init: injects the transport, bypassing the network.
    init(baseURL: URL, auth: AuthorizationMethod, configuration: Configuration = .init(), transport: any Transport) {
        self.factory = RequestFactory(baseURL: baseURL, auth: auth, timeout: configuration.timeout)
        self.transport = transport
        self.logger = configuration.logger
    }

    // MARK: - Public API

    /// Start a verification: dispatch a code over `method` to `destination`.
    /// `POST /api/v1/verifications`. Returns a handle to use with `verify`/`status`.
    ///
    /// ⚠️ Check `.status` on the returned handle — a start can come back already `.denied` as a
    /// `201`, without throwing. See ``Verification/status``.
    ///
    /// Options that apply to one channel only go in the parameter named after it: `sms:` and
    /// `callout:`. Passing options for a channel other than `method` throws
    /// ``VerificationError/channelMismatch(expected:)`` — the server would otherwise drop them and
    /// answer `201` with its defaults.
    public func start(destination: String, method: DeliveryMethod,
                      sms: SMSOptions? = nil, callout: CalloutOptions? = nil) async throws -> Verification {
        // One slot per channel with options. Guarded on presence, not content: the server drops a
        // non-matching block and answers 201 either way, so this is the only signal.
        let supplied: [(any ChannelOptionsBlock)?] = [sms, callout]
        let channelOptions = supplied.compactMap { $0 }
        guard channelOptions.allSatisfy({ type(of: $0).channel == method }) else {
            throw VerificationError.channelMismatch(expected: method)
        }
        let body = RequestEnvelope(
            data: StartRequestData(destination: destination, deliveryMethod: method.wireValue,
                                   channelOptions: channelOptions)
        )
        let request = try factory.request(method: "POST", path: ["verifications"], jsonBody: body)
        let dto: VerificationDTO = try await perform(request)
        return try dto.toVerification()
    }

    /// Submit the `code` the user received. `PUT /api/v1/verifications/{id}`.
    ///
    /// Every channel this SDK models is submitted with a `code`, so there is nothing to guard
    /// client-side; a channel it doesn't model (`.other`) is let through too — only the server can
    /// say what it takes.
    public func verify(_ verification: Verification, code: String) async throws -> VerificationResult {
        try await submit(path: ["verifications", verification.id],
                         deliveryMethod: verification.deliveryMethod, code: code)
    }

    /// Fetch the current state of a verification. `GET /api/v1/verifications/{id}`.
    public func status(_ verification: Verification) async throws -> VerificationResult {
        let request = factory.request(method: "GET", path: ["verifications", verification.id])
        let dto: VerificationDTO = try await perform(request)
        return dto.toResult()
    }

    // MARK: - Public API (by number)
    // Address a verification without holding a handle. The server keeps at most one unfinished
    // verification per number, so these resolve the active one when it exists, else the most recent
    // finished one. `number` is reduced to its digits, so formatting doesn't matter; both throw
    // `VerificationError.invalidNumber` before any network call when there are no digits.

    /// Fetch the current state of the newest verification for `number`, finished ones included.
    /// `GET /api/v1/verifications/by_number/{digits}`. 404s only when the number has no
    /// verification at all.
    public func status(number: String) async throws -> VerificationResult {
        let request = factory.request(method: "GET", path: try byNumberPath(number))
        let dto: VerificationDTO = try await perform(request)
        return dto.toResult()
    }

    /// Submit a `code` for the newest verification on `number`.
    /// `PUT /api/v1/verifications/by_number/{digits}`.
    ///
    /// `method` must name the channel the verification was started with — with no handle the SDK
    /// can't know it. A wrong `.sms`-vs-`.callout` choice is only detectable server-side and comes
    /// back as `APIError.validationFailed`.
    public func verify(number: String, code: String, method: DeliveryMethod) async throws -> VerificationResult {
        try await submit(path: try byNumberPath(number), deliveryMethod: method, code: code)
    }

    // MARK: - Internals

    private func byNumberPath(_ number: String) throws -> [String] {
        let digits = PhoneNumberNormalizer.normalize(number)
        guard !digits.isEmpty else { throw VerificationError.invalidNumber }
        return ["verifications", "by_number", digits]
    }

    private func submit(path: [String], deliveryMethod: DeliveryMethod,
                        code: String) async throws -> VerificationResult {
        let body = RequestEnvelope(
            data: SubmitRequestData(deliveryMethod: deliveryMethod.wireValue, code: code)
        )
        let request = try factory.request(method: "PUT", path: path, jsonBody: body)
        let dto: VerificationDTO = try await perform(request)
        return dto.toResult()
    }

    /// Send a request and decode its `data`-wrapped payload as `T`, or throw a typed ``APIError``.
    private func perform<T: Decodable>(_ request: URLRequest, successCodes: Set<Int> = [200, 201]) async throws -> T {
        // Method/URL/status only — never bodies, so codes and phone numbers stay out of logs. The
        // Redactor is defense-in-depth for the by-number paths, whose URLs do carry a number.
        log("→ \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "?")")
        let response = try await transport.send(request)
        log("← \(response.statusCode)")
        return try ResponseDecoder.decode(response, successCodes: successCodes)
    }

    private func log(_ message: String) {
        guard let logger else { return }
        logger.log(Redactor.redact(message))
    }
}
