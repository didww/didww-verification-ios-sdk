// SampleCLI — a macOS command-line demo of the full DIDWW verification flow over SMS.
//
// Runnable with either a named environment or a custom host:
//   ENVIRONMENT=sandbox APP_KEY=… SECRET=… DESTINATION=+15551234567 swift run SampleCLI
//   BASE_URL=https://verify.example.com APP_KEY=… SECRET=… DESTINATION=+15551234567 swift run SampleCLI
//
// It uses Basic auth: a CLI is a trusted environment, so the secret is safe here. Public
// `Application <app_key>` auth is the on-device scheme and additionally requires the application to
// have a callback_url configured (see README).

import DIDWWVerification
import Foundation

func env(_ key: String) -> String? {
    let value = ProcessInfo.processInfo.environment[key]
    return (value?.isEmpty ?? true) ? nil : value
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

/// Resolve the target environment: a named `ENVIRONMENT` wins (unknown names fail fast); otherwise
/// `BASE_URL` selects a custom host.
func resolveEnvironment() -> VerifyEnvironment {
    if let name = env("ENVIRONMENT") {
        switch name.lowercased() {
        case "production": return .production
        case "sandbox": return .sandbox
        default:
            fail("Unknown ENVIRONMENT '\(name)'. Valid: production, sandbox — or set BASE_URL for a custom host.", code: 2)
        }
    }
    guard let baseURLString = env("BASE_URL"), let url = URL(string: baseURLString) else {
        fail("Set ENVIRONMENT=production|sandbox, or BASE_URL=<scheme+host> for a custom host.", code: 2)
    }
    return .custom(url)
}

let environment = resolveEnvironment()

guard let appKey = env("APP_KEY"),
      let secret = env("SECRET"),
      let destination = env("DESTINATION") else {
    fail("""
    Missing environment. Required: APP_KEY, SECRET, DESTINATION (plus ENVIRONMENT or BASE_URL).
    Example:
      ENVIRONMENT=sandbox APP_KEY=... SECRET=... DESTINATION=+15551234567 swift run SampleCLI
    """, code: 2)
}

let client = VerificationClient(
    environment: environment,
    auth: .basic(appKey: appKey, secret: secret),
    configuration: .init(timeout: 30)
)

do {
    print("Starting SMS verification to \(destination)…")
    let verification = try await client.start(destination: destination, method: .sms)
    // A start can come back already settled as a 201 — a denial, most often. Nothing was
    // dispatched in that case, so there is no code to ask the user for.
    print("Started. id=\(verification.id)  status=\(verification.status)  expires=\(verification.expiresAt)")
    if verification.status.isTerminal {
        let reasonText = verification.reason.map { " — reason: \($0)" } ?? ""
        fail("Verification finished at creation: \(verification.status)\(reasonText)")
    }
    if case .sms(let sms) = try await client.status(verification).details, let template = sms.template {
        print("SMS template: \(template)")
    }

    print("Enter the code you received: ", terminator: "")
    guard let code = readLine(strippingNewline: true), !code.isEmpty else {
        fail("No code entered; aborting.")
    }

    let result = try await client.verify(verification, code: code)
    switch result.status {
    case .verified:
        print("✅ Verified.")
    case .failed, .denied, .expired:
        let reasonText = result.reason.map { " — reason: \($0)" } ?? ""
        print("❌ \(result.status)\(reasonText)")
    default:
        print("Status: \(result.status)")
    }
} catch let error as APIError {
    fail("SDK error: \(error)")
} catch let error as VerificationError {
    fail("SDK usage error (wrong channel overload): \(error)")
} catch {
    fail("Unexpected error: \(error)")
}
