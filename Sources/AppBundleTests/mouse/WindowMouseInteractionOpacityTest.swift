@testable import AppBundle
import Foundation
import XCTest

final class WindowMouseInteractionOpacityTest: XCTestCase {
    @MainActor
    func testInventoryRefreshRunsOffMainActorAndPublishesAsynchronously() async {
        let probe = MouseInteractionInventoryProbe(blocksLoad: true)
        defer { probe.releaseLoad() }
        let inventory = MouseInteractionVisibleWindowInventoryCache(load: probe.load)
        var publishedWindowIds: Set<UInt32>?
        inventory.didRefresh = { publishedWindowIds = $0 }

        inventory.refreshIfNeeded()

        XCTAssertNil(publishedWindowIds)
        let didStart = await waitUntil { probe.didStart }
        XCTAssertTrue(didStart)
        XCTAssertFalse(probe.didRunOnMainThread)
        probe.releaseLoad()
        let didPublish = await waitUntil { publishedWindowIds != nil }
        XCTAssertTrue(didPublish)
        XCTAssertEqual(publishedWindowIds, [11, 12])
    }

    @MainActor
    func testInventoryRefreshCoalescesWhileLoadIsInFlight() async {
        let probe = MouseInteractionInventoryProbe(blocksLoad: true)
        defer { probe.releaseLoad() }
        let inventory = MouseInteractionVisibleWindowInventoryCache(load: probe.load)

        inventory.refreshIfNeeded()
        inventory.refreshIfNeeded()
        inventory.refreshIfNeeded()

        let didStart = await waitUntil { probe.didStart }
        XCTAssertTrue(didStart)
        XCTAssertEqual(probe.loadCount, 1)
        probe.releaseLoad()
        let didPublish = await waitUntil { inventory.freshWindowIds != nil }
        XCTAssertTrue(didPublish)
        inventory.refreshIfNeeded()
        XCTAssertEqual(probe.loadCount, 1)
    }

    @MainActor
    func testInvalidationDiscardsLateInventoryAndAllowsFreshReload() async {
        let probe = MouseInteractionInventoryProbe(blocksLoad: true)
        defer { probe.releaseLoad() }
        let inventory = MouseInteractionVisibleWindowInventoryCache(load: probe.load)
        var publishCount = 0
        inventory.didRefresh = { _ in publishCount += 1 }

        inventory.refreshIfNeeded()
        let didStart = await waitUntil { probe.didStart }
        XCTAssertTrue(didStart)
        inventory.invalidate()
        probe.releaseLoad()
        for _ in 0 ..< 20 {
            await Task.yield()
        }

        XCTAssertNil(inventory.freshWindowIds)
        XCTAssertEqual(publishCount, 0)

        inventory.refreshIfNeeded()
        let didReload = await waitUntil { probe.loadCount == 2 && inventory.freshWindowIds != nil }
        XCTAssertTrue(didReload)
        XCTAssertEqual(publishCount, 1)
    }

    @MainActor
    func testInventorySnapshotExpires() async {
        var now: TimeInterval = 10
        let inventory = MouseInteractionVisibleWindowInventoryCache(
            load: { [21] },
            now: { now }
        )

        inventory.refreshIfNeeded()
        let didPublish = await waitUntil { inventory.freshWindowIds == [21] }
        XCTAssertTrue(didPublish)
        now += MouseInteractionVisibleWindowInventoryCache.maximumSnapshotAge + 0.001

        XCTAssertNil(inventory.freshWindowIds)
    }

    @MainActor
    private func waitUntil(_ predicate: @MainActor () -> Bool) async -> Bool {
        for _ in 0 ..< 1_000 {
            if predicate() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
    }
}

private final class MouseInteractionInventoryProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let loadGate = DispatchSemaphore(value: 0)
    private let blocksLoad: Bool
    private var didReleaseLoad = false
    private var _didStart = false
    private var _didRunOnMainThread = false
    private var _loadCount = 0

    init(blocksLoad: Bool) {
        self.blocksLoad = blocksLoad
    }

    var didStart: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _didStart
    }

    var didRunOnMainThread: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _didRunOnMainThread
    }

    var loadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _loadCount
    }

    func load() -> Set<UInt32> {
        lock.lock()
        _didStart = true
        _didRunOnMainThread = Thread.isMainThread
        _loadCount += 1
        let invocation = _loadCount
        lock.unlock()
        if blocksLoad, invocation == 1 {
            loadGate.wait()
        }
        return [11, 12]
    }

    func releaseLoad() {
        lock.lock()
        let shouldRelease = !didReleaseLoad
        didReleaseLoad = true
        lock.unlock()
        if shouldRelease {
            loadGate.signal()
        }
    }
}
