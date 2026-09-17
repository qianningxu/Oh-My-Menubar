@testable import AppBundle
import XCTest

@MainActor
private final class WindowInventoryPollTestScheduler {
    struct Job {
        let id: Int
        let deadline: TimeInterval
        let delay: TimeInterval
        let tolerance: TimeInterval
        let operation: WindowInventoryPollController.ScheduledOperation
    }

    private(set) var now: TimeInterval = 0
    private(set) var history: [(delay: TimeInterval, tolerance: TimeInterval)] = []
    private var nextId = 0
    private var jobs: [Int: Job] = [:]

    var pendingJobs: [Job] {
        jobs.values.sorted { $0.deadline < $1.deadline }
    }

    func schedule(
        delay: TimeInterval,
        tolerance: TimeInterval,
        operation: @escaping WindowInventoryPollController.ScheduledOperation
    ) -> WindowInventoryPollController.CancelScheduledOperation {
        nextId += 1
        let id = nextId
        history.append((delay, tolerance))
        jobs[id] = Job(
            id: id,
            deadline: now + delay,
            delay: delay,
            tolerance: tolerance,
            operation: operation
        )
        return { [weak self] in self?.jobs[id] = nil }
    }

    func advance(to time: TimeInterval) {
        now = time
    }

    func runNext() async {
        guard let job = pendingJobs.first else {
            XCTFail("Expected a scheduled inventory check")
            return
        }
        jobs[job.id] = nil
        now = job.deadline
        await job.operation()
    }
}

final class WindowInventoryPollControllerTest: XCTestCase {
    @MainActor
    func testStableChecksBackOffAndCapAtThirtySecondsWithoutReconciling() async {
        let scheduler = WindowInventoryPollTestScheduler()
        var reconcileCount = 0
        let controller = makeController(
            scheduler: scheduler,
            reconcileIfIdle: {
                reconcileCount += 1
                return true
            }
        )

        controller.start()
        XCTAssertEqual(scheduler.pendingJobs.map(\.delay), [0.35])
        for _ in 0 ..< 8 {
            await scheduler.runNext()
        }

        XCTAssertEqual(scheduler.history.map(\.delay), [0.35, 0.7, 1.4, 2.8, 5.6, 11.2, 22.4, 30, 30])
        let expectedTolerances = [0.07, 0.14, 0.28, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5]
        XCTAssertEqual(scheduler.history.count, expectedTolerances.count)
        for (entry, expectedTolerance) in zip(scheduler.history, expectedTolerances) {
            XCTAssertEqual(entry.tolerance, expectedTolerance, accuracy: 0.000_001)
        }
        XCTAssertEqual(reconcileCount, 0)

        scheduler.advance(to: scheduler.now + 1)
        controller.noteActivity()
        XCTAssertEqual(scheduler.pendingJobs.map(\.delay), [0.35])
    }

    @MainActor
    func testActivityAcceleratesWithoutPostponingEarlierDeadline() async {
        let scheduler = WindowInventoryPollTestScheduler()
        let controller = makeController(scheduler: scheduler)

        controller.start()
        scheduler.advance(to: 0.1)
        controller.noteActivity()
        XCTAssertEqual(scheduler.history.map(\.delay), [0.35])

        await scheduler.runNext()
        XCTAssertEqual(scheduler.pendingJobs.map(\.delay), [0.7])
        scheduler.advance(to: 0.4)
        controller.noteActivity()
        XCTAssertEqual(scheduler.pendingJobs.map(\.delay), [0.35])
        scheduler.advance(to: 0.5)
        controller.noteActivity()
        XCTAssertEqual(scheduler.history.map(\.delay), [0.35, 0.7, 0.35])
    }

    @MainActor
    func testPersistentMismatchReconcilesWithoutReturningToFastLoop() async {
        let scheduler = WindowInventoryPollTestScheduler()
        var reconcileCount = 0
        let controller = makeController(
            scheduler: scheduler,
            checkInventory: { true },
            reconcileIfIdle: {
                reconcileCount += 1
                return true
            }
        )

        controller.start()
        for _ in 0 ..< 4 {
            await scheduler.runNext()
        }

        XCTAssertEqual(reconcileCount, 4)
        XCTAssertEqual(scheduler.history.map(\.delay), [0.35, 0.7, 1.4, 2.8, 5.6])
    }

    @MainActor
    func testFailedReconciliationRetriesWithoutRecheckingInventoryAndCoalescesActivity() async {
        let scheduler = WindowInventoryPollTestScheduler()
        var inventoryResults = [true, false]
        var inventoryCheckCount = 0
        var reconciliationResults = [false, false, true]
        var reconcileCount = 0
        let controller = makeController(
            scheduler: scheduler,
            checkInventory: {
                inventoryCheckCount += 1
                return inventoryResults.removeFirst()
            },
            reconcileIfIdle: {
                reconcileCount += 1
                return reconciliationResults.removeFirst()
            }
        )

        controller.start()
        await scheduler.runNext()

        XCTAssertEqual(inventoryCheckCount, 1)
        XCTAssertEqual(reconcileCount, 1)
        XCTAssertEqual(scheduler.pendingJobs.map(\.delay), [0.35])

        controller.noteActivity()
        controller.noteActivity()
        XCTAssertEqual(scheduler.history.map(\.delay), [0.35, 0.35])

        await scheduler.runNext()
        XCTAssertEqual(inventoryCheckCount, 1)
        XCTAssertEqual(reconcileCount, 2)
        XCTAssertEqual(scheduler.pendingJobs.map(\.delay), [0.35])

        await scheduler.runNext()
        XCTAssertEqual(inventoryCheckCount, 1)
        XCTAssertEqual(reconcileCount, 3)
        XCTAssertEqual(scheduler.pendingJobs.map(\.delay), [0.35])

        await scheduler.runNext()
        XCTAssertEqual(inventoryCheckCount, 2)
        XCTAssertEqual(reconcileCount, 3)
        XCTAssertEqual(scheduler.pendingJobs.map(\.delay), [0.7])
    }

    @MainActor
    func testActivityDuringCheckSchedulesOneFastFollowUp() async {
        let scheduler = WindowInventoryPollTestScheduler()
        var continuation: CheckedContinuation<Bool, Never>?
        var activeChecks = 0
        var maximumActiveChecks = 0
        let controller = makeController(
            scheduler: scheduler,
            checkInventory: {
                activeChecks += 1
                maximumActiveChecks = max(maximumActiveChecks, activeChecks)
                let result = await withCheckedContinuation { continuation = $0 }
                activeChecks -= 1
                return result
            }
        )

        controller.start()
        let runningCheck = Task { @MainActor in await scheduler.runNext() }
        while continuation == nil {
            await Task.yield()
        }
        controller.noteActivity()
        controller.noteActivity()
        XCTAssertTrue(scheduler.pendingJobs.isEmpty)
        continuation?.resume(returning: false)
        await runningCheck.value

        XCTAssertEqual(maximumActiveChecks, 1)
        XCTAssertEqual(scheduler.pendingJobs.map(\.delay), [0.35])
    }

    @MainActor
    func testStopDiscardsInFlightResult() async {
        let scheduler = WindowInventoryPollTestScheduler()
        var continuation: CheckedContinuation<Bool, Never>?
        var reconcileCount = 0
        let controller = makeController(
            scheduler: scheduler,
            checkInventory: {
                await withCheckedContinuation { continuation = $0 }
            },
            reconcileIfIdle: {
                reconcileCount += 1
                return true
            }
        )

        controller.start()
        let runningCheck = Task { @MainActor in await scheduler.runNext() }
        while continuation == nil {
            await Task.yield()
        }
        controller.stop()
        continuation?.resume(returning: true)
        await runningCheck.value

        XCTAssertEqual(reconcileCount, 0)
        XCTAssertTrue(scheduler.pendingJobs.isEmpty)
    }

    @MainActor
    func testCanceledQueuedCallbackCannotRunOrReplaceCurrentSchedule() async throws {
        let scheduler = WindowInventoryPollTestScheduler()
        var inventoryCheckCount = 0
        let controller = makeController(
            scheduler: scheduler,
            checkInventory: {
                inventoryCheckCount += 1
                return false
            }
        )

        controller.start()
        await scheduler.runNext()
        let canceledJob = try XCTUnwrap(scheduler.pendingJobs.first)

        controller.noteActivity()
        let currentJob = try XCTUnwrap(scheduler.pendingJobs.first)
        XCTAssertNotEqual(canceledJob.id, currentJob.id)

        await canceledJob.operation()

        XCTAssertEqual(inventoryCheckCount, 1)
        XCTAssertEqual(scheduler.pendingJobs.map(\.id), [currentJob.id])
        XCTAssertEqual(scheduler.history.map(\.delay), [0.35, 0.7, 0.35])
    }

    @MainActor
    func testQueuedReconciliationCallbackFromPreviousLifecycleIsDiscardedAfterRestart() async throws {
        let scheduler = WindowInventoryPollTestScheduler()
        var inventoryCheckCount = 0
        var reconcileCount = 0
        let controller = makeController(
            scheduler: scheduler,
            checkInventory: {
                inventoryCheckCount += 1
                return true
            },
            reconcileIfIdle: {
                reconcileCount += 1
                return false
            }
        )

        controller.start()
        await scheduler.runNext()
        let previousLifecycleRetry = try XCTUnwrap(scheduler.pendingJobs.first)
        controller.stop()
        controller.start()
        let currentJob = try XCTUnwrap(scheduler.pendingJobs.first)

        await previousLifecycleRetry.operation()

        XCTAssertEqual(inventoryCheckCount, 1)
        XCTAssertEqual(reconcileCount, 1)
        XCTAssertEqual(scheduler.pendingJobs.map(\.id), [currentJob.id])
        XCTAssertEqual(scheduler.history.map(\.delay), [0.35, 0.35, 0.35])
    }

    @MainActor
    private func makeController(
        scheduler: WindowInventoryPollTestScheduler,
        checkInventory: @escaping @MainActor () async -> Bool = { false },
        reconcileIfIdle: @escaping @MainActor () -> Bool = { true }
    ) -> WindowInventoryPollController {
        WindowInventoryPollController(
            scheduler: scheduler.schedule,
            checkInventory: checkInventory,
            reconcileIfIdle: reconcileIfIdle,
            now: { scheduler.now }
        )
    }
}
