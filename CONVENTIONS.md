# SDK structural conventions

How this package is organized, and the rules a **second resource** must follow so it drops in without
renaming or moving anything that already exists. These are conventions, not compiler-enforced
boundaries — SPM compiles the whole target as one module.

## Layout

```
Sources/DIDWWVerification/
  Core/          # SDK-wide, resource-agnostic. Reused verbatim by every resource.
  <Feature>/     # one folder per resource/feature (e.g. Verification/)
```

- **`Core/`** holds anything not tied to one resource: the transport seam (`Transport`,
  `URLSessionTransport`), `RequestFactory`, the generic `ResponseDecoder.decode<T>`, the shared wire
  primitives (`RequestEnvelope`/`ResponseEnvelope`, `FlexibleDecimal`, `WireDate`, `APIErrorBody`),
  `VerifyEnvironment`, `AuthorizationMethod`, `Configuration`, `VerificationLogger`, and the SDK-wide
  **`APIError`**.
- **`<Feature>/`** holds one resource's delivery surface: its public API on the client, its handle
  and result types, its domain enums, its wire DTOs + DTO→domain mapping, and any feature-specific
  client-side guard error.

## Errors — two flat types, never a wrapper

- **`APIError` (Core)** is every HTTP/transport failure. A new resource reuses it as-is; do **not**
  add a per-resource network error type.
- **A feature error** (e.g. `VerificationError`) holds only *client-side guards the SDK raises
  itself* — preconditions checked before/independent of the network. Keep it to real cases; if a
  feature has none, it has no error type.
- Callers catch two flat types (`catch let e as APIError` / `catch let e as VerificationError`).
  Never nest one inside the other, and never use typed `throws(...)` on public API — it pins the
  thrown type into the contract and makes broadening it source-breaking.

## Domain enums — nest on the owning type, fail open

- Nest a resource's vocabulary on its primary type: `Verification.Status`, `Verification.Reason`,
  `Verification.Details` (like `URLSession.Configuration`). This keeps names local and lets a second
  resource bring its own `Foo.Status` with no collision.
- **Never** nest a type named `Result` or `Error` — they shadow `Swift.Result` / `Swift.Error`. Keep
  those flat and prefixed (`VerificationResult`, `VerificationError`).
- **Fail open on every value the backend emits** — status, reason and delivery method alike:
  include an `.other(String)` case from day one so a new server value decodes instead of throwing.
  Adding an enum case post-1.0 is source-breaking; `.other` is the escape hatch. Nothing we decode is
  really "a value we control": the server can add a channel at any time, and an installed copy of the
  SDK cannot be updated in step. Strictness belongs on the request side, where the caller picks from
  the modelled cases and the server validates what we send.
- Method-keyed payloads (`Verification.Details`) still have **no** `.other`, for a plainer reason
  than fail-closed decoding used to give: the SDK only decodes the blocks it models, so an unmodelled
  channel's block is never decoded at all and `details` is simply `nil` — there is nothing an
  `.other` case could carry. Seed the known cases up front so future keys are additive struct fields,
  not breaking new enum cases.

## Per-channel options — one type per channel, self-encoding

Request options that apply to a single delivery method live in their own public struct
(`SMSOptions`, `CalloutOptions`), take their own `start` parameter named after the channel, and
travel as a JSON block of that same name.

- Each block conforms to the internal `ChannelOptionsBlock` and **encodes itself**. The wire layer
  spells no channel name and no key, so a channel gaining a key is a change to
  `ChannelOptions.swift` alone. A channel gaining its *first* option adds a type there **plus** a
  `start` parameter and a slot in that method's options list; the wire layer still doesn't change.
- The protocol deliberately does **not** refine `Encodable`: a public type conforming to it has to
  make `encode(to:)` public, which would freeze the request JSON into the public API.
- `isEmpty` decides omission — an all-`nil` block is left out rather than sent as `{}`, because the
  server distinguishes absent from present.
- Options for a channel other than `method:` are rejected client-side
  (`VerificationError.channelMismatch`). The server silently drops a non-matching block and still
  answers `201`, so this guard is the only place the mistake can surface.

## Deliberately NOT done (revisit only when a real second resource proves the need)

- No caseless-enum namespace shells (`enum Verification {}` with the handle renamed away).
- No `client.<feature>.method(...)` sub-clients — the flat facade is clearer at this size.
- No separate SPM target per feature.
- No folder-per-delivery-method — our channels are one enum parameter, not subclasses.
