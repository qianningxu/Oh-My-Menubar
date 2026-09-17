@testable import AppBundle
import AppKit
import XCTest

@MainActor
final class NativeLiveResizeGeometryTest: XCTestCase {
    func testExpiredResizeGateLeavesLaterPointerEventsUnchanged() {
        var state = ResizePointerGateState(session: 7, windowId: 42, expiresAt: 10,
            bounds: ResizePointerBounds(minX: 100, maxX: 500))
        XCTAssertEqual(state.constrain(CGPoint(x: 800, y: 30), now: 9), CGPoint(x: 500, y: 30))
        XCTAssertEqual(state.constrain(CGPoint(x: 800, y: 30), now: 10), CGPoint(x: 800, y: 30))
        XCTAssertNil(state.session)
        XCTAssertNil(state.windowId)
        XCTAssertEqual(state.constrain(CGPoint(x: 20, y: 30), now: 11), CGPoint(x: 20, y: 30))
    }

    func testSameWindowStartsANewResizeSessionIdentity() {
        let first = WindowMouseInteractionDriver.ResizeSession(windowId: 42)
        let next = WindowMouseInteractionDriver.ResizeSession(windowId: 42)
        XCTAssertNotEqual(first, next)
        XCTAssertEqual(first, first)
    }

    func testResizePointerIsClampedToTheSharedSplitLimits() {
        let bounds = ResizePointerBounds(minX: 100, maxX: 500, minY: 200, maxY: 700)

        XCTAssertEqual(constrainResizePointer(CGPoint(x: 50, y: 900), to: bounds), CGPoint(x: 100, y: 700))
        XCTAssertEqual(constrainResizePointer(CGPoint(x: 300, y: 400), to: bounds), CGPoint(x: 300, y: 400))
        XCTAssertEqual(constrainResizePointer(CGPoint(x: 800, y: 100), to: bounds), CGPoint(x: 500, y: 200))
    }

    func testLiveResizeMovesLeadingEdgeBeforeChangingSize() {
        let current = Rect(topLeftX: 500, topLeftY: 100, width: 700, height: 600)

        XCTAssertEqual(
            nativeLiveResizeFrameWriteOrder(
                from: current,
                to: Rect(topLeftX: 400, topLeftY: 100, width: 800, height: 600)),
            .positionThenSize)
        XCTAssertEqual(
            nativeLiveResizeFrameWriteOrder(
                from: current,
                to: Rect(topLeftX: 600, topLeftY: 100, width: 600, height: 600)),
            .sizeThenPosition)
    }

    func testNativeEdgeResizeCannotBecomeAMove() {
        XCTAssertTrue(shouldIgnoreMovedObsForManagedWindowDragSession(
            observedWindowId: 1, currentWindowId: 1, kind: .resize,
            subject: .window, detachOrigin: .window, startedInSidebar: false))
        XCTAssertFalse(shouldIgnoreMovedObsForManagedWindowDragSession(
            observedWindowId: 2, currentWindowId: 1, kind: .resize,
            subject: .window, detachOrigin: .window, startedInSidebar: false))
        XCTAssertFalse(shouldIgnoreMovedObsForManagedWindowDragSession(
            observedWindowId: 1, currentWindowId: 1, kind: .move,
            subject: .window, detachOrigin: .window, startedInSidebar: false))
    }

    func testTranslationAndResizeAreDistinguished() {
        let before = Rect(topLeftX: 100, topLeftY: 100, width: 500, height: 400)
        XCTAssertFalse(nativeWindowSizeChangedForResize(from: before,
            to: Rect(topLeftX: 110, topLeftY: 90, width: 500, height: 400)))
        for delta: CGFloat in [-30, 30] {
            XCTAssertTrue(nativeWindowSizeChangedForResize(from: before,
                to: Rect(topLeftX: 100 - delta, topLeftY: 100, width: 500 + delta, height: 400)))
            XCTAssertTrue(nativeWindowSizeChangedForResize(from: before,
                to: Rect(topLeftX: 100, topLeftY: 100 - delta, width: 500, height: 400 + delta)))
        }
    }

    func testLiveStackContentUsesTheSameGeometryAsNormalLayout() {
        for width: CGFloat in [200, 500, 1200] {
            for height: CGFloat in [150, 400, 900] {
                let content = Rect(topLeftX: 100, topLeftY: 100, width: width, height: height)
                let outer = windowTabGroupFrameRect(forActiveWindowContentRect: content)
                let live = liveResizeWindowContentRect(groupRect: outer, isTabGroup: true)
                XCTAssertEqual(live.topLeftX, content.topLeftX)
                XCTAssertEqual(live.topLeftY, content.topLeftY)
                XCTAssertEqual(live.width, content.width)
                XCTAssertEqual(live.height, content.height)
            }
        }
    }

    func testNativeClampRaisesOnlyTheRejectedMinimumDimension() {
        XCTAssertEqual(learnedMinimumSizeAfterNativeClamp(
            current: CGSize(width: 200, height: 150),
            requested: CGSize(width: 300, height: 300),
            observed: CGSize(width: 420, height: 300),
            tolerance: 0.5
        ), CGSize(width: 420, height: 150))
        XCTAssertNil(learnedMinimumSizeAfterNativeClamp(
            current: CGSize(width: 420, height: 150),
            requested: CGSize(width: 420, height: 300),
            observed: CGSize(width: 420.4, height: 300),
            tolerance: 0.5
        ))
    }

    func testNativeClampRequiresAChangedStableFrameAtARequestedEdge() {
        let initial = Rect(topLeftX: 700, topLeftY: 100, width: 1000, height: 800)
        let requested = Rect(topLeftX: 900, topLeftY: 100, width: 800, height: 800)
        let clamped = Rect(topLeftX: 900, topLeftY: 100, width: 850, height: 800)

        XCTAssertFalse(nativeLiveResizeClampIsConfirmed(
            initial: initial, requested: requested, previous: nil,
            observed: initial, tolerance: 0.5))
        XCTAssertFalse(nativeLiveResizeClampIsConfirmed(
            initial: initial, requested: requested, previous: initial,
            observed: initial, tolerance: 0.5))
        XCTAssertFalse(nativeLiveResizeClampIsConfirmed(
            initial: initial, requested: requested, previous: initial,
            observed: clamped, tolerance: 0.5))
        XCTAssertTrue(nativeLiveResizeClampIsConfirmed(
            initial: initial, requested: requested, previous: clamped,
            observed: clamped, tolerance: 0.5))

        let trailingEdgeClamp = Rect(topLeftX: 800, topLeftY: 100, width: 900, height: 800)
        XCTAssertTrue(nativeLiveResizeClampIsConfirmed(
            initial: initial, requested: requested, previous: trailingEdgeClamp,
            observed: trailingEdgeClamp, tolerance: 0.5))
    }
}
