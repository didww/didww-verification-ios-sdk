# Changelog

Notable changes to `DIDWWVerification`. Versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html): from 1.0.0 onwards a breaking change to
the public surface requires a major version.

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
