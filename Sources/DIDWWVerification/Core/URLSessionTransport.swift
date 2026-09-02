import Foundation

/// The real transport, over `URLSession`.
///
/// `async`/`await` back-deploys to iOS 13 but `URLSession.data(for:)` is iOS 15+, so to hold the
/// iOS 13 floor this bridges the completion-handler `dataTask` with
/// `withCheckedThrowingContinuation` and wires task cancellation through
/// `withTaskCancellationHandler`.
struct URLSessionTransport: Transport {
    let session: URLSession

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let box = TaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HTTPResponse, Error>) in
                let task = session.dataTask(with: request) { data, response, error in
                    if let urlError = error as? URLError {
                        // A cancelled request surfaces idiomatically as Swift's CancellationError,
                        // so structured-concurrency callers catch it the standard way.
                        if urlError.code == .cancelled {
                            continuation.resume(throwing: CancellationError())
                        } else {
                            continuation.resume(throwing: APIError.transport(urlError))
                        }
                        return
                    }
                    if error != nil {
                        continuation.resume(throwing: APIError.transport(URLError(.unknown)))
                        return
                    }
                    guard let http = response as? HTTPURLResponse, let data else {
                        continuation.resume(throwing: APIError.unexpectedResponse("no HTTP response"))
                        return
                    }
                    continuation.resume(returning: HTTPResponse(statusCode: http.statusCode, body: data))
                }
                // Store BEFORE resume so cancellation can reach the task. `store` also handles the
                // already-cancelled race (see TaskBox): if cancellation fired first, it cancels now.
                box.store(task)
                task.resume()
            }
        } onCancel: {
            box.cancel()
        }
    }
}

/// Lock-guarded holder bridging Swift task cancellation to a `URLSessionDataTask`.
///
/// `@unchecked Sendable`: the lock supplies the safety the compiler can't verify. It closes a real
/// runtime race — if `cancel()` arrives before `store(_:)`, the `isCancelled` flag makes `store`
/// cancel immediately instead of leaking a live request.
final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var isCancelled = false

    func store(_ task: URLSessionDataTask) {
        lock.lock()
        let alreadyCancelled = isCancelled
        if !alreadyCancelled { self.task = task }
        lock.unlock()
        if alreadyCancelled { task.cancel() }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let taskToCancel = task
        lock.unlock()
        taskToCancel?.cancel()
    }
}
