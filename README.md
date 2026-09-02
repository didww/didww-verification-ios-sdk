# DIDWWVerification

A lean, dependency-free Swift SDK for the [DIDWW](https://didww.com) phone-number verification API.
It wraps three endpoints (start / status / submit) over two channels (SMS, callout) with a modern
`async/await` surface, typed models, and a closed, catchable error taxonomy.

- **Zero third-party runtime dependencies** — `URLSession` + `Codable` only.
- **iOS 13+**, `async/await` throughout (back-deployed — see *Requirements*).
- Swift Package Manager, or CocoaPods from a git source.

## Requirements

- **Runtime:** iOS 13.0+ (or macOS 10.15+ for the CLI and tests).
- **Build toolchain:** Swift 6.1 / Xcode 16.3+. This is the floor for *building* the package, not
  for running it — the library it produces deploys to iOS 13.
- **Concurrency:** `async/await` back-deploys to iOS 13, but `URLSession.data(for:)` is iOS 15+, so
  the SDK bridges the completion-handler API internally and wires `Task` cancellation through it.
  Nothing about that is visible in the public surface.

## Installation

### Swift Package Manager

In Xcode: **File → Add Package Dependencies…** and enter the repository URL. Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/didww/didww-verification-ios-sdk.git", from: "1.0.0")
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "DIDWWVerification", package: "didww-verification-ios-sdk")
    ])
]
```

### CocoaPods

Add the pod from git, pinned to a release tag, in your `Podfile`:

```ruby
pod 'DIDWWVerification', :git => 'https://github.com/didww/didww-verification-ios-sdk.git', :tag => '1.0.0'
```

## Quick start

```swift
import DIDWWVerification

let client = VerificationClient(
    environment: .production,                               // .production, .sandbox, or .custom(url)
    auth: .basic(appKey: "your-app-key", secret: "your-secret"),
    configuration: .init(timeout: 30)                       // logger: nil (off) by default
)

// 1. Start — dispatch a code over a channel.
let verification = try await client.start(
    destination: "+15551234567",
    method: .sms,                       // .sms or .callout
    sms: .init(languages: ["en-US"])    // optional, see Per-method options
)                                       // .callout takes `callout: .init(languages:)`

// 1b. A start can arrive already settled — check before asking the user for a code.
guard verification.status == .pending else {
    print("start settled immediately: \(verification.status) / \(verification.errorCode ?? "-")")
    return
}

// 2. Submit — the code the user received.
let result = try await client.verify(verification, code: "123456")

// 3. (Optional) Poll status at any time.
let current = try await client.status(verification)

switch result.status {
case .verified:              print("verified 🎉")
case .failed, .denied:       print("nope: \(String(describing: result.reason))")
case .expired:               print("expired")
case .pending:               print("still pending")
case .other(let raw):        print("new server status: \(raw)")   // forward-compatible
}
```

### Per-method options

Options that apply to one delivery method only go in a parameter named after that method, and travel
as a block of the same name:

```swift
try await client.start(
    destination: "+4915112345678",
    method: .sms,
    sms: .init(languages: ["de-DE"])
)
```

```json
{ "data": { "destination": "+4915112345678", "delivery_method": "sms",
            "sms": { "languages": ["de-DE"] } } }
```

`sms:` and `callout:` are the parameters today — one per channel. The server reads only the block
matching `delivery_method` and silently ignores the rest, so passing options alongside a different
`method:` throws `VerificationError.channelMismatch` before any network call rather than letting the
request come back as a healthy `201` with the defaults applied.

### Languages

Both channels that carry content take a `languages` list — the template an SMS is written in, and
the recording a callout announces the code in:

```swift
let verification = try await client.start(
    destination: "+5511999999999",
    method: .callout,
    callout: .init(languages: ["pt-BR", "pt-PT"])
)
```

```json
{ "data": { "destination": "+5511999999999", "delivery_method": "callout",
            "callout": { "languages": ["pt-BR", "pt-PT"] } } }
```

The tags and the rules are identical on both channels, so a single list can serve either one:

- **BCP-47 tags, most preferred first** — the first tag the server has content for wins.
- **Matched exactly, so the region subtag is required.** `"pt"` does not match the `pt-PT` recording,
  and `"pl"` does not match the `pl-PL` template.
- **Unmatched tags fall back to `en-US` rather than failing.** A tag the channel has no content for
  is accepted; only a malformed tag is rejected, as `APIErrorCode.languagesInvalid`. That makes it
  safe to pass a device's preferred languages straight through.
- **What the server settled on comes back in the channel block**, on the `start` handle and on every
  later result — so a fallback is something you can detect rather than assume:

```swift
if case .callout(let callout) = verification.details, callout.language != "pt-BR" {
    // announced in callout.language, not in the language that was asked for
}
```

The two catalogues overlap but are not identical, which is the usual reason a fallback happens:

| | Tags |
|---|---|
| **SMS templates** | `bg-BG` `bs-BA` `cs-CZ` `da-DK` `de-DE` `el-GR` `en-GB` `en-US` `es-419` `es-ES` `et-EE` `fi-FI` `fr-FR` `he-IL` `hr-HR` `hu-HU` `is-IS` `it-IT` `ja-JP` `ka-GE` `lt-LT` `lv-LV` `mk-MK` `ms-MY` `mt-MT` `nb-NO` `nl-NL` `pl-PL` `pt-BR` `pt-PT` `ro-RO` `ru-RU` `sk-SK` `sl-SI` `sq-AL` `sr-RS` `sv-SE` `th-TH` `uk-UA` `zh-CN` `zh-HK` |
| **Callout recordings** | `af-ZA` `ar-AE` `ar-EG` `ar-SA` `bg-BG` `bs-BA` `cs-CZ` `da-DK` `de-DE` `el-GR` `en-GB` `en-US` `es-419` `es-ES` `et-EE` `fi-FI` `fr-FR` `he-IL` `hi-IN` `hr-HR` `hu-HU` `id-ID` `is-IS` `it-IT` `ja-JP` `lt-LT` `lv-LV` `mk-MK` `ms-MY` `nb-NO` `nl-NL` `pl-PL` `pt-BR` `pt-PT` `ro-RO` `sk-SK` `sl-SI` `sr-RS` `sv-SE` `sw-KE` `th-TH` `tl-PH` `tr-CY` `tr-TR` `uk-UA` `ur-PK` `vi-VN` `zh-CN` `zh-HK` |

`ka-GE`, `mt-MT`, `ru-RU` and `sq-AL` have a template but no recording, so a callout in one of them
is announced in `en-US`. A few callout tags are served by an approximate recording rather than a
dedicated one: `en-GB` is the US-accented English recording, `es-419` one informal-register Spanish
recording, the three `ar-*` tags Modern Standard Arabic rather than a regional dialect, and `tr-CY`
standard Turkish. The API reference is authoritative if these lists drift.

### Environments

The environment is chosen at construction and **defaults to `.production`** — as an explicit
parameter default visible in the signature, not a silent fallback, so reaching a non-production host
is always a deliberate choice. The SDK appends `/api/v1` to the resolved host.

| Environment | Host |
|---|---|
| `.production` | `https://verification.didww.com` |
| `.sandbox` | `https://verification-sandbox.didww.com` |
| `.custom(URL)` | any scheme + host — a local backend, a proxy, or tests |

```swift
let client = VerificationClient(environment: .sandbox, auth: .basic(appKey: "…", secret: "…"))
```

### Authentication

The API ranks three auth modes. This SDK implements the two usable from a device:

| Mode | Header | Here | Use |
|---|---|---|---|
| `public` | `Application <appKey>` | `.public(appKey:)` | Production, on-device (see below) |
| `basic` | `Basic base64(appKey:secret)` | `.basic(appKey:secret:)` | Development |
| `application` | `Application <appKey>:<signature>` + `x-timestamp` | — | Server-to-server, not implemented |

The header token is `Application` for two of them, so these are named for the mode.

> **`public` requires a `callback_url` on your application.** By design, not as a limitation:
> an app key is copyable out of any binary, so the server calls *your* callback to authorize each
> start. With no `callback_url` configured, a start is **not** rejected at the HTTP level — it comes
> back `201` with `status: .denied` and `errorCode: "denied_missing_callback_url"`. Branch on
> `verification.status` (see *Start can come back denied*). For local development without a
> callback, use `.basic`. The signed `application` mode needs a secret on-device and is
> intentionally not implemented.

> ⚠️ **Leave your application's minimum auth mode at `public`.** It is set from your DIDWW
> account, and raising it rejects every call this SDK makes — `basic` would ship a secret in your
> binary, and `application` is unavailable.

### Error handling

Failures are typed — branch on the case, never on a message string. There are **two** flat error
types (like `URLError` vs `DecodingError`): `APIError` for anything the network/API surfaces, and
`VerificationError` for a client-side usage guard the SDK raises before the call goes out. Under
`async`/`await` both land in the same `do`, so you just add a `catch` per type — no wrapper, no
unwrapping.

The message-carrying cases (`invalidParameters`, `validationFailed`, `unexpectedStatus`) carry an
array of **`APIErrorItem`** — the server's `{"errors":[{"code":…,"detail":…}]}` envelope:

- `item.code` — the raw slug string, **always present** (e.g. `"destination_blank"`).
- `item.detail` — human-readable static text. Display it; never branch on it.
- `item.known` — the typed `APIErrorCode` when this SDK version recognizes the slug, else `nil`.

`APIErrorCode` is a `String`-raw-valued enum of every known slug and has **no `.other` case**.
It's **fail-open by construction**: an unknown/future slug simply makes `item.known == nil` while
`item.code` still carries the raw truth — decoding never fails and no slug is ever lost. Branch on
`code`/`known`, still never on `detail`.

```swift
do {
    _ = try await client.verify(verification, code: code)
} catch APIError.validationFailed(let items) {
    // 422 — e.g. wrong code. Each item carries a raw slug + typed `.known`.
    for item in items {
        switch item.known {
        case .codeInvalid:       print("wrong code")
        case .destinationBlank:  print("no destination")
        case nil:                print("unmodeled slug: \(item.code) — \(item.detail)")
        default:                 print("\(item.code): \(item.detail)")
        }
    }
} catch APIError.unauthorized {
    // 401
} catch APIError.insufficientBalance {
    // 402
} catch APIError.transport(let urlError) {
    // offline / timeout / TLS
} catch VerificationError.channelMismatch(let expected) {
    // you passed `sms:` or `callout:` options for a channel other than `method:`.
    // Thrown before any network call — matching the block to `method:` prevents it.
} catch VerificationError.invalidNumber {
    // the by-number `number:` argument had no digits in it at all.
    // Thrown before any network call, on status(number:) and verify(number:code:method:).
} catch is CancellationError {
    // the awaiting Task was cancelled
}
```

### Start can come back denied

`start()` returning normally does **not** mean a code was dispatched. The server runs the
application's request callback *before* dispatching, and a denial — the callback said no, returned
something unparseable, timed out, or the application has no `callback_url` at all — is an ordinary
`201 Created` whose body carries the outcome. Nothing throws, because nothing failed at the HTTP
level.

The returned ``Verification`` therefore carries the server's creation-time snapshot: `status`,
`errorCode`, `errorDetail`, `reason`, and `fee`. It is a snapshot, never updated — call
`status(_:)` for the live state.

> `fee` is the **verification fee**, and a quote rather than a charge: it is billed only when a
> verification reaches `.verified`, though every outcome reports the same figure. It is not the
> total cost either — delivering the SMS or call is billed separately as ordinary DIDWW traffic.

```swift
let verification = try await client.start(destination: number, method: .sms)

switch verification.status {
case .pending:
    presentCodeEntry(for: verification)          // the normal path
case .denied:
    // Public auth: your callback declined, or the application has no callback_url.
    show(verification.errorDetail ?? "verification denied")
default:
    show("unexpected start status: \(verification.status)")
}
```

This matters most with `.public` auth, where a denial is a routine outcome rather than an edge
case.

### Reading the delivery-method block

`details` carries the server's method-specific block, keyed by channel — on the `Verification`
returned by `start` and on every `VerificationResult`. The `sms` channel returns the `template` and
the `language` it was rendered in; `callout` returns the `language` it is announced in.

```swift
switch result.details {
case .sms(let sms):         print(sms.template ?? "-", sms.language ?? "-")
case .callout(let callout): print(callout.language ?? "-")
case nil:                   break
}
```

A block for a channel this SDK version doesn't model isn't decoded at all, so `details` is simply
`nil` — there is no `.other` case to handle. New keys on a channel it does model arrive as new
properties on that block, never as a new enum case.

### Cancellation & timeout

Wrap a call in a `Task` and `cancel()` it — the in-flight request is cancelled and the call throws
`CancellationError`. Per-request timeout is set via `Configuration(timeout:)`.

### Debug logging (opt-in, redacting)

Logging is **off** by default. Provide a `VerificationLogger` to turn it on; the SDK redacts OTP
codes and phone numbers before anything reaches your logger.

```swift
struct ConsoleLogger: VerificationLogger { func log(_ m: String) { print(m) } }
let client = VerificationClient(environment: .production, auth: auth,
                               configuration: .init(logger: ConsoleLogger()))
```

## Verify by phone number

Alongside the handle-based flow above, the same start → submit → status flow is available
addressed by the destination number directly — useful when you'd rather not retain the
`Verification` handle across app restarts:

```swift
// 1. Start (unchanged) — dispatch a code over a channel.
let verification = try await client.start(destination: "+15551234567", method: .sms)

// 2. Submit, addressing by number instead of the handle.
let result = try await client.verify(number: "+15551234567", code: "123456", method: .sms)

// 3. Poll status by number.
let current = try await client.status(number: "+15551234567")
```

Both accept the number in any format and normalize it client-side to digits-only before it
goes on the wire — `"+1 (555) 123-4567"` and `"15551234567"` hit the identical endpoint. A number
with no digits at all throws `VerificationError.invalidNumber` before any network call.

There is no call that recovers a handle for an already-active verification, so retain the
`Verification` returned by `start` if you need by-id access after a relaunch.

### Single-active invariant

The backend allows at most one non-finished verification per app + number. Calling `start` again
for a number that already has one **supersedes** it: the previously active verification is
immediately failed with `Verification.Reason.superseded`, and the new one becomes the verification
that by-number calls resolve. You'll only ever observe `.superseded` through the original handle's by-id
`status(_:)` — a by-number call always resolves the newest verification, never the one it replaced.

### Sharp edges

- **By-number resolves the newest verification for the number** — the active one when one
  exists, else the most recent finished one. `status(number:)` therefore keeps returning the
  outcome (`.verified` / `.failed` / `.denied` / `.expired`) after the verification finishes,
  so a server can poll by number without retaining the handle. A by-number call 404s only when
  no verification exists for the number at all. Note a newer `start` changes which verification
  by-number resolves — after that, the previous attempt's outcome is only reachable via its
  retained handle.
- **A wrong `method:` looks identical to a wrong code.** `verify(number:code:method:)` sends
  `method` as the delivery method of the *existing* active verification — get it wrong (e.g. pass
  `.sms` for a number actually started with `.callout`) and the server rejects it with the same
  `APIError.validationFailed` (422) as a wrong code. There's no separate error case for it — "wrong
  method" and "wrong code" are not programmatically distinguishable.

## Building from source

```bash
swift build      # compile the library + sample
swift test       # run the unit suite (no network — a mock transport is injected)
swift run SampleCLI   # macOS demo of the full SMS flow (needs a live backend + credentials)
```

`pod lib lint` and any iOS-targeted build need a full Xcode install rather than the Command Line
Tools alone.

## Support

Questions about the verification API or your DIDWW account: [support@didww.com](mailto:support@didww.com).
Bugs and feature requests for this SDK: open an issue on this repository.

## License

MIT — see [LICENSE](LICENSE).
