# Changelog

Notable changes to `DIDWWVerification`. Versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html): from 1.0.0 onwards a breaking change to
the public surface requires a major version.

## 1.1.0

Released — 2026-10.

- **`codeLength` on the delivery-method block.** `Verification.Details.SMS` and `.Callout` both gain
  a `codeLength: Int?` — the OTP code length the application is configured to send, 4–8, set per
  application.
- **`destination_in_cooldown` is a known `APIErrorCode`.** A `start` too soon after a non-denied one
  for the same app + destination now types via `item.known`; it still surfaces as
  `APIError.unexpectedStatus(code: 429, items:)` in this release — a dedicated `APIError` case is
  deferred to a future major version. Each `APIErrorItem` now also carries `retryAfter: TimeInterval?`,
  the server's `Retry-After` header as whole seconds, so a caller can back off for exactly as long as
  asked instead of guessing a fixed delay.
- **Redaction widened from a fixed 6-digit code to the server-chosen 4–8 digit range**, since the
  code length is now configurable per application. Canonical UUIDs (verification ids) pass through
  the logger intact instead of having a digit run inside them masked.
- **The verification's code lifetime is set per application** (60–600 s, default 300) rather than a
  fixed duration — always read `Verification.expiresAt`/`VerificationResult.expiresAt` instead of
  assuming a constant.
- Every request now carries a `User-Agent: didww-verification-ios/<version>` header.

## 1.0.0

First public release — 2026-09.

- **`VerificationClient`** — three endpoints (start / status / submit) over `async/await`, as five
  methods: `start(destination:method:sms:callout:)`, `verify(_:code:)`, `status(_:)`, and the
  by-number pair `status(number:)` and `verify(number:code:method:)`.
- **Two channels** — `.sms` and `.callout`, each with its own option block (`SMSOptions`,
  `CalloutOptions`) so the server reads only the block matching the delivery method. Both take
  `languages` as BCP-47 tags, most preferred first, matched exactly — a region subtag is required
  (`"pl"` does not match `pl-PL`) — with unmatched tags falling back to `en-US`.
- **`DeliveryMethod` is open.** A channel added after this release decodes as `.other(String)`
  rather than failing, so a new channel does not require an SDK upgrade to read.
- **Authorization** — `.public(appKey:)` and `.basic(appKey:secret:)`.
- **Environments** — `.production`, `.sandbox` and `.custom(URL)`.
- **A closed, catchable error taxonomy** — `VerificationError` and `APIError`, where
  `APIErrorCode` enumerates the slugs that arrive in an error envelope and `Verification.Reason`
  keys the outcome codes of a finished verification semantically rather than by slug.
- **Zero third-party runtime dependencies** — Foundation and `URLSession` only. iOS 13+, with
  `async/await` back-deployed.
- `Configuration` carries the request `timeout` (30s by default) and an optional
  `VerificationLogger`.
