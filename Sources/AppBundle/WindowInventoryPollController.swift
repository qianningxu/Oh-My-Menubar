import Foundation

@MainActor
final class WindowInventoryPollController {
    private enum ScheduledWork: Equatable {
        case checkInventory
        case retryReconciliation
    }

    typealias ScheduledOperation = @MainActor () async -> Void
    typealias CancelScheduledOperation = @MainActor () -> Void
    typealias Scheduler = @MainActor (
        _ delay: TimeInterval,
        _ tolerance: TimeInterval,
        _ operation: @escaping ScheduledOperation
    ) -> CancelScheduledOperation

    static let initialDelay: TimeInterval = 0.35
    static let maximumDelay: TimeInterval = 30
    static let reconciliationRetryDelay: TimeInterval = initialDelay

    private let scheduler: Scheduler
    private let checkInventory: @MainActor () async -> Bool
    private let reconcileIfIdle: @MainActor () -> Bool
    private let now: @MainActor () -> TimeInterval

    private var currentDelay = initialDelay
    private var scheduledDeadline: TimeInterval?
    private var scheduledWork: ScheduledWork?
    private var cancelScheduledOperation: CancelScheduledOperation?
    private var scheduleGeneration: UInt64 = 0
    private var lifecycleGeneration: UInt64 = 0
    private var isRunning = false
    private var isChecking = false
    private var activityWhileChecking = false
    private var reconciliationPending = false

    init(
        scheduler: @escaping Scheduler,
        checkInventory: @escaping @MainActor () async -> Bool,
        reconcileIfIdle: @escaping @MainActor () -> Bool,
        now: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.scheduler = scheduler
        self.checkInventory = checkInventory
        self.reconcileIfIdle = reconcileIfIdle
        self.now = now
    }

    func start() {
        guard !isRunning else {
            noteActivity()
            return
        }
        lifecycleGeneration += 1
        isRunning = true
        currentDelay = Self.initialDelay
        schedule(.checkInventory, after: currentDelay)
    }

    func stop() {
        lifecycleGeneration += 1
        isRunning = false
        activityWhileChecking = false
        reconciliationPending = false
        cancelScheduledWork()
    }

    func noteActivity() {
        guard isRunning else { return }
        currentDelay = Self.initialDelay
        if isChecking {
            activityWhileChecking = true
        } else {
            let work: ScheduledWork = reconciliationPending ? .retryReconciliation : .checkInventory
            schedule(work, after: Self.initialDelay)
        }
    }

    private func schedule(_ work: ScheduledWork, after delay: TimeInterval) {
        guard isRunning else { return }
        let deadline = now() + delay
        if scheduledWork == work, let scheduledDeadline, scheduledDeadline <= deadline {
            return
        }

        cancelScheduledWork()
        scheduleGeneration += 1
        let generation = scheduleGeneration
        scheduledDeadline = deadline
        scheduledWork = work
        cancelScheduledOperation = scheduler(delay, Self.tolerance(for: delay)) { [weak self] in
            guard let self else { return }
            await self.runScheduledWork(work, generation: generation)
        }
    }

    private func cancelScheduledWork() {
        scheduleGeneration += 1
        cancelScheduledOperation?()
        cancelScheduledOperation = nil
        scheduledDeadline = nil
        scheduledWork = nil
    }

    private func runScheduledWork(_ work: ScheduledWork, generation: UInt64) async {
        guard isRunning, generation == scheduleGeneration else { return }
        cancelScheduledOperation = nil
        scheduledDeadline = nil
        scheduledWork = nil

        switch work {
        case .checkInventory:
            await runInventoryCheck()
        case .retryReconciliation:
            retryPendingReconciliation()
        }
    }

    private func runInventoryCheck() async {
        guard !isChecking else {
            activityWhileChecking = true
            return
        }

        isChecking = true
        let checkLifecycleGeneration = lifecycleGeneration
        let inventoryChanged = await checkInventory()
        isChecking = false

        guard isRunning, checkLifecycleGeneration == lifecycleGeneration else {
            if isRunning, activityWhileChecking {
                activityWhileChecking = false
                currentDelay = Self.initialDelay
                schedule(.checkInventory, after: currentDelay)
            }
            return
        }

        if activityWhileChecking {
            activityWhileChecking = false
            currentDelay = Self.initialDelay
        } else {
            currentDelay = min(currentDelay * 2, Self.maximumDelay)
        }

        if inventoryChanged {
            reconciliationPending = true
            retryPendingReconciliation()
        } else {
            schedule(.checkInventory, after: currentDelay)
        }
    }

    private func retryPendingReconciliation() {
        guard reconciliationPending else { return }
        let reconciliationLifecycleGeneration = lifecycleGeneration
        let didReconcile = reconcileIfIdle()
        guard isRunning, reconciliationLifecycleGeneration == lifecycleGeneration else { return }

        if didReconcile {
            reconciliationPending = false
            schedule(.checkInventory, after: currentDelay)
        } else {
            schedule(.retryReconciliation, after: Self.reconciliationRetryDelay)
        }
    }

    static func tolerance(for delay: TimeInterval) -> TimeInterval {
        min(delay * 0.2, 0.5)
    }
}
