@testable import AppBundle
import CoreGraphics
import XCTest

final class WindowTabReorderBoundaryTest: XCTestCase {
    func testInsertionSlotsStayCorrectAfterHorizontalScrolling() {
        let ids: [UInt32] = [1, 2, 3, 4]
        for scroll: CGFloat in [0, -104, -208] {
            let frames = Dictionary(uniqueKeysWithValues: ids.enumerated().map {
                ($0.element, CGRect(x: CGFloat($0.offset) * 104 + scroll, y: 0, width: 100, height: 32))
            })
            for source in ids.indices {
                for slot in 0...ids.count {
                    let result = tabReorderTargetIndexForFrames(
                        pointerXInViewport: CGFloat(slot) * 104 + scroll - 1,
                        tabOrder: ids, tabFramesById: frames, sourceIndex: source)
                    XCTAssertEqual(result, max(0, min(slot > source ? slot - 1 : slot, ids.count - 1)))
                }
            }
        }
    }

    func testMidpointIsTheThresholdAndMissingGeometryCannotCommit() {
        let frames: [UInt32: CGRect] = [
            1: CGRect(x: 0, y: 0, width: 100, height: 32),
            2: CGRect(x: 104, y: 0, width: 100, height: 32),
        ]
        XCTAssertEqual(tabReorderTargetIndexForFrames(
            pointerXInViewport: 153.9, tabOrder: [1, 2], tabFramesById: frames, sourceIndex: 0), 0)
        XCTAssertEqual(tabReorderTargetIndexForFrames(
            pointerXInViewport: 154, tabOrder: [1, 2], tabFramesById: frames, sourceIndex: 0), 1)
        XCTAssertNil(tabReorderTargetIndexForFrames(
            pointerXInViewport: 200, tabOrder: [1, 2, 3], tabFramesById: frames, sourceIndex: 0))
        XCTAssertNil(tabReorderTargetIndexForFrames(
            pointerXInViewport: 200, tabOrder: [1, 2], tabFramesById: frames, sourceIndex: nil))
    }
}
