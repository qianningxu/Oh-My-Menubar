@testable import AppBundle
import Foundation
import XCTest

final class WindowLevelCacheTest: XCTestCase {
    @MainActor
    func testInventoryLoadRunsOffMainThread() async throws {
        let probe = WindowLevelInventoryProbe(inventories: [[11: .normalWindow]])
        let cache = WindowLevelCache(loadInventory: { @Sendable in probe.load() })

        let level = try await cache.windowLevel(for: 11)

        XCTAssertEqual(level, .normalWindow)
        XCTAssertEqual(probe.loadCount, 1)
        XCTAssertFalse(probe.didRunOnMainThread)
    }

    @MainActor
    func testConcurrentMissesShareOneInventoryLoad() async throws {
        let probe = WindowLevelInventoryProbe(
            inventories: [[11: .normalWindow]],
            blocksFirstLoad: true
        )
        defer { probe.releaseFirstLoad() }
        let cache = WindowLevelCache(loadInventory: { @Sendable in probe.load() })
        let first = Task { @MainActor in
            try await cache.windowLevel(for: 11)
        }

        let didStart = await waitUntil { probe.loadCount == 1 }
        XCTAssertTrue(didStart)
        let second = Task { @MainActor in
            try await cache.windowLevel(for: 12)
        }
        for _ in 0 ..< 20 {
            await Task.yield()
        }

        XCTAssertEqual(probe.loadCount, 1)
        probe.releaseFirstLoad()
        let firstLevel = try await first.value
        let secondLevel = try await second.value

        XCTAssertEqual(firstLevel, .normalWindow)
        XCTAssertNil(secondLevel)
        XCTAssertEqual(probe.loadCount, 1)
    }

    @MainActor
    func testCancelledWaiterDoesNotCancelSharedLoad() async throws {
        let probe = WindowLevelInventoryProbe(
            inventories: [[21: .alwaysOnTopWindow]],
            blocksFirstLoad: true
        )
        defer { probe.releaseFirstLoad() }
        let cache = WindowLevelCache(loadInventory: { @Sendable in probe.load() })
        let survivor = Task { @MainActor in
            try await cache.windowLevel(for: 21)
        }

        let didStart = await waitUntil { probe.loadCount == 1 }
        XCTAssertTrue(didStart)
        let cancelledWaiter = Task { @MainActor in
            do {
                _ = try await cache.windowLevel(for: 22)
                return false
            } catch is CancellationError {
                return true
            } catch {
                XCTFail("Unexpected error: \(error)")
                return false
            }
        }
        for _ in 0 ..< 20 {
            await Task.yield()
        }

        cancelledWaiter.cancel()
        let didCancel = await cancelledWaiter.value
        XCTAssertTrue(didCancel)
        XCTAssertEqual(probe.loadCount, 1)

        probe.releaseFirstLoad()
        let survivingLevel = try await survivor.value
        let cachedLevel = try await cache.windowLevel(for: 21)
        XCTAssertEqual(survivingLevel, .alwaysOnTopWindow)
        XCTAssertEqual(cachedLevel, .alwaysOnTopWindow)
        XCTAssertEqual(probe.loadCount, 1)
    }

    @MainActor
    func testFailedLoadKeepsPreviousCacheAndRetriesMisses() async throws {
        let probe = WindowLevelInventoryProbe(inventories: [
            [31: .normalWindow],
            nil,
            [32: .alwaysOnTopWindow],
        ])
        let cache = WindowLevelCache(loadInventory: { @Sendable in probe.load() })

        let initialLevel = try await cache.windowLevel(for: 31)
        let failedLevel = try await cache.windowLevel(for: 32)
        let retainedLevel = try await cache.windowLevel(for: 31)
        XCTAssertEqual(initialLevel, .normalWindow)
        XCTAssertNil(failedLevel)
        XCTAssertEqual(retainedLevel, .normalWindow)
        XCTAssertEqual(probe.loadCount, 2)

        let retriedLevel = try await cache.windowLevel(for: 32)
        XCTAssertEqual(retriedLevel, .alwaysOnTopWindow)
        XCTAssertEqual(probe.loadCount, 3)
    }

    @MainActor
    private func waitUntil(_ predicate: @MainActor () -> Bool) async -> Bool {
        for _ in 0 ..< 1_000 {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
    }
}

private final class WindowLevelInventoryProbe: @unchecked Sendable {
    typealias Inventory = WindowLevelCache.Inventory

    private let lock = NSLock()
    private let firstLoadGate = DispatchSemaphore(value: 0)
    private let inventories: [Inventory?]
    private let blocksFirstLoad: Bool
    private var didReleaseFirstLoad = false
    private var _loadCount = 0
    private var _didRunOnMainThread = false

    init(inventories: [Inventory?], blocksFirstLoad: Bool = false) {
        self.inventories = inventories
        self.blocksFirstLoad = blocksFirstLoad
    }

    var loadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _loadCount
    }

    var didRunOnMainThread: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _didRunOnMainThread
    }

    func load() -> Inventory? {
        lock.lock()
        _loadCount += 1
        let invocation = _loadCount
        _didRunOnMainThread = _didRunOnMainThread || Thread.isMainThread
        let inventory = invocation <= inventories.count ? inventories[invocation - 1] : nil
        lock.unlock()

        if blocksFirstLoad, invocation == 1 {
            firstLoadGate.wait()
        }
        return inventory
    }

    func releaseFirstLoad() {
        lock.lock()
        let shouldRelease = !didReleaseFirstLoad
        didReleaseFirstLoad = true
        lock.unlock()
        if shouldRelease {
            firstLoadGate.signal()
        }
    }
}
