@testable import AppBundle
import XCTest

final class MacAppWindowInventoryTest: XCTestCase {
    func testMatchingWindowIdentityIsUnchanged() {
        XCTAssertFalse(windowInventoryIdentityChanged(
            actualWindowIds: [10, 20],
            lastObservedWindowIds: [10, 20]
        ))
    }

    func testSameCountWithDifferentWindowIdentityIsChanged() {
        XCTAssertTrue(windowInventoryIdentityChanged(
            actualWindowIds: [10, 30],
            lastObservedWindowIds: [10, 20]
        ))
    }

    func testDifferentWindowCountIsChanged() {
        XCTAssertTrue(windowInventoryIdentityChanged(
            actualWindowIds: [10, 20, 30],
            lastObservedWindowIds: [10, 20]
        ))
    }

    func testUnavailableWindowIdentityDoesNotReportChange() {
        XCTAssertFalse(windowInventoryIdentityChanged(
            actualWindowIds: nil,
            lastObservedWindowIds: [10, 20]
        ))
    }

    func testMissingAccessibilityWindowDoesNotBlockCloseAfterTheCloseButtonIsUnavailable() {
        XCTAssertTrue(shouldGarbageCollectAfterFailedClose(isWindowStillExposed: false))
        XCTAssertFalse(shouldGarbageCollectAfterFailedClose(isWindowStillExposed: true))
        XCTAssertFalse(shouldGarbageCollectAfterFailedClose(isWindowStillExposed: nil))
    }
}
