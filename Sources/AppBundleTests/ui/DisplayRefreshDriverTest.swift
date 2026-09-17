@testable import AppBundle
import XCTest

final class DisplayRefreshDriverTest: XCTestCase {
    func testCoalescerKeepsLatestTimestampAndSchedulesOnce() throws {
        let coalescer = DisplayRefreshFrameCoalescer()

        let generation = try XCTUnwrap(coalescer.enqueue(timestamp: 1))
        XCTAssertNil(coalescer.enqueue(timestamp: 3))
        XCTAssertNil(coalescer.enqueue(timestamp: 2))

        XCTAssertEqual(coalescer.takeLatestTimestampOrFinish(generation: generation), 3)
        XCTAssertNil(coalescer.takeLatestTimestampOrFinish(generation: generation))
        XCTAssertNotNil(coalescer.enqueue(timestamp: 4))
    }

    func testCoalescerKeepsOneDeliveryOutstandingWhileDraining() throws {
        let coalescer = DisplayRefreshFrameCoalescer()

        let generation = try XCTUnwrap(coalescer.enqueue(timestamp: 1))
        XCTAssertEqual(coalescer.takeLatestTimestampOrFinish(generation: generation), 1)

        XCTAssertNil(coalescer.enqueue(timestamp: 2))
        XCTAssertEqual(coalescer.takeLatestTimestampOrFinish(generation: generation), 2)
        XCTAssertNil(coalescer.enqueue(timestamp: 3))
        XCTAssertEqual(coalescer.takeLatestTimestampOrFinish(generation: generation), 3)

        XCTAssertNil(coalescer.takeLatestTimestampOrFinish(generation: generation))
        XCTAssertNotNil(coalescer.enqueue(timestamp: 4))
    }

    func testResetRejectsOldLifecycleAndAllowsNewDelivery() throws {
        let coalescer = DisplayRefreshFrameCoalescer()
        let oldGeneration = try XCTUnwrap(coalescer.enqueue(timestamp: 1))

        coalescer.reset()
        let newGeneration = try XCTUnwrap(coalescer.enqueue(timestamp: 2))

        XCTAssertNil(coalescer.takeLatestTimestampOrFinish(generation: oldGeneration))
        XCTAssertEqual(coalescer.takeLatestTimestampOrFinish(generation: newGeneration), 2)
    }
}
