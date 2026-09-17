@testable import AppBundle
import XCTest

final class WindowTitleCacheTest: XCTestCase {
    @MainActor
    func testGetCachedWindowTitleReusesFreshValue() async {
        resetCachedWindowTitles()
        let window = StubTitleWindow(id: 42, title: "  Example  ")

        let first = await getCachedWindowTitle(window, maxAge: 60, now: Date(timeIntervalSince1970: 10))
        let second = await getCachedWindowTitle(window, maxAge: 60, now: Date(timeIntervalSince1970: 20))

        XCTAssertEqual(first, "Example")
        XCTAssertEqual(second, "Example")
        XCTAssertEqual(window.titleGetCount, 1)
    }

    @MainActor
    func testGetCachedWindowTitleRefreshesExpiredValue() async {
        resetCachedWindowTitles()
        let window = StubTitleWindow(id: 43, title: "First")

        let first = await getCachedWindowTitle(window, maxAge: 1, now: Date(timeIntervalSince1970: 10))
        window.stubTitle = "Second"
        let second = await getCachedWindowTitle(window, maxAge: 1, now: Date(timeIntervalSince1970: 12))

        XCTAssertEqual(first, "First")
        XCTAssertEqual(second, "Second")
        XCTAssertEqual(window.titleGetCount, 2)
    }

    @MainActor
    func testPrefetchDeduplicatesWindowsAndKeepsEachAppSequential() async {
        resetCachedWindowTitles()
        let probe = StubTitleReadProbe()
        let firstApp = StubTitleApp(pid: 101)
        let secondApp = StubTitleApp(pid: 102)
        let windows = [
            StubTitleWindow(id: 44, title: "First A", app: firstApp, probe: probe),
            StubTitleWindow(id: 45, title: "Second A", app: firstApp, probe: probe),
            StubTitleWindow(id: 46, title: "First B", app: secondApp, probe: probe),
            StubTitleWindow(id: 47, title: "Second B", app: secondApp, probe: probe),
        ]

        await prefetchCachedWindowTitles(windows + [windows[0]], maxAge: 60)

        XCTAssertEqual(windows.map(\.titleGetCount), [1, 1, 1, 1])
        XCTAssertEqual(probe.maximumReadsByApp[firstApp.pid], 1)
        XCTAssertEqual(probe.maximumReadsByApp[secondApp.pid], 1)
        XCTAssertEqual(probe.maximumConcurrentApps, 2)
    }

    @MainActor
    func testConcurrentRefreshesShareOneWindowRead() async throws {
        resetCachedWindowTitles()
        defer { resetCachedWindowTitles() }
        let latch = AwaitableOneTimeBroadcastLatch()
        let window = StubTitleWindow(id: 55, title: "Shared", titleReadLatch: latch)
        let first = Task { @MainActor in
            try await refreshCachedWindowTitles(
                [window],
                maxAge: 60,
                now: Date(timeIntervalSince1970: 10)
            )
        }
        while window.titleGetCount == 0 {
            await Task.yield()
        }
        let second = Task { @MainActor in
            try await refreshCachedWindowTitles(
                [window],
                maxAge: 60,
                now: Date(timeIntervalSince1970: 20)
            )
        }
        while windowTitleReadWaiterCountForTests(window) < 2 {
            await Task.yield()
        }

        XCTAssertEqual(window.titleGetCount, 1)

        await latch.signalToAll()
        _ = try await first.value
        _ = try await second.value

        XCTAssertEqual(window.titleGetCount, 1)
        XCTAssertEqual(cachedWindowTitle(for: window), "Shared")
    }

    @MainActor
    func testCancellingOneWaiterKeepsSharedReadAlive() async throws {
        resetCachedWindowTitles()
        defer { resetCachedWindowTitles() }
        let latch = AwaitableOneTimeBroadcastLatch()
        let window = StubTitleWindow(id: 56, title: "Shared", titleReadLatch: latch)
        let first = Task { @MainActor in
            do {
                try await refreshCachedWindowTitles([window], maxAge: 60)
                return false
            } catch is CancellationError {
                return true
            } catch {
                XCTFail("Unexpected title refresh error: \(error)")
                return false
            }
        }
        while window.titleGetCount == 0 {
            await Task.yield()
        }
        let second = Task { @MainActor in
            try await refreshCachedWindowTitles([window], maxAge: 60)
        }
        while windowTitleReadWaiterCountForTests(window) < 2 {
            await Task.yield()
        }

        first.cancel()

        let firstWasCancelled = await first.value
        XCTAssertTrue(firstWasCancelled)
        XCTAssertEqual(windowTitleReadWaiterCountForTests(window), 1)
        XCTAssertEqual(window.titleGetCount, 1)

        await latch.signalToAll()
        let secondDidChange = try await second.value
        XCTAssertTrue(secondDidChange)
        XCTAssertEqual(cachedWindowTitle(for: window), "Shared")
        XCTAssertEqual(window.titleGetCount, 1)
    }

    @MainActor
    func testConcurrentBatchesSerializeReadsForTheSameApp() async throws {
        resetCachedWindowTitles()
        defer { resetCachedWindowTitles() }
        let latch = AwaitableOneTimeBroadcastLatch()
        let probe = StubTitleReadProbe()
        let app = StubTitleApp(pid: 104)
        let firstWindow = StubTitleWindow(
            id: 57,
            title: "First",
            app: app,
            probe: probe,
            titleReadDelay: .zero,
            titleReadLatch: latch
        )
        let secondWindow = StubTitleWindow(
            id: 58,
            title: "Second",
            app: app,
            probe: probe,
            titleReadDelay: .zero
        )
        let first = Task { @MainActor in
            try await refreshCachedWindowTitles([firstWindow], maxAge: 60)
        }
        while firstWindow.titleGetCount == 0 {
            await Task.yield()
        }
        let second = Task { @MainActor in
            try await refreshCachedWindowTitles([secondWindow], maxAge: 60)
        }
        while windowTitleReadWaiterCountForTests(secondWindow) == 0 {
            await Task.yield()
        }

        XCTAssertEqual(secondWindow.titleGetCount, 0)
        XCTAssertEqual(probe.maximumReadsByApp[app.pid], 1)

        await latch.signalToAll()
        _ = try await first.value
        _ = try await second.value

        XCTAssertEqual(secondWindow.titleGetCount, 1)
        XCTAssertEqual(probe.maximumReadsByApp[app.pid], 1)
    }

    @MainActor
    func testDelayedOlderBatchDoesNotOverwriteNewerTitle() async throws {
        resetCachedWindowTitles()
        defer { resetCachedWindowTitles() }
        let blockerLatch = AwaitableOneTimeBroadcastLatch()
        let target = StubTitleWindow(
            id: 59,
            title: "Old",
            app: StubTitleApp(pid: 105)
        )
        let blocker = StubTitleWindow(
            id: 60,
            title: "Blocker",
            app: StubTitleApp(pid: 106),
            titleReadLatch: blockerLatch
        )
        let older = Task { @MainActor in
            try await refreshCachedWindowTitles(
                [target, blocker],
                maxAge: 60,
                now: Date(timeIntervalSince1970: 10)
            )
        }
        while target.titleGetCount == 0 || blocker.titleGetCount == 0 {
            await Task.yield()
        }
        while windowTitleReadWaiterCountForTests(target) > 0 {
            await Task.yield()
        }

        target.stubTitle = "New"
        try await refreshCachedWindowTitles(
            [target],
            maxAge: 60,
            now: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(target.titleGetCount, 2)
        XCTAssertEqual(cachedWindowTitle(for: target), "New")

        await blockerLatch.signalToAll()
        _ = try await older.value

        XCTAssertEqual(cachedWindowTitle(for: target), "New")
    }

    @MainActor
    func testWorkspaceSidebarReturnsStaleCachedTitleAndCoalescesRefresh() async throws {
        resetCachedWindowTitles()
        defer { resetCachedWindowTitles() }
        let probe = StubTitleReadProbe()
        let window = StubTitleWindow(id: 48, title: "First", probe: probe)
        try await refreshCachedWindowTitles(
            [window],
            maxAge: 60,
            now: Date(timeIntervalSince1970: 10)
        )
        window.stubTitle = "Second"
        var refreshCallbackCount = 0
        setWorkspaceSidebarWindowTitleRefreshHandlerForTests {
            refreshCallbackCount += 1
        }

        let first = await withWorkspaceSidebarCachedWindowTitles([window]) {
            await getCachedWindowTitle(window)
        }
        let second = await withWorkspaceSidebarCachedWindowTitles([window]) {
            await getCachedWindowTitle(window)
        }

        XCTAssertEqual(first, "First")
        XCTAssertEqual(second, "First")
        XCTAssertEqual(refreshCallbackCount, 0)

        await waitForWorkspaceSidebarWindowTitleRefreshForTests()

        XCTAssertEqual(cachedWindowTitle(for: window), "Second")
        XCTAssertEqual(window.titleGetCount, 2)
        XCTAssertEqual(refreshCallbackCount, 1)
    }

    @MainActor
    func testWorkspaceSidebarUsesAppFallbackUntilColdTitleArrives() async {
        resetCachedWindowTitles()
        defer { resetCachedWindowTitles() }
        let app = StubTitleApp(pid: 103)
        let probe = StubTitleReadProbe()
        let window = StubTitleWindow(id: 49, title: "Cold Title", app: app, probe: probe)
        var refreshCallbackCount = 0
        setWorkspaceSidebarWindowTitleRefreshHandlerForTests {
            refreshCallbackCount += 1
        }

        let immediateTitle = await withWorkspaceSidebarCachedWindowTitles([window]) {
            await tabDisplayTitle(for: window)
        }

        XCTAssertEqual(immediateTitle, app.name)
        XCTAssertEqual(refreshCallbackCount, 0)

        await waitForWorkspaceSidebarWindowTitleRefreshForTests()

        XCTAssertEqual(cachedWindowTitle(for: window), "Cold Title")
        XCTAssertEqual(window.titleGetCount, 1)
        XCTAssertEqual(refreshCallbackCount, 1)
    }

    @MainActor
    func testWindowTabsReturnCachedTitleWhileRefreshRuns() async throws {
        resetCachedWindowTitles()
        defer { resetCachedWindowTitles() }
        let window = StubTitleWindow(id: 54, title: "First")
        try await refreshCachedWindowTitles(
            [window],
            maxAge: 60,
            now: Date(timeIntervalSince1970: 10)
        )
        window.stubTitle = "Second"
        var refreshCallbackCount = 0
        setWorkspaceSidebarWindowTitleRefreshHandlerForTests {
            refreshCallbackCount += 1
        }

        let immediateTitle = await withWindowTabCachedWindowTitles([window]) {
            await getCachedWindowTitle(window)
        }

        XCTAssertEqual(immediateTitle, "First")
        XCTAssertEqual(refreshCallbackCount, 0)

        await waitForWorkspaceSidebarWindowTitleRefreshForTests()

        XCTAssertEqual(cachedWindowTitle(for: window), "Second")
        XCTAssertEqual(window.titleGetCount, 2)
        XCTAssertEqual(refreshCallbackCount, 1)
    }

    @MainActor
    func testCancelledRefreshDoesNotStampTitleFresh() async throws {
        resetCachedWindowTitles()
        defer { resetCachedWindowTitles() }
        let probe = StubTitleReadProbe()
        let window = StubTitleWindow(
            id: 50,
            title: "Recovered",
            probe: probe,
            titleReadDelay: .seconds(30)
        )
        let refreshTask = Task { @MainActor in
            do {
                try await refreshCachedWindowTitles([window], maxAge: 60)
                return false
            } catch is CancellationError {
                return true
            } catch {
                XCTFail("Unexpected title refresh error: \(error)")
                return false
            }
        }
        while window.titleGetCount == 0 {
            await Task.yield()
        }

        refreshTask.cancel()

        let didCancel = await refreshTask.value
        XCTAssertTrue(didCancel)
        XCTAssertNil(cachedWindowTitle(for: window))

        window.titleReadDelay = nil
        try await refreshCachedWindowTitles([window], maxAge: 60)

        XCTAssertEqual(cachedWindowTitle(for: window), "Recovered")
        XCTAssertEqual(window.titleGetCount, 2)
    }

    @MainActor
    func testFailedTitleReadRemainsStaleForRetry() async throws {
        resetCachedWindowTitles()
        defer { resetCachedWindowTitles() }
        let window = StubTitleWindow(id: 51, title: "Retried")
        window.throwsOnTitleRead = true

        let didChangeAfterFailure = try await refreshCachedWindowTitles([window], maxAge: 60)

        XCTAssertFalse(didChangeAfterFailure)
        XCTAssertNil(cachedWindowTitle(for: window))

        window.throwsOnTitleRead = false
        let didChangeAfterRetry = try await refreshCachedWindowTitles([window], maxAge: 60)

        XCTAssertTrue(didChangeAfterRetry)
        XCTAssertEqual(cachedWindowTitle(for: window), "Retried")
        XCTAssertEqual(window.titleGetCount, 2)
    }

    @MainActor
    func testTitleRefreshCallbackDoesNotRecursivelyRetryFailures() async {
        resetCachedWindowTitles()
        defer { resetCachedWindowTitles() }
        let goodWindow = StubTitleWindow(id: 52, title: "Loaded")
        let failingWindow = StubTitleWindow(id: 53, title: "Unavailable")
        failingWindow.throwsOnTitleRead = true
        var refreshCallbackCount = 0
        setWorkspaceSidebarWindowTitleRefreshHandlerForTests {
            refreshCallbackCount += 1
            _ = await withWorkspaceSidebarCachedWindowTitles([goodWindow, failingWindow]) {
                await getCachedWindowTitle(failingWindow)
            }
        }

        _ = await withWorkspaceSidebarCachedWindowTitles([goodWindow, failingWindow]) {
            await getCachedWindowTitle(goodWindow)
        }
        await waitForWorkspaceSidebarWindowTitleRefreshForTests()

        XCTAssertEqual(cachedWindowTitle(for: goodWindow), "Loaded")
        XCTAssertNil(cachedWindowTitle(for: failingWindow))
        XCTAssertEqual(goodWindow.titleGetCount, 1)
        XCTAssertEqual(failingWindow.titleGetCount, 1)
        XCTAssertEqual(refreshCallbackCount, 1)
    }
}

private final class StubTitleWindow: Window {
    var stubTitle: String
    var titleGetCount: Int = 0
    var titleReadDelay: Duration?
    var throwsOnTitleRead = false
    private let probe: StubTitleReadProbe?
    private let titleReadLatch: AwaitableOneTimeBroadcastLatch?

    @MainActor
    init(
        id: UInt32,
        title: String,
        app: any AbstractApp = TestApp.shared,
        probe: StubTitleReadProbe? = nil,
        titleReadDelay: Duration? = nil,
        titleReadLatch: AwaitableOneTimeBroadcastLatch? = nil,
    ) {
        stubTitle = title
        self.probe = probe
        self.titleReadDelay = titleReadDelay ?? (probe == nil ? nil : .milliseconds(50))
        self.titleReadLatch = titleReadLatch
        super.init(id: id, app, lastFloatingSize: nil, parent: Workspace.get(byName: "cache-test"), adaptiveWeight: 1, index: INDEX_BIND_LAST)
    }

    override func closeAxWindow() {}

    @MainActor
    override var title: String {
        get async throws {
            titleGetCount += 1
            probe?.begin(app.pid)
            defer { probe?.end(app.pid) }
            if throwsOnTitleRead { throw StubTitleReadError.unavailable }
            if let titleReadDelay { try await Task.sleep(for: titleReadDelay) }
            if let titleReadLatch { try await titleReadLatch.await() }
            return stubTitle
        }
    }

    @MainActor override var isMacosFullscreen: Bool { get async throws { false } }
    @MainActor override var isMacosMinimized: Bool { get async throws { false } }
}

private enum StubTitleReadError: Error {
    case unavailable
}

private final class StubTitleApp: AbstractApp {
    let pid: Int32
    let rawAppBundleId: String?
    let name: String?
    let execPath: String? = nil
    let bundlePath: String? = nil

    init(pid: Int32) {
        self.pid = pid
        rawAppBundleId = "test.title-cache.\(pid)"
        name = rawAppBundleId
    }

    @MainActor
    func getFocusedWindow() async throws -> Window? { nil }
}

@MainActor
private final class StubTitleReadProbe {
    private var activeReadsByApp: [Int32: Int] = [:]
    private(set) var maximumReadsByApp: [Int32: Int] = [:]
    private(set) var maximumConcurrentApps = 0

    func begin(_ pid: Int32) {
        activeReadsByApp[pid, default: 0] += 1
        maximumReadsByApp[pid] = max(
            maximumReadsByApp[pid, default: 0],
            activeReadsByApp[pid, default: 0],
        )
        maximumConcurrentApps = max(
            maximumConcurrentApps,
            activeReadsByApp.values.count(where: { $0 > 0 }),
        )
    }

    func end(_ pid: Int32) {
        activeReadsByApp[pid, default: 0] -= 1
    }
}
