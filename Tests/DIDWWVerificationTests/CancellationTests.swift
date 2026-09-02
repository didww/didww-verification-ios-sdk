import Foundation
import XCTest
@testable import DIDWWVerification

final class CancellationTests: XCTestCase {
    func testCancellationPropagatesThroughClientAsCancellationError() async throws {
        let transport = SuspendingMockTransport()
        let client = makeClient(transport: transport)
        let handle = makeHandle()

        let task = Task { try await client.status(handle) }

        // Wait until the transport is actually suspended, then cancel the surrounding Task.
        await fulfillment(of: [transport.didSuspend], timeout: 2)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
    }

    func testConfigurationTimeoutDefaultsAndOverrides() {
        XCTAssertEqual(Configuration().timeout, 30, accuracy: 0.001)
        XCTAssertEqual(Configuration(timeout: 5).timeout, 5, accuracy: 0.001)
    }
}
