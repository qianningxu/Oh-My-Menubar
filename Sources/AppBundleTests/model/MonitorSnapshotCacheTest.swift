@testable import AppBundle
import Foundation
import XCTest

final class MonitorSnapshotCacheTest: XCTestCase {
    func testValueIsCachedUntilInvalidated() {
        let cache = InvalidatableSnapshotCache<Int>()
        var loadCount = 0

        XCTAssertEqual(cache.value {
            loadCount += 1
            return loadCount
        }, 1)
        XCTAssertEqual(cache.value {
            loadCount += 1
            return loadCount
        }, 1)
        XCTAssertEqual(loadCount, 1)

        cache.invalidate()

        XCTAssertEqual(cache.value {
            loadCount += 1
            return loadCount
        }, 2)
        XCTAssertEqual(loadCount, 2)
    }

    func testInvalidationRejectsAnInFlightStaleValue() async {
        let cache = InvalidatableSnapshotCache<String>()
        let didStartLoading = DispatchSemaphore(value: 0)
        let mayFinishLoading = DispatchSemaphore(value: 0)
        let staleLoad = Task.detached {
            cache.value {
                didStartLoading.signal()
                mayFinishLoading.wait()
                return "stale"
            }
        }

        didStartLoading.wait()
        cache.invalidate()
        XCTAssertEqual(cache.value { "fresh" }, "fresh")
        mayFinishLoading.signal()

        let staleCallerResult = await staleLoad.value
        XCTAssertEqual(staleCallerResult, "fresh")
        XCTAssertEqual(cache.value { "unexpected" }, "fresh")
    }

    @MainActor
    func testMonitorOverridesBypassTheProductionMainHeightSnapshot() {
        let first = TestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "First",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1600, height: 900),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1600, height: 900),
            isMain: true,
        )
        let second = TestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Second",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1200),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1200),
            isMain: true,
        )
        defer { setMonitorsForTests(nil) }

        setMonitorsForTests([first])
        XCTAssertEqual(mainMonitorHeight, 900)
        XCTAssertEqual(normalizeAppKitScreenPoint(CGPoint(x: 40, y: 100)), CGPoint(x: 40, y: 800))

        setMonitorsForTests([second])
        XCTAssertEqual(mainMonitorHeight, 1200)
        XCTAssertEqual(normalizeAppKitScreenPoint(CGPoint(x: 40, y: 100)), CGPoint(x: 40, y: 1100))
    }
}
