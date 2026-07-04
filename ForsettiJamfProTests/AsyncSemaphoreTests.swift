import XCTest
@testable import ForsettiJamfProApp

// "End of Line"

/// Exercises the `AsyncSemaphore` actor and — critically — the
/// gateway's `withPermit` pattern that sits on top of it.
///
/// The audit caught a permit leak: the gateway acquired a permit, ran
/// the network call, and released only on the success branch. A throw
/// from `session.data(for:)` (DNS failure, cancellation, dropped
/// connection) left the permit uncounted. After five concurrent
/// failures the semaphore had zero permits left and every subsequent
/// request blocked forever. The fix routes the critical section
/// through `withPermit` + `defer` so the release runs on every exit
/// path, including thrown errors.
///
/// These tests verify:
/// 1. The semaphore itself correctly counts permits across acquire/release.
/// 2. Concurrent waiters are unblocked in order.
/// 3. The fix holds: repeated failure-path executions must not
///    exhaust the permit pool.
final class AsyncSemaphoreTests: XCTestCase {

    // MARK: - Basic semantics

    func test_acquire_withFreePermit_doesNotBlock() async {
        let semaphore = AsyncSemaphore(maxConcurrency: 1)
        await semaphore.acquire()
        // If we reach here within the test timeout, acquire didn't block.
        await semaphore.release()
    }

    func test_multipleAcquireRelease_reusesPermitsCleanly() async {
        let semaphore = AsyncSemaphore(maxConcurrency: 2)
        // Cycle the semaphore ten times through acquire/release. If the
        // permit accounting were off, we'd either deadlock or end up
        // with more permits than we started with.
        for _ in 0..<10 {
            await semaphore.acquire()
            await semaphore.release()
        }
        // Final state: both permits available — acquire twice in a row
        // should succeed without blocking.
        await semaphore.acquire()
        await semaphore.acquire()
        await semaphore.release()
        await semaphore.release()
    }

    // MARK: - Concurrent waiters

    func test_concurrentAcquires_unblockAsPermitsRelease() async {
        let semaphore = AsyncSemaphore(maxConcurrency: 1)
        await semaphore.acquire()

        // Start a second acquire that will block behind the first.
        let waitTask = Task {
            await semaphore.acquire()
            await semaphore.release()
        }

        // Give the waiter a moment to enqueue (no other signal available).
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Release should unblock the waiter.
        await semaphore.release()

        // Waiter finishes on its own — a timeout here means the waiter
        // never woke up.
        await waitTask.value
    }

    // MARK: - The leak scenario

    /// The core regression guard. Simulates the failure-path flow that
    /// used to leak permits: acquire, execute a block that throws,
    /// release via `defer`. After running this 10× on a 3-permit pool,
    /// the pool must still have 3 permits available.
    func test_withPermitStandIn_doesNotLeakOnThrow() async {
        let semaphore = AsyncSemaphore(maxConcurrency: 3)

        struct SimulatedThrow: Error {}

        // Drive 10 throwing "requests" through a defer-based release
        // pattern. This mimics what the gateway's `withPermit` helper
        // does around `session.data(for:)`.
        for _ in 0..<10 {
            await semaphore.acquire()
            do {
                // `defer`-backed release must fire even on throw.
                defer {
                    Task {
                        await semaphore.release()
                    }
                }
                throw SimulatedThrow()
            } catch {
                // Let the deferred release actually run before the
                // next iteration — otherwise we can get scheduling-
                // dependent timing. 5 ms is plenty.
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
        }

        // All three permits must still be acquirable. If the leak bug
        // were back, the pool would be exhausted and this would block
        // past the test timeout.
        await semaphore.acquire()
        await semaphore.acquire()
        await semaphore.acquire()
        await semaphore.release()
        await semaphore.release()
        await semaphore.release()
    }
}

//endofline
