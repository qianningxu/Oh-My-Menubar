@testable import AppBundle
import XCTest

final class WorkspaceSidebarHorizontalReorderPreviewTest: XCTestCase {
    func testPreviewKeepsUniqueSlotsAndPreservesNeighbourOrder() {
        let order = ["a", "b", "c", "d"]
        for source in order {
            for target in order where target != source {
                for after in [false, true] {
                    let offsets = workspaceSidebarHorizontalReorderSteps(
                        order: order, source: source,
                        placement: after ? .after(target) : .before(target))
                    let positions = order.enumerated().map { $0.offset + offsets[$0.element, default: 0] }
                    XCTAssertEqual(Set(positions), Set(order.indices))
                    let result = order.sorted {
                        order.firstIndex(of: $0)! + offsets[$0, default: 0]
                            < order.firstIndex(of: $1)! + offsets[$1, default: 0]
                    }
                    XCTAssertEqual(result.filter { $0 != source }, order.filter { $0 != source })
                    XCTAssertEqual(result.firstIndex(of: source)!, result.firstIndex(of: target)! + (after ? 1 : -1))
                }
            }
        }
    }

    func testMissingAndSelfTargetsDoNotShiftTabs() {
        for placement in [WorkspaceReorderPlacement.before("missing"), .after("a")] {
            XCTAssertTrue(workspaceSidebarHorizontalReorderSteps(
                order: ["a", "b"], source: "a", placement: placement).isEmpty)
        }
        XCTAssertTrue(workspaceSidebarHorizontalReorderSteps(
            order: ["a", "b"], source: "missing", placement: .after("a")).isEmpty)
    }
}
