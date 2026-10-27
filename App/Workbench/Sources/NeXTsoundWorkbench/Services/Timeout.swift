import Foundation
import Synchronization

/// Runs `operation` and returns its result, or throws `timeoutError` once `timeout` has passed, whichever comes first.
///
/// A task group cannot bound an operation that ignores cancellation, such as a blocking libusb control transfer on a
/// dispatch queue: the group waits for every child before it returns, so its timeout would end only with the
/// operation. Here the operation runs in a task of its own that outlives the timeout, and a result it delivers late is
/// dropped. The caller learns of the timeout on time, while the operation itself still runs to its own end.
///
/// - Parameters:
///   - timeout: How long the caller waits for the operation.
///   - timeoutError: The error thrown when the timeout passes first.
///   - operation: The work to wait for.
/// - Returns: The operation's value, when it finishes before the timeout.
/// - Throws: `timeoutError`, or the operation's own error when it fails before the timeout.
func withTimeout<Value: Sendable>(
    _ timeout: Duration,
    throwing timeoutError: some Error,
    operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    try await withCheckedThrowingContinuation { continuation in
        let outcome = FirstOutcome(continuation)
        let timer = Task {
            try await Task.sleep(for: timeout)
            outcome.deliver(.failure(timeoutError))
        }
        Task {
            do {
                try await outcome.deliver(.success(operation()))
            } catch {
                outcome.deliver(.failure(error))
            }
            timer.cancel()
        }
    }
}

/// Resumes a continuation with the first result delivered to it and drops every later one.
private final class FirstOutcome<Value: Sendable>: Sendable {
    private let continuation: Mutex<CheckedContinuation<Value, any Error>?>

    init(_ continuation: CheckedContinuation<Value, any Error>) {
        self.continuation = Mutex(continuation)
    }

    func deliver(_ result: Result<Value, any Error>) {
        continuation.withLock { $0.take() }?.resume(with: result)
    }
}
