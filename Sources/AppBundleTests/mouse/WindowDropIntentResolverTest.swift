@testable import AppBundle
import XCTest

final class WindowDropIntentResolverTest: XCTestCase {
    @MainActor
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testResolvesTopBandAsTabZone() {
        let resolution = resolve(point: CGPoint(x: 150, y: 115))
        XCTAssertEqual(resolution?.intent.zone, .tab)
        XCTAssertEqual(resolution?.intent.sourceWindowId, 1)
        XCTAssertEqual(resolution?.intent.targetWindowId, 2)
    }

    func testResolvesBodyZones() {
        XCTAssertEqual(resolve(point: CGPoint(x: 110, y: 210))?.intent.zone, .left)
        XCTAssertEqual(resolve(point: CGPoint(x: 290, y: 210))?.intent.zone, .right)
        XCTAssertEqual(resolve(point: CGPoint(x: 200, y: 160))?.intent.zone, .top)
        XCTAssertEqual(resolve(point: CGPoint(x: 200, y: 210))?.intent.zone, .middle)
        XCTAssertEqual(resolve(point: CGPoint(x: 200, y: 285))?.intent.zone, .bottom)
    }

    func testPreviewZonesUseFullTargetFrameAndActiveZone() {
        let resolution = resolve(point: CGPoint(x: 110, y: 210)).orDie()
        let zones = windowDropIntentPreviewZones(for: resolution)

        XCTAssertEqual(zones.count, 6)
        XCTAssertEqual(zones.filter(\.isActive).count, 1)
        assertRect(zones.first { $0.isActive }?.rect, x: 100, y: 100, width: 105, height: 210)
        assertRect(windowDropIntentActivePreviewRect(for: resolution), x: 100, y: 100, width: 105, height: 210)
        assertRect(zones.first?.rect, x: 100, y: 100, width: 105, height: 210)
    }

    func testPreviewZonesIncludeStackAndSwapTargets() {
        let top = resolve(point: CGPoint(x: 150, y: 115)).orDie()
        let middle = resolve(point: CGPoint(x: 200, y: 210)).orDie()

        let topZones = windowDropIntentPreviewZones(for: top)
        let middleZones = windowDropIntentPreviewZones(for: middle)

        XCTAssertEqual(topZones.count, 6)
        XCTAssertEqual(middleZones.count, 6)
        XCTAssertEqual(topZones.filter(\.isActive).singleOrNil()?.style, .tabInsert)
        XCTAssertEqual(middleZones.filter(\.isActive).singleOrNil()?.style, .swap)
    }

    func testRejectsSourceAsTargetAndOutsidePointer() {
        let frame = Rect(topLeftX: 100, topLeftY: 100, width: 210, height: 210)
        XCTAssertNil(WindowDropIntentResolver().resolve(
            sourceWindowId: 1,
            targetWindowId: 1,
            pointer: CGPoint(x: 150, y: 150),
            targetFrame: frame,
        ))
        XCTAssertNil(WindowDropIntentResolver().resolve(
            sourceWindowId: 1,
            targetWindowId: 2,
            pointer: CGPoint(x: 99, y: 150),
            targetFrame: frame,
        ))
    }

    @MainActor
    func testTopTabAndCenterBodyDropsProduceTabStackAndSwapDestinations() {
        let workspace = Workspace.get(byName: "drag")
        let root = workspace.rootTilingContainer
        let source = TestWindow.new(id: 1, parent: root)
        let target = TestWindow.new(id: 2, parent: root)
        target.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 100, topLeftY: 100, width: 210, height: 210)
        config.windowTabs.enabled = true

        let topResolution = resolve(point: CGPoint(x: 150, y: 115)).orDie()
        let centerResolution = resolve(point: CGPoint(x: 200, y: 210)).orDie()

        let topDestination = destinationFromWindowDropIntent(
            topResolution,
            sourceWindow: source,
            targetWindow: target,
            mouseLocation: CGPoint(x: 150, y: 115),
            subject: .window,
            detachOrigin: .window,
        )
        let centerDestination = destinationFromWindowDropIntent(
            centerResolution,
            sourceWindow: source,
            targetWindow: target,
            mouseLocation: CGPoint(x: 200, y: 210),
            subject: .window,
            detachOrigin: .window,
        )

        XCTAssertEqual(topDestination?.kind, .tabStack(targetWindowId: target.windowId))
        XCTAssertEqual(topDestination?.dropIntentOverlay?.activeZone, .tab)
        XCTAssertEqual(centerDestination?.kind, .swap(targetWindowId: target.windowId))
        XCTAssertEqual(centerDestination?.dropIntentOverlay?.activeZone, .middle)
    }

    @MainActor
    func testStackedWindowCenterDropIsNeutralAndDoesNotSwap() {
        let workspace = Workspace.get(byName: "drag")
        let root = workspace.rootTilingContainer
        let source = TestWindow.new(id: 1, parent: root)
        let target = TestWindow.new(id: 2, parent: root)
        target.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 100, topLeftY: 100, width: 210, height: 210)
        let resolution = resolve(point: CGPoint(x: 200, y: 210)).orDie()

        let destination = destinationFromWindowDropIntent(
            resolution,
            sourceWindow: source,
            targetWindow: target,
            mouseLocation: CGPoint(x: 200, y: 210),
            subject: .group,
            detachOrigin: .window,
        )

        XCTAssertEqual(destination?.kind, .sidebarHover)
        XCTAssertNil(destination?.dropIntentOverlay?.activeZone)
        XCTAssertTrue(destination?.previewZones.allSatisfy { !$0.isActive } ?? false)
    }

    @MainActor
    func testEdgeDropsStillProduceSplitDestinations() {
        let workspace = Workspace.get(byName: "drag")
        let root = workspace.rootTilingContainer
        let source = TestWindow.new(id: 1, parent: root)
        let target = TestWindow.new(id: 2, parent: root)
        target.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 100, topLeftY: 100, width: 210, height: 210)
        let resolution = resolve(point: CGPoint(x: 110, y: 210)).orDie()

        let destination = destinationFromWindowDropIntent(
            resolution,
            sourceWindow: source,
            targetWindow: target,
            mouseLocation: CGPoint(x: 110, y: 210),
            subject: .window,
            detachOrigin: .window,
        )

        XCTAssertEqual(destination?.kind, .stackSplit(targetWindowId: target.windowId, position: .left))
    }

    @MainActor
    func testEdgeDropCopyUsesSplitLanguage() {
        let workspace = Workspace.get(byName: "drag")
        let root = workspace.rootTilingContainer
        let source = TestWindow.new(id: 1, parent: root)
        let target = TestWindow.new(id: 2, parent: root)
        target.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 100, topLeftY: 100, width: 210, height: 210)
        let resolution = resolve(point: CGPoint(x: 110, y: 210)).orDie()

        let destination = destinationFromWindowDropIntent(
            resolution,
            sourceWindow: source,
            targetWindow: target,
            mouseLocation: CGPoint(x: 110, y: 210),
            subject: .window,
            detachOrigin: .window,
        )

        XCTAssertEqual(destination?.title, "Split Left")
        XCTAssertEqual(destination?.subtitle, "Drop to split this tile and place the dragged item on the left")
    }

    @MainActor
    func testCrossWorkspaceCenterBodyDropProducesNoDestination() {
        let sourceWorkspace = Workspace.get(byName: "source")
        let source = TestWindow.new(id: 1, parent: sourceWorkspace.rootTilingContainer)
        _ = source.focusWindow()
        let targetWorkspace = Workspace.get(byName: "target")
        targetWorkspace.markAsAutomaticallyNamed()
        targetWorkspace.seedMonitorIfNeeded(mainMonitor)
        XCTAssertTrue(mainMonitor.setActiveWorkspace(targetWorkspace))

        let destination = currentWindowDragIntentDestination(
            sourceWindow: source,
            mouseLocation: mainMonitor.visibleRect.center,
            subject: .window,
            detachOrigin: .window,
        )

        XCTAssertNil(destination)
    }

    @MainActor
    func testCrossWorkspaceEdgeDropStillProducesDirectionalMove() {
        let sourceWorkspace = Workspace.get(byName: "source")
        let source = TestWindow.new(id: 1, parent: sourceWorkspace.rootTilingContainer)
        _ = source.focusWindow()
        let targetWorkspace = Workspace.get(byName: "target")
        targetWorkspace.markAsAutomaticallyNamed()
        targetWorkspace.seedMonitorIfNeeded(mainMonitor)
        XCTAssertTrue(mainMonitor.setActiveWorkspace(targetWorkspace))
        let targetFrame = mainMonitor.visibleRectPaddedByOuterGaps
        let mouseLocation = CGPoint(x: targetFrame.minX + 4, y: targetFrame.center.y)

        let destination = currentWindowDragIntentDestination(
            sourceWindow: source,
            mouseLocation: mouseLocation,
            subject: .window,
            detachOrigin: .window,
        )

        XCTAssertEqual(destination?.kind, .moveToWorkspaceZone(workspaceName: targetWorkspace.name, zone: .left))
        XCTAssertEqual(destination?.title, "Move Left")
    }

    private func resolve(point: CGPoint) -> WindowDropIntentResolution? {
        WindowDropIntentResolver().resolve(
            sourceWindowId: 1,
            targetWindowId: 2,
            pointer: point,
            targetFrame: Rect(topLeftX: 100, topLeftY: 100, width: 210, height: 210),
        )
    }

    private func assertRect(
        _ rect: Rect?,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let rect else {
            XCTFail("Expected rect", file: file, line: line)
            return
        }
        XCTAssertEqual(rect.topLeftX, x, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(rect.topLeftY, y, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(rect.width, width, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(rect.height, height, accuracy: 0.0001, file: file, line: line)
    }
}
