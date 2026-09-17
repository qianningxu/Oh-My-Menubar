@testable import AppBundle
import AppKit
import Common
import XCTest

final class AxRefreshFastPathTest: XCTestCase {
    @MainActor
    func testFocusedWindowChangedSkipsFullRefreshBarrier() async throws {
        let (first, second) = setUpFocusScenario()
        var refreshCount = 0
        var normalizeCount = 0
        setBlockingRefreshOverridesForTests(
            refresh: { refreshCount += 1 },
            normalizeLayoutReason: { normalizeCount += 1 }
        )

        _ = first.focusWindow()
        TestApp.shared.focusedWindow = second

        try await runRefreshSessionBlocking(.ax(kAXFocusedWindowChangedNotification as String))

        XCTAssertEqual(focus.windowOrNil?.windowId, second.windowId)
        XCTAssertEqual(refreshCount, 0)
        XCTAssertEqual(normalizeCount, 0)
    }

    @MainActor
    func testAppActivationSkipsFullRefreshBarrier() async throws {
        let (first, second) = setUpFocusScenario()
        var refreshCount = 0
        var normalizeCount = 0
        setBlockingRefreshOverridesForTests(
            refresh: { refreshCount += 1 },
            normalizeLayoutReason: { normalizeCount += 1 }
        )

        _ = first.focusWindow()
        TestApp.shared.focusedWindow = second

        try await runRefreshSessionBlocking(.globalObserver(NSWorkspace.didActivateApplicationNotification.rawValue))

        XCTAssertEqual(focus.windowOrNil?.windowId, second.windowId)
        XCTAssertEqual(refreshCount, 0)
        XCTAssertEqual(normalizeCount, 0)
    }

    func testFocusOnlyEventsCanReuseLastAppliedWindowFrames() {
        XCTAssertTrue(RefreshSessionEvent.ax(kAXFocusedWindowChangedNotification as String).canReuseLastAppliedWindowFrames)
        XCTAssertTrue(RefreshSessionEvent.globalObserver(NSWorkspace.didActivateApplicationNotification.rawValue).canReuseLastAppliedWindowFrames)
        XCTAssertTrue(RefreshSessionEvent.workspaceSidebarWidthChanged.canReuseLastAppliedWindowFrames)
        XCTAssertFalse(RefreshSessionEvent.ax(kAXMovedNotification as String).canReuseLastAppliedWindowFrames)
    }

    func testWindowCreatedEventUsesTargetedRefreshPlan() {
        let event = RefreshSessionEvent.axWindowCreated(pid: 42)

        XCTAssertTrue(event.isAxWindowCreated)
        XCTAssertEqual(event.axWindowCreatedSourcePid, 42)
        XCTAssertTrue(event.requiresWindowRefreshBarrier)
        XCTAssertTrue(event.requiresLayoutReasonNormalization)
    }

    @MainActor
    func testSidebarWidthChangeSkipsWindowRefreshBarriers() async throws {
        _ = setUpFocusScenario()
        var refreshCount = 0
        var normalizeCount = 0
        setBlockingRefreshOverridesForTests(
            refresh: { refreshCount += 1 },
            normalizeLayoutReason: { normalizeCount += 1 }
        )

        try await runRefreshSessionBlocking(.workspaceSidebarWidthChanged)

        XCTAssertEqual(refreshCount, 0)
        XCTAssertEqual(normalizeCount, 0)
    }

    @MainActor
    func testSidebarWidthChangeDoesNotReplaceAnActiveFullRefresh() async throws {
        setUpWorkspacesForTests()
        var refreshContinuation: CheckedContinuation<Void, Never>?
        var scheduledEvents: [String] = []
        setScheduledRefreshOverrideForTests { event, _ in
            scheduledEvents.append(event.description)
            await withCheckedContinuation { refreshContinuation = $0 }
        }
        defer {
            refreshContinuation?.resume()
            setScheduledRefreshOverrideForTests(nil)
        }

        scheduleRefreshSession(.menuBarButton)
        while refreshContinuation == nil {
            await Task.yield()
        }

        scheduleRefreshSession(.workspaceSidebarWidthChanged)
        await Task.yield()
        XCTAssertEqual(scheduledEvents, [RefreshSessionEvent.menuBarButton.description])

        refreshContinuation?.resume()
        refreshContinuation = nil
        try await waitForScheduledRefreshForTests()
    }

    func testWindowInventoryActivityIncludesLifecycleAndFocusNotifications() {
        XCTAssertTrue(shouldNoteWindowInventoryActivity(forAxNotification: kAXWindowCreatedNotification as String))
        XCTAssertTrue(shouldNoteWindowInventoryActivity(forAxNotification: kAXUIElementDestroyedNotification as String))
        XCTAssertTrue(shouldNoteWindowInventoryActivity(forAxNotification: kAXFocusedWindowChangedNotification as String))
        XCTAssertFalse(shouldNoteWindowInventoryActivity(forAxNotification: kAXMovedNotification as String))
    }

    @MainActor
    func testWindowCreatedStillRunsFullRefreshBarrier() async throws {
        _ = setUpFocusScenario()
        var refreshCount = 0
        var normalizeCount = 0
        setBlockingRefreshOverridesForTests(
            refresh: { refreshCount += 1 },
            normalizeLayoutReason: { normalizeCount += 1 }
        )

        try await runRefreshSessionBlocking(.ax(kAXWindowCreatedNotification as String))

        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(normalizeCount, 1)
    }

    @MainActor
    func testWindowDestroyedStillRunsFullRefreshBarrier() async throws {
        _ = setUpFocusScenario()
        var refreshCount = 0
        var normalizeCount = 0
        setBlockingRefreshOverridesForTests(
            refresh: { refreshCount += 1 },
            normalizeLayoutReason: { normalizeCount += 1 }
        )

        try await runRefreshSessionBlocking(.ax(kAXUIElementDestroyedNotification as String))

        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(normalizeCount, 1)
    }

    @MainActor
    func testWindowInventoryReconciliationRunsFullRefreshBarrier() async throws {
        _ = setUpFocusScenario()
        var refreshCount = 0
        var normalizeCount = 0
        setBlockingRefreshOverridesForTests(
            refresh: { refreshCount += 1 },
            normalizeLayoutReason: { normalizeCount += 1 }
        )

        try await runRefreshSessionBlocking(.windowInventoryReconciliation)

        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(normalizeCount, 1)
    }

    @MainActor
    func testWindowInventoryReconciliationSchedulesWhenIdle() async throws {
        setUpWorkspacesForTests()
        var scheduledEvents: [String] = []
        setScheduledRefreshOverrideForTests { event, _ in
            scheduledEvents.append(event.description)
        }
        defer { setScheduledRefreshOverrideForTests(nil) }

        XCTAssertTrue(scheduleWindowInventoryReconciliationIfIdle())
        try await waitForScheduledRefreshForTests()

        XCTAssertEqual(scheduledEvents, [RefreshSessionEvent.windowInventoryReconciliation.description])
    }

    @MainActor
    func testWindowInventoryReconciliationDoesNotReplaceActiveRefresh() async throws {
        setUpWorkspacesForTests()
        var continuation: CheckedContinuation<Void, Never>?
        setScheduledRefreshOverrideForTests { _, _ in
            await withCheckedContinuation { continuation = $0 }
        }
        defer { setScheduledRefreshOverrideForTests(nil) }

        scheduleRefreshSession(.menuBarButton)
        while continuation == nil {
            await Task.yield()
        }

        XCTAssertFalse(scheduleWindowInventoryReconciliationIfIdle())
        continuation?.resume()
        try await waitForScheduledRefreshForTests()
    }

    @MainActor
    func testCancelledScheduledRefreshRemainsActiveUntilItUnwinds() async throws {
        _ = setUpFocusScenario()
        var refreshContinuation: CheckedContinuation<Void, Never>?
        var didFinishScheduledOverride = false
        setScheduledRefreshOverrideForTests { _, _ in
            await withCheckedContinuation { refreshContinuation = $0 }
            didFinishScheduledOverride = true
        }
        defer {
            refreshContinuation?.resume()
            setScheduledRefreshOverrideForTests(nil)
        }

        scheduleRefreshSession(.menuBarButton)
        while refreshContinuation == nil {
            await Task.yield()
        }

        try await runLightSession(.menuBarButton, .forceRun, shouldSchedulePostRefresh: false) {}

        XCTAssertFalse(scheduleWindowInventoryReconciliationIfIdle())
        refreshContinuation?.resume()
        refreshContinuation = nil
        while !didFinishScheduledOverride || !refreshSessionsAreIdle() {
            await Task.yield()
        }

        setScheduledRefreshOverrideForTests { _, _ in }
        XCTAssertTrue(scheduleWindowInventoryReconciliationIfIdle())
        try await waitForScheduledRefreshForTests()
    }

    @MainActor
    func testWindowInventoryReconciliationWaitsForDirectBlockingRefresh() async throws {
        _ = setUpFocusScenario()
        var refreshContinuation: CheckedContinuation<Void, Never>?
        var scheduledEvents: [String] = []
        setBlockingRefreshOverridesForTests(
            refresh: {
                await withCheckedContinuation { refreshContinuation = $0 }
            },
            normalizeLayoutReason: {}
        )
        setScheduledRefreshOverrideForTests { event, _ in
            scheduledEvents.append(event.description)
        }
        defer {
            refreshContinuation?.resume()
            setScheduledRefreshOverrideForTests(nil)
            setBlockingRefreshOverridesForTests()
        }

        let blockingRefresh = Task { @MainActor in
            try await runRefreshSessionBlocking(.windowInventoryReconciliation, layoutWorkspaces: false)
        }
        while refreshContinuation == nil {
            await Task.yield()
        }

        XCTAssertFalse(scheduleWindowInventoryReconciliationIfIdle())
        refreshContinuation?.resume()
        refreshContinuation = nil
        try await blockingRefresh.value

        XCTAssertTrue(scheduleWindowInventoryReconciliationIfIdle())
        try await waitForScheduledRefreshForTests()
        XCTAssertEqual(scheduledEvents, [RefreshSessionEvent.windowInventoryReconciliation.description])
    }

    @MainActor
    func testWindowInventoryReconciliationWaitsForOuterLightRefreshAfterNestedBlockingRefresh() async throws {
        _ = setUpFocusScenario()
        var refreshContinuation: CheckedContinuation<Void, Never>?
        var didRejectAfterNestedRefresh = false
        setBlockingRefreshOverridesForTests(
            refresh: {
                await withCheckedContinuation { refreshContinuation = $0 }
            },
            normalizeLayoutReason: {}
        )
        defer {
            refreshContinuation?.resume()
            setBlockingRefreshOverridesForTests()
        }

        let lightRefresh = Task { @MainActor in
            try await runLightSession(.menuBarButton, .forceRun, shouldSchedulePostRefresh: false) {
                try await runRefreshSessionBlocking(.windowInventoryReconciliation, layoutWorkspaces: false)
                didRejectAfterNestedRefresh = !scheduleWindowInventoryReconciliationIfIdle()
            }
        }
        while refreshContinuation == nil {
            await Task.yield()
        }

        XCTAssertFalse(scheduleWindowInventoryReconciliationIfIdle())
        refreshContinuation?.resume()
        refreshContinuation = nil
        try await lightRefresh.value
        XCTAssertTrue(didRejectAfterNestedRefresh)
    }

    @MainActor
    func testNativeMinimizeRefreshKeepsActiveAdjacentEmptyWorkspaceForReuse() async throws {
        setUpWorkspacesForTests()
        TrayMenuModel.shared.isEnabled = true
        config.automaticallyUnhideMacosHiddenApps = true
        appForTests = TestApp.shared
        setBlockingRefreshOverridesForTests(refresh: {})

        let survivingWorkspace = Workspace.get(byName: "1")
        survivingWorkspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 1, parent: survivingWorkspace.rootTilingContainer)

        let minimizedWorkspace = Workspace.get(byName: "2")
        minimizedWorkspace.markAsAutomaticallyNamed()
        let minimizedWindow = TestWindow.new(id: 2, parent: minimizedWorkspace.rootTilingContainer)
        _ = minimizedWorkspace.focusWorkspace()
        TestApp.shared.focusedWindow = minimizedWindow
        minimizedWindow.nativeIsMacosMinimized = true

        try await runRefreshSessionBlocking(.ax("native-minimize"), layoutWorkspaces: false)

        XCTAssertNotNil(Workspace.existing(byName: minimizedWorkspace.name))
        XCTAssertEqual(workspaceDefaultDisplayName(minimizedWorkspace.name), "Tab 2")
        XCTAssertTrue(
            getOrCreateAdjacentBlankWorkspace(
                projectId: minimizedWorkspace.projectId,
                monitor: minimizedWorkspace.workspaceMonitor,
            ) === minimizedWorkspace
        )
        XCTAssertTrue(minimizedWindow.parent === macosMinimizedWindowsContainer)
        XCTAssertEqual(minimizedWindow.layoutReason, .macos(prevParentKind: .tilingContainer, prevWorkspaceName: nil))
    }

    @MainActor
    private func setUpFocusScenario() -> (TestWindow, TestWindow) {
        setUpWorkspacesForTests()
        TrayMenuModel.shared.isEnabled = true
        appForTests = TestApp.shared
        let workspace = focus.workspace
        let first = TestWindow.new(
            id: 1,
            parent: workspace.rootTilingContainer,
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 800, height: 600)
        )
        let second = TestWindow.new(
            id: 2,
            parent: workspace.rootTilingContainer,
            rect: Rect(topLeftX: 800, topLeftY: 0, width: 800, height: 600)
        )
        return (first, second)
    }
}
