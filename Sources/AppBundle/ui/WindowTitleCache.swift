import Foundation

private struct CachedWindowTitle {
    let title: String?
    let fetchedAt: Date
    let readId: UInt64
}

private struct WindowTitleRefresh: Sendable {
    let readId: UInt64
    let windowId: UInt32
    let rawTitle: String
}

private struct InFlightWindowTitleRead {
    let readId: UInt64
    let appId: ObjectIdentifier
    let task: Task<WindowTitleRefresh, any Error>
    let completion: AwaitableOneTimeBroadcastLatch
    var waiterCount: Int
    var isComplete: Bool
}

private struct WindowTitleReadTail {
    let readId: UInt64
    let task: Task<WindowTitleRefresh, any Error>
}

private enum WindowTitleRefreshConsumer: Hashable {
    case workspaceSidebar
    case windowTabs
}

// Window instances are main-actor-owned tree nodes. Keeping the batch behind an
// actor-isolated, unchecked-sendable box lets independent app reads overlap
// without allowing the instances themselves to escape their isolation domain.
@MainActor
private final class WindowTitleReadBatch: @unchecked Sendable {
    private let windowsByApp: [[Window]]

    init(windowsByApp: [[Window]]) {
        self.windowsByApp = windowsByApp
    }

    var appCount: Int { windowsByApp.count }

    func read(appIndex: Int) async throws -> [WindowTitleRefresh] {
        var refreshes: [WindowTitleRefresh] = []
        let windows = windowsByApp[appIndex]
        refreshes.reserveCapacity(windows.count)
        for window in windows {
            try Task.checkCancellation()
            do {
                refreshes.append(try await readWindowTitle(window))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }
        return refreshes
    }
}

private let cachedWindowTitleMaxAge: TimeInterval = 5

@TaskLocal
private var readsWindowTitlesFromCacheOnly = false

@TaskLocal
private var suppressesWorkspaceSidebarWindowTitleRefresh = false

@MainActor
private var cachedWindowTitles: [UInt32: CachedWindowTitle] = [:]

@MainActor
private var cachedWindowTitleGeneration: UInt64 = 0

@MainActor
private var nextWindowTitleReadId: UInt64 = 0

@MainActor
private var inFlightWindowTitleReads: [UInt32: InFlightWindowTitleRead] = [:]

@MainActor
private var windowTitleReadTailsByApp: [ObjectIdentifier: WindowTitleReadTail] = [:]

@MainActor
private var pendingWorkspaceSidebarWindowTitleRefreshes: [UInt32: Window] = [:]

@MainActor
private var pendingWindowTitleRefreshConsumers: Set<WindowTitleRefreshConsumer> = []

@MainActor
private var activeWindowTitleRefreshIds: Set<UInt32> = []

@MainActor
private var scheduledWorkspaceSidebarWindowTitleRefresh: Task<Void, Never>? = nil

@MainActor
private var workspaceSidebarWindowTitleRefreshGeneration: UInt64 = 0

@MainActor
private var workspaceSidebarWindowTitleRefreshHandlerForTests: (@MainActor () async -> Void)? = nil

@MainActor
private func readWindowTitle(_ window: Window) async throws -> WindowTitleRefresh {
    let cacheGeneration = cachedWindowTitleGeneration
    let read = acquireWindowTitleRead(window)
    defer { releaseWindowTitleRead(windowId: window.windowId, readId: read.readId) }

    try await read.completion.await()
    try Task.checkCancellation()
    guard cacheGeneration == cachedWindowTitleGeneration else {
        throw CancellationError()
    }
    let refresh = try await read.task.value
    guard cacheGeneration == cachedWindowTitleGeneration else {
        throw CancellationError()
    }
    return refresh
}

@MainActor
private func acquireWindowTitleRead(_ window: Window) -> InFlightWindowTitleRead {
    if var read = inFlightWindowTitleReads[window.windowId], read.waiterCount > 0 {
        read.waiterCount += 1
        inFlightWindowTitleReads[window.windowId] = read
        return read
    }

    nextWindowTitleReadId &+= 1
    let readId = nextWindowTitleReadId
    let appId = ObjectIdentifier(window.app)
    let completion = AwaitableOneTimeBroadcastLatch()
    let predecessor = windowTitleReadTailsByApp[appId]?.task
    let task: Task<WindowTitleRefresh, any Error> = Task { @MainActor in
        let result: Result<WindowTitleRefresh, any Error>
        do {
            if let predecessor {
                _ = await predecessor.result
            }
            try Task.checkCancellation()
            let rawTitle = try await window.title
            try Task.checkCancellation()
            result = .success(WindowTitleRefresh(
                readId: readId,
                windowId: window.windowId,
                rawTitle: rawTitle,
            ))
        } catch {
            result = .failure(error)
        }

        markWindowTitleReadComplete(
            windowId: window.windowId,
            readId: readId,
            appId: appId
        )
        await completion.signalToAll()
        return try result.get()
    }
    let read = InFlightWindowTitleRead(
        readId: readId,
        appId: appId,
        task: task,
        completion: completion,
        waiterCount: 1,
        isComplete: false
    )
    inFlightWindowTitleReads[window.windowId] = read
    windowTitleReadTailsByApp[appId] = WindowTitleReadTail(readId: readId, task: task)
    return read
}

@MainActor
private func releaseWindowTitleRead(windowId: UInt32, readId: UInt64) {
    guard var read = inFlightWindowTitleReads[windowId], read.readId == readId else { return }
    precondition(read.waiterCount > 0)
    read.waiterCount -= 1
    if read.waiterCount == 0, read.isComplete {
        inFlightWindowTitleReads.removeValue(forKey: windowId)
    } else {
        if read.waiterCount == 0 {
            read.task.cancel()
        }
        inFlightWindowTitleReads[windowId] = read
    }
}

@MainActor
private func markWindowTitleReadComplete(
    windowId: UInt32,
    readId: UInt64,
    appId: ObjectIdentifier
) {
    if var read = inFlightWindowTitleReads[windowId], read.readId == readId {
        read.isComplete = true
        if read.waiterCount == 0 {
            inFlightWindowTitleReads.removeValue(forKey: windowId)
        } else {
            inFlightWindowTitleReads[windowId] = read
        }
    }
    if windowTitleReadTailsByApp[appId]?.readId == readId {
        windowTitleReadTailsByApp.removeValue(forKey: appId)
    }
}

@MainActor
private func cancelInFlightWindowTitleReads() {
    let reads = Array(inFlightWindowTitleReads.values)
    inFlightWindowTitleReads = [:]
    windowTitleReadTailsByApp = [:]
    for read in reads {
        read.task.cancel()
        Task { @MainActor in
            await read.completion.signalToAll()
        }
    }
}

@MainActor
func windowTitleReadWaiterCountForTests(_ window: Window) -> Int {
    inFlightWindowTitleReads[window.windowId]?.waiterCount ?? 0
}

@MainActor
func resetCachedWindowTitles() {
    cachedWindowTitleGeneration &+= 1
    cancelInFlightWindowTitleReads()
    scheduledWorkspaceSidebarWindowTitleRefresh?.cancel()
    scheduledWorkspaceSidebarWindowTitleRefresh = nil
    pendingWorkspaceSidebarWindowTitleRefreshes = [:]
    pendingWindowTitleRefreshConsumers = []
    activeWindowTitleRefreshIds = []
    workspaceSidebarWindowTitleRefreshGeneration += 1
    workspaceSidebarWindowTitleRefreshHandlerForTests = nil
    cachedWindowTitles = [:]
}

@MainActor
func cachedWindowTitle(for window: Window) -> String? {
    cachedWindowTitles[window.windowId]?.title
}

@MainActor
func pruneCachedWindowTitles() {
    cachedWindowTitles = cachedWindowTitles.filter { Window.get(byId: $0.key) != nil }
}

@MainActor
@discardableResult
func refreshCachedWindowTitles(
    _ windows: [Window],
    maxAge: TimeInterval = cachedWindowTitleMaxAge,
    now: Date = .now,
) async throws -> Bool {
    let cacheGeneration = cachedWindowTitleGeneration
    var seenWindowIds: Set<UInt32> = []
    let staleWindows = windows.filter { window in
        guard seenWindowIds.insert(window.windowId).inserted else { return false }
        guard let cached = cachedWindowTitles[window.windowId] else { return true }
        return now.timeIntervalSince(cached.fetchedAt) >= maxAge
    }
    guard !staleWindows.isEmpty else { return false }

    let windowsByApp = Dictionary(grouping: staleWindows) { ObjectIdentifier($0.app) }
    let batch = WindowTitleReadBatch(windowsByApp: Array(windowsByApp.values))
    let refreshes = try await withThrowingTaskGroup(
        of: [WindowTitleRefresh].self,
        returning: [WindowTitleRefresh].self
    ) { group in
        for appIndex in 0 ..< batch.appCount {
            group.addTask {
                try await batch.read(appIndex: appIndex)
            }
        }

        var refreshes: [WindowTitleRefresh] = []
        refreshes.reserveCapacity(staleWindows.count)
        for try await appRefreshes in group {
            refreshes.append(contentsOf: appRefreshes)
        }
        return refreshes
    }
    try Task.checkCancellation()
    guard cacheGeneration == cachedWindowTitleGeneration else {
        throw CancellationError()
    }

    var didChangeTitle = false
    for refresh in refreshes {
        if let cached = cachedWindowTitles[refresh.windowId] {
            guard cached.readId < refresh.readId || (
                cached.readId == refresh.readId && cached.fetchedAt <= now
            ) else { continue }
        }
        let cachedTitle = cachedWindowTitles[refresh.windowId]?.title
        let normalized = refresh.rawTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .takeIf { !$0.isEmpty }
        let refreshedTitle = normalized ?? cachedTitle
        didChangeTitle = didChangeTitle || refreshedTitle != cachedTitle
        cachedWindowTitles[refresh.windowId] = CachedWindowTitle(
            title: refreshedTitle,
            fetchedAt: now,
            readId: refresh.readId,
        )
    }
    return didChangeTitle
}

@MainActor
func prefetchCachedWindowTitles(
    _ windows: [Window],
    maxAge: TimeInterval = cachedWindowTitleMaxAge,
    now: Date = .now,
) async {
    do {
        try await refreshCachedWindowTitles(windows, maxAge: maxAge, now: now)
    } catch {
        // A failed or cancelled read stays stale so a later refresh can retry it.
    }
}

@MainActor
func getCachedWindowTitle(
    _ window: Window,
    maxAge: TimeInterval = cachedWindowTitleMaxAge,
    now: Date = .now,
) async -> String? {
    if readsWindowTitlesFromCacheOnly {
        return cachedWindowTitles[window.windowId]?.title
    }
    await prefetchCachedWindowTitles([window], maxAge: maxAge, now: now)
    return cachedWindowTitles[window.windowId]?.title
}

@MainActor
func withWorkspaceSidebarCachedWindowTitles<T>(
    _ windows: [Window],
    operation: @MainActor () async -> T,
) async -> T {
    if !suppressesWorkspaceSidebarWindowTitleRefresh {
        scheduleWorkspaceSidebarWindowTitleRefresh(windows, consumer: .workspaceSidebar)
    }
    return await $readsWindowTitlesFromCacheOnly.withValue(true) {
        await operation()
    }
}

@MainActor
func withWindowTabCachedWindowTitles<T>(
    _ windows: [Window],
    operation: @MainActor () async -> T,
) async -> T {
    if !suppressesWorkspaceSidebarWindowTitleRefresh {
        scheduleWorkspaceSidebarWindowTitleRefresh(windows, consumer: .windowTabs)
    }
    return await $readsWindowTitlesFromCacheOnly.withValue(true) {
        await operation()
    }
}

@MainActor
private func scheduleWorkspaceSidebarWindowTitleRefresh(
    _ windows: [Window],
    consumer: WindowTitleRefreshConsumer,
) {
    let now = Date.now
    var didQueueWindow = false
    for window in windows where cachedWindowTitles[window.windowId].map({
        now.timeIntervalSince($0.fetchedAt) >= cachedWindowTitleMaxAge
    }) ?? true {
        guard !activeWindowTitleRefreshIds.contains(window.windowId) else {
            pendingWindowTitleRefreshConsumers.insert(consumer)
            continue
        }
        pendingWorkspaceSidebarWindowTitleRefreshes[window.windowId] = window
        didQueueWindow = true
    }
    if didQueueWindow {
        pendingWindowTitleRefreshConsumers.insert(consumer)
    }
    startWorkspaceSidebarWindowTitleRefreshIfNeeded()
}

@MainActor
private func startWorkspaceSidebarWindowTitleRefreshIfNeeded() {
    guard scheduledWorkspaceSidebarWindowTitleRefresh == nil,
          !pendingWorkspaceSidebarWindowTitleRefreshes.isEmpty
    else { return }

    let generation = workspaceSidebarWindowTitleRefreshGeneration
    scheduledWorkspaceSidebarWindowTitleRefresh = Task { @MainActor in
        await runWorkspaceSidebarWindowTitleRefresh(generation: generation)
    }
}

@MainActor
private func runWorkspaceSidebarWindowTitleRefresh(generation: UInt64) async {
    var didChangeTitle = false
    var consumers: Set<WindowTitleRefreshConsumer> = []
    do {
        await Task.yield()
        while true {
            try Task.checkCancellation()
            guard generation == workspaceSidebarWindowTitleRefreshGeneration else { return }
            let windows = Array(pendingWorkspaceSidebarWindowTitleRefreshes.values)
            pendingWorkspaceSidebarWindowTitleRefreshes = [:]
            consumers.formUnion(pendingWindowTitleRefreshConsumers)
            pendingWindowTitleRefreshConsumers = []
            guard !windows.isEmpty else { break }
            let windowIds = Set(windows.map(\.windowId))
            activeWindowTitleRefreshIds.formUnion(windowIds)
            defer { activeWindowTitleRefreshIds.subtract(windowIds) }
            didChangeTitle = try await refreshCachedWindowTitles(windows) || didChangeTitle
        }
    } catch {
        guard generation == workspaceSidebarWindowTitleRefreshGeneration else { return }
        scheduledWorkspaceSidebarWindowTitleRefresh = nil
        pendingWorkspaceSidebarWindowTitleRefreshes = [:]
        pendingWindowTitleRefreshConsumers = []
        activeWindowTitleRefreshIds = []
        return
    }

    guard generation == workspaceSidebarWindowTitleRefreshGeneration,
          !Task.isCancelled
    else { return }

    if didChangeTitle {
        let testHandler = workspaceSidebarWindowTitleRefreshHandlerForTests
        await $suppressesWorkspaceSidebarWindowTitleRefresh.withValue(true) {
            if let testHandler {
                await testHandler()
            } else {
                if consumers.contains(.workspaceSidebar), config.workspaceSidebar.enabled {
                    await updateWorkspaceSidebarModel()
                }
                if consumers.contains(.windowTabs), legacyWindowTabBehaviorIsEnabled() {
                    await updateWindowTabModel()
                }
            }
        }
    }

    guard generation == workspaceSidebarWindowTitleRefreshGeneration else { return }
    scheduledWorkspaceSidebarWindowTitleRefresh = nil
    startWorkspaceSidebarWindowTitleRefreshIfNeeded()
}

@MainActor
func setWorkspaceSidebarWindowTitleRefreshHandlerForTests(
    _ handler: (@MainActor () async -> Void)?
) {
    workspaceSidebarWindowTitleRefreshHandlerForTests = handler
}

@MainActor
func waitForWorkspaceSidebarWindowTitleRefreshForTests() async {
    while let task = scheduledWorkspaceSidebarWindowTitleRefresh {
        await task.value
    }
}
