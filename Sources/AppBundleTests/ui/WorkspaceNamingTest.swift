@testable import AppBundle
import AppKit
import Common
import SwiftUI
import XCTest

private final class WorkspaceRenameTestState {
    var text = ""
    var commitCount = 0
    var cancelCount = 0
}

struct WorkspaceNamingTestMonitor: Monitor {
    let monitorAppKitNsScreenScreensId: Int
    let name: String
    let rect: Rect
    let visibleRect: Rect
    let isMain: Bool

    var width: CGFloat { rect.width }
    var height: CGFloat { rect.height }
}

@MainActor
final class WorkspaceNamingTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testSidebarTabRenameKeepsEditingThroughTransientFocusChanges() {
        let state = WorkspaceRenameTestState()
        let coordinator = WorkspaceSidebarProjectRenameTextField.Coordinator(
            text: Binding(get: { state.text }, set: { state.text = $0 }),
            onCommit: { state.commitCount += 1 },
            onCancel: { state.cancelCount += 1 },
            onPanelReady: { _, _ in }
        )
        let field = NSTextField(string: "Remembered")

        coordinator.controlTextDidEndEditing(Notification(
            name: NSControl.textDidEndEditingNotification,
            object: field
        ))

        XCTAssertEqual(state.text, "Remembered")
        XCTAssertEqual(state.commitCount, 0)
        XCTAssertEqual(state.cancelCount, 0)
    }

    func testNativeSidebarRenameDoesNotFallBackToPanelKeyForwardingAfterViewReplacement() {
        let state = WorkspaceRenameTestState()
        let panel = WorkspaceSidebarPanel.shared
        var field: NSTextField? = NSTextField(string: "Original")

        panel.beginInlineTextEditing(
            cancelsOnPointerExit: false,
            editingView: field,
            onKeyDown: { key in
                if case .text(let inserted) = key {
                    state.text += inserted
                }
            }
        )

        XCTAssertTrue(panel.inlineTextEditingUsesNativeEditor)
        XCTAssertTrue(panel.inlineTextEditingView === field)
        XCTAssertNil(panel.inlineTextEditingKeyEventTap)

        field = nil
        XCTAssertNil(panel.inlineTextEditingView)
        XCTAssertTrue(panel.inlineTextEditingUsesNativeEditor)

        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        )!
        panel.keyDown(with: event)

        XCTAssertEqual(state.text, "")
        panel.endInlineTextEditing()
    }

    func testReconcilePreservesLabelForWorkspaceThatHasNotRestoredYet() {
        let restoringWorkspace = Workspace.get(byName: "restoring-workspace")
        config.workspaceSidebar.workspaceLabels["restoring-workspace"] = "Remembered"

        Workspace.reconcileWorkspaceState()

        XCTAssertNil(Workspace.existing(byName: restoringWorkspace.name))
        XCTAssertEqual(
            config.workspaceSidebar.workspaceLabels["restoring-workspace"],
            "Remembered"
        )
    }

    func testSanitizedWorkspaceSidebarHoveredWorkspaceNameClearsDeadWorkspaceReferences() {
        let sanitized = sanitizedWorkspaceSidebarHoveredWorkspaceName(
            visibleWorkspaceNames: ["live"],
            hoveredWorkspaceName: "dead",
        )

        XCTAssertNil(sanitized)
    }

    func testSanitizedWorkspaceSidebarHoveredWorkspaceNameKeepsLiveHoverState() {
        let sanitized = sanitizedWorkspaceSidebarHoveredWorkspaceName(
            visibleWorkspaceNames: ["live"],
            hoveredWorkspaceName: "live",
        )

        XCTAssertEqual(sanitized, "live")
    }

    func testTrayItemDisablesRawWorkspaceIconWhenDisplayNameIsCustom() {
        let renamedWorkspace = TrayItem(
            type: .workspace,
            name: "1",
            displayName: "Code",
            isActive: true,
            hasFullscreenWindows: false,
        )
        let plainWorkspace = TrayItem(
            type: .workspace,
            name: "1",
            displayName: "1",
            isActive: true,
            hasFullscreenWindows: false,
        )

        XCTAssertNil(renamedWorkspace.systemImageName)
        XCTAssertEqual(plainWorkspace.systemImageName, "1.square.fill")
    }

    func testAutomaticNumericWorkspaceDisplayNamesCompactLiveWorkspaceSet() {
        let first = Workspace.get(byName: "3")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 1, parent: first.rootTilingContainer)
        let second = Workspace.get(byName: "7")
        second.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 2, parent: second.rootTilingContainer)

        XCTAssertEqual(workspaceDisplayName(first.name), "Tab 1")
        XCTAssertEqual(workspaceDisplayName(second.name), "Tab 2")
    }

    func testAutomaticWorkspaceDisplayNamesFollowProjectOrderInsteadOfRawNameSort() {
        let first = Workspace.get(byName: "10")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 201, parent: first.rootTilingContainer)
        let second = Workspace.get(byName: "2")
        second.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 202, parent: second.rootTilingContainer)

        XCTAssertEqual(
            orderedUserFacingWorkspaces(in: first.projectId, focusedWorkspace: focus.workspace)
                .filter(\.usesAutomaticDisplayName)
                .map(\.name),
            ["10", "2"],
        )
        XCTAssertEqual(workspaceDisplayName(first.name), "Tab 1")
        XCTAssertEqual(workspaceDisplayName(second.name), "Tab 2")
    }

    func testSidebarTabTitleFollowsFocusedWindowInComposedLayout() async {
        let workspace = Workspace.get(byName: "composed")
        workspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 221, parent: workspace.rootTilingContainer)
        let focusedWindow = TestWindow.new(id: 222, parent: workspace.rootTilingContainer)
        _ = focusedWindow.focusWindow()

        let viewModels = await buildWorkspaceSidebarWorkspaceViewModels(
            currentFocus: focus,
            workspaceLabels: [:],
            availableMonitors: [mainMonitor],
        )

        let viewModel = viewModels.first { $0.name == workspace.name }
        XCTAssertEqual(viewModel?.tabSummary.title, "bobko.WinMux.test-app & 1 other")
        XCTAssertEqual(viewModel?.displayName, "bobko.WinMux.test-app & 1 other")
        XCTAssertNil(viewModel?.tabSummary.subtitle)
        XCTAssertEqual(viewModel?.tabSummary.windowCount, 2)
    }

    func testComposedTabTitleSummarizesApps() {
        XCTAssertEqual(
            workspaceSidebarComposedTabTitle(appNames: ["Xcode", "Safari"]),
            "Xcode & Safari"
        )
        XCTAssertEqual(
            workspaceSidebarComposedTabTitle(appNames: ["Xcode", "Safari", "Notes"]),
            "Xcode & 2 others"
        )
        XCTAssertEqual(
            workspaceSidebarComposedTabTitle(appNames: ["Safari", "Safari"]),
            "Safari & 1 other"
        )
    }

    func testComposedTabHeaderAlwaysShowsIndependentTabs() {
        XCTAssertTrue(workspaceSidebarShowsComposedTabHeader(
            isRenamingWorkspace: false,
            sidebarLabel: "",
            hasComposedTabs: true,
        ))
        XCTAssertTrue(workspaceSidebarShowsComposedTabHeader(
            isRenamingWorkspace: false,
            sidebarLabel: "Research",
            hasComposedTabs: true,
        ))
        XCTAssertTrue(workspaceSidebarShowsComposedTabHeader(
            isRenamingWorkspace: false,
            sidebarLabel: "   ",
            hasComposedTabs: true,
        ))
        XCTAssertFalse(workspaceSidebarShowsComposedTabHeader(
            isRenamingWorkspace: false,
            sidebarLabel: "Research",
            hasComposedTabs: false,
        ))
        XCTAssertFalse(workspaceSidebarShowsComposedTabHeader(
            isRenamingWorkspace: true,
            sidebarLabel: "",
            hasComposedTabs: true,
        ))
    }

    func testSidebarManualTabRenameOverridesFocusedWindowTitle() async {
        let workspace = Workspace.get(byName: "renamed")
        workspace.markAsAutomaticallyNamed()
        let focusedWindow = TestWindow.new(id: 223, parent: workspace.rootTilingContainer)
        _ = focusedWindow.focusWindow()

        let viewModels = await buildWorkspaceSidebarWorkspaceViewModels(
            currentFocus: focus,
            workspaceLabels: [workspace.name: "Build"],
            availableMonitors: [mainMonitor],
        )

        let viewModel = viewModels.first { $0.name == workspace.name }
        XCTAssertEqual(viewModel?.tabSummary.title, "Build")
        XCTAssertEqual(viewModel?.displayName, "Build")
        XCTAssertNil(viewModel?.tabSummary.subtitle)
        XCTAssertEqual(viewModel?.tabSummary.windowCount, 1)
    }

    func testReconcileRepairsMissingProjectWorkspaceIndex() {
        let first = Workspace.get(byName: "1")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 211, parent: first.rootTilingContainer)
        let second = Workspace.get(byName: "2")
        second.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 212, parent: second.rootTilingContainer)

        var folder = winMuxWorkspaceState.workspaceFoldersById[WorkspaceFolderId(first.projectId)].orDie()
        folder.workspaceOrder = [first.id]
        winMuxWorkspaceState.workspaceFoldersById[WorkspaceFolderId(first.projectId)] = folder

        Workspace.reconcileWorkspaceState()

        XCTAssertEqual(
            orderedUserFacingWorkspaces(in: first.projectId, focusedWorkspace: focus.workspace)
                .filter(\.usesAutomaticDisplayName)
                .map(\.name),
            ["1", "2"],
        )
        XCTAssertEqual(workspaceDisplayName(second.name), "Tab 2")
    }

    func testNextAutomaticWorkspaceRawNameReusesLowestNumericGap() {
        let first = Workspace.get(byName: "1")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 208, parent: first.rootTilingContainer)
        let thirdRaw = Workspace.get(byName: "3")
        thirdRaw.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 209, parent: thirdRaw.rootTilingContainer)

        XCTAssertEqual(nextSidebarCreatedWorkspaceName(), "2")
    }

    func testNextAutomaticWorkspaceRawNameSkipsNamesForcedToAnotherMonitor() {
        let main = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let secondary = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([main, secondary])
        config.workspaceToMonitorForceAssignment["1"] = [.sequenceNumber(2)]

        XCTAssertEqual(nextSidebarCreatedWorkspaceName(monitor: main), "2")
        XCTAssertEqual(nextSidebarCreatedWorkspaceName(monitor: secondary), "1")
    }

    func testAutomaticNumericWorkspaceDisplayNamesCompactWithoutRenamingWorkspaceIds() {
        let first = Workspace.get(byName: "1")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 6, parent: first.rootTilingContainer)
        let second = Workspace.get(byName: "3")
        second.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 7, parent: second.rootTilingContainer)

        Workspace.reconcileWorkspaceState()

        XCTAssertEqual(first.name, "1")
        XCTAssertEqual(second.name, "3")
        XCTAssertEqual(workspaceDisplayName(first.name), "Tab 1")
        XCTAssertEqual(workspaceDisplayName(second.name), "Tab 2")
        XCTAssertTrue(Workspace.existing(byName: "3") === second)
    }

    func testDeletingMiddleAutomaticWorkspaceCompactsNamesWithoutReorderingSurvivors() throws {
        let first = Workspace.get(byName: "10")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 203, parent: first.rootTilingContainer)
        let deleted = Workspace.get(byName: "2")
        deleted.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 204, parent: deleted.rootTilingContainer)
        let third = Workspace.get(byName: "7")
        third.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 205, parent: third.rootTilingContainer)

        try deleteWorkspaceForSidebar(workspaceName: deleted.name)

        XCTAssertNil(Workspace.existing(byName: deleted.name))
        XCTAssertEqual(
            orderedUserFacingWorkspaces(in: first.projectId, focusedWorkspace: focus.workspace)
                .filter(\.usesAutomaticDisplayName)
                .map(\.name),
            ["10", "7"],
        )
        XCTAssertEqual(workspaceDisplayName(first.name), "Tab 1")
        XCTAssertEqual(workspaceDisplayName(third.name), "Tab 2")
    }

    func testWorkspaceNameAfterCompactionUsesCurrentAutomaticName() throws {
        let deleted = Workspace.get(byName: "10")
        deleted.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 206, parent: deleted.rootTilingContainer)
        let survivor = Workspace.get(byName: "2")
        survivor.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 207, parent: survivor.rootTilingContainer)
        try deleteWorkspaceForSidebar(workspaceName: deleted.name)

        XCTAssertEqual(survivor.name, "2")
        XCTAssertEqual(workspaceDisplayName(survivor.name), "Tab 1")
        XCTAssertNil(config.workspaceSidebar.workspaceLabels[survivor.name])
    }

    func testAutomaticWorkspaceDisplayNameCompactionPreservesFocus() {
        let first = Workspace.get(byName: "1")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 8, parent: first.rootTilingContainer)
        let focused = Workspace.get(byName: "3")
        focused.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 9, parent: focused.rootTilingContainer)
        _ = focused.focusWorkspace()

        Workspace.reconcileWorkspaceState()

        XCTAssertEqual(focused.name, "3")
        XCTAssertEqual(workspaceDisplayName(focused.name), "Tab 2")
        XCTAssertTrue(focus.workspace === focused)
    }

    func testAutomaticDraftWorkspaceDisplayNamesCompactLiveWorkspaceSet() {
        let first = Workspace.get(byName: "__sidebar_draft_workspace_1")
        first.markAsSidebarManaged()
        _ = TestWindow.new(id: 3, parent: first.rootTilingContainer)
        let second = Workspace.get(byName: "__sidebar_draft_workspace_3")
        second.markAsSidebarManaged()
        _ = TestWindow.new(id: 4, parent: second.rootTilingContainer)

        XCTAssertEqual(workspaceDisplayName(first.name), "Tab 1")
        XCTAssertEqual(workspaceDisplayName(second.name), "Tab 2")
    }

    func testSidebarWorkspaceCreationUsesAutomaticWorkspaceName() {
        let first = Workspace.get(byName: "1")
        first.markAsAutomaticallyNamed()
        let window = TestWindow.new(id: 5, parent: first.rootTilingContainer)
        _ = first.focusWorkspace()

        XCTAssertTrue(createWorkspaceFromSidebarDrag(sourceNode: window, sourceWindow: window))
        XCTAssertNotNil(Workspace.existing(byName: "2"))
        XCTAssertNil(Workspace.existing(byName: "__sidebar_draft_workspace_1"))
        XCTAssertEqual(focus.workspace.name, "1")
    }

    func testAutomaticWorkspaceDisplayNamesAreMonitorLocalAcrossDisplays() {
        let main = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let secondary = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([main, secondary])

        let mainWorkspace = Workspace.get(byName: "1")
        mainWorkspace.markAsAutomaticallyNamed()
        mainWorkspace.seedMonitorIfNeeded(main)
        _ = TestWindow.new(id: 10, parent: mainWorkspace.rootTilingContainer)
        let secondaryWorkspace = Workspace.get(byName: "2")
        secondaryWorkspace.markAsAutomaticallyNamed()
        secondaryWorkspace.seedMonitorIfNeeded(secondary)
        _ = TestWindow.new(id: 11, parent: secondaryWorkspace.rootTilingContainer)

        XCTAssertEqual(workspaceDisplayName(mainWorkspace.name), "Tab 1")
        XCTAssertEqual(workspaceDisplayName(secondaryWorkspace.name), "Tab 1")
        XCTAssertEqual(mainWorkspace.projectId, workspaceProjectDefaultId)
        XCTAssertEqual(secondaryWorkspace.projectId, workspaceProjectDefaultId)
    }

    func testSidebarFoldersOwnSeparateTabDisplayIndexesWhenProjectsHardDisabled() {
        let defaultWorkspace = Workspace.get(byName: "1")
        defaultWorkspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 12, parent: defaultWorkspace.rootTilingContainer)
        let project = createWorkspaceProject()
        let projectWorkspace = Workspace.get(byName: nextSidebarCreatedWorkspaceName(projectId: project.id, monitor: mainMonitor))
        projectWorkspace.markAsAutomaticallyNamed()
        projectWorkspace.assignProject(project.id)
        projectWorkspace.seedMonitorIfNeeded(mainMonitor)
        _ = TestWindow.new(id: 13, parent: projectWorkspace.rootTilingContainer)

        XCTAssertNotEqual(defaultWorkspace.projectId, projectWorkspace.projectId)
        XCTAssertEqual(workspaceDisplayName(defaultWorkspace.name), "Tab 1")
        XCTAssertEqual(workspaceDisplayName(projectWorkspace.name), "Tab 1")
    }

    func testWorkspaceSidebarRenameUsesDisplayLabelWithoutRenamingWorkspaceIdentity() throws {
        let workspace = Workspace.get(byName: "1")
        workspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 14, parent: workspace.rootTilingContainer)

        try renameWorkspaceForSidebar(workspaceName: workspace.name, displayName: "Code")

        XCTAssertEqual(workspace.name, "1")
        XCTAssertEqual(workspaceDisplayName(workspace.name), "Code")
        XCTAssertEqual(config.workspaceSidebar.workspaceLabels[workspace.name], "Code")
        XCTAssertTrue(Workspace.existing(byName: "1") === workspace)
        XCTAssertNil(Workspace.existing(byName: "Code"))
    }

    func testResettingWorkspaceNameFromSidebarUsesDefaultDisplayName() throws {
        let workspace = Workspace.get(byName: "1")
        workspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 114, parent: workspace.rootTilingContainer)
        try renameWorkspaceForSidebar(workspaceName: workspace.name, displayName: "Code")

        try resetWorkspaceSidebarName(workspaceName: workspace.name)

        XCTAssertEqual(workspace.name, "1")
        XCTAssertEqual(workspaceDisplayName(workspace.name), "Tab 1")
        XCTAssertNil(config.workspaceSidebar.workspaceLabels[workspace.name])
    }

    func testRenamingWorkspaceToDefaultDisplayNameClearsLabel() throws {
        let workspace = Workspace.get(byName: "1")
        workspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 214, parent: workspace.rootTilingContainer)
        try renameWorkspaceForSidebar(workspaceName: workspace.name, displayName: "Code")

        try renameWorkspaceForSidebar(workspaceName: workspace.name, displayName: "Tab 1")

        XCTAssertEqual(workspace.name, "1")
        XCTAssertEqual(workspaceDisplayName(workspace.name), "Tab 1")
        XCTAssertNil(config.workspaceSidebar.workspaceLabels[workspace.name])
    }

    func testWorkspaceRenameRejectsEmptyDisplayName() throws {
        let workspace = Workspace.get(byName: "1")
        workspace.markAsAutomaticallyNamed()

        XCTAssertThrowsError(try renameWorkspaceForSidebar(workspaceName: workspace.name, displayName: "  "))
        XCTAssertNil(config.workspaceSidebar.workspaceLabels[workspace.name])
    }

    func testDeletingWorkspaceKeepsStableWorkspaceIdsAndCompactsDisplayNames() throws {
        let first = Workspace.get(byName: "1")
        first.markAsAutomaticallyNamed()
        let firstWindow = TestWindow.new(id: 15, parent: first.rootTilingContainer)
        let second = Workspace.get(byName: "2")
        second.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 16, parent: second.rootTilingContainer)
        try renameWorkspaceForSidebar(workspaceName: first.name, displayName: "Code")

        try deleteWorkspaceForSidebar(workspaceName: first.name)

        XCTAssertNil(Workspace.existing(byName: "1"))
        XCTAssertTrue(Workspace.existing(byName: "2") === second)
        XCTAssertTrue(firstWindow.nodeWorkspace === second)
        XCTAssertEqual(workspaceDisplayName(second.name), "Tab 1")
        XCTAssertNil(config.workspaceSidebar.workspaceLabels[first.name])
    }

    func testDeletingFocusedWorkspaceFocusesWorkspaceImmediatelyAboveIt() throws {
        let above = Workspace.get(byName: "1")
        above.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 115, parent: above.rootTilingContainer)
        let deleted = Workspace.get(byName: "2")
        deleted.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 116, parent: deleted.rootTilingContainer)
        let next = Workspace.get(byName: "3")
        next.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 117, parent: next.rootTilingContainer)
        _ = deleted.focusWorkspace()

        try deleteWorkspaceForSidebar(workspaceName: deleted.name)

        XCTAssertTrue(focus.workspace === above)
        XCTAssertTrue(Workspace.existing(byName: "3") === next)
    }

    func testDeletingLastFocusedWorkspaceFocusesPreviousClosestWorkspace() throws {
        let previous = Workspace.get(byName: "1")
        previous.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 118, parent: previous.rootTilingContainer)
        let deleted = Workspace.get(byName: "2")
        deleted.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 119, parent: deleted.rootTilingContainer)
        _ = deleted.focusWorkspace()

        try deleteWorkspaceForSidebar(workspaceName: deleted.name)

        XCTAssertTrue(focus.workspace === previous)
        XCTAssertTrue(Workspace.existing(byName: "1") === previous)
    }

    func testRenamingAndDeletingProjectKeepsFallbackWorkspaces() throws {
        let defaultWorkspace = Workspace.get(byName: "1")
        defaultWorkspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 17, parent: defaultWorkspace.rootTilingContainer)
        _ = defaultWorkspace.focusWorkspace()
        Workspace.reconcileWorkspaceState()
        let project = createWorkspaceProject()
        let projectWorkspace = Workspace.get(byName: "2")
        projectWorkspace.markAsAutomaticallyNamed()
        projectWorkspace.assignProject(project.id)
        projectWorkspace.seedMonitorIfNeeded(mainMonitor)
        let projectWindow = TestWindow.new(id: 18, parent: projectWorkspace.rootTilingContainer)

        try renameWorkspaceProject(project.id, displayName: "Work")
        try deleteWorkspaceProject(project.id)

        XCTAssertFalse(workspaceProjects().contains { $0.id == project.id })
        XCTAssertNil(Workspace.existing(byName: projectWorkspace.name))
        XCTAssertTrue(projectWindow.nodeWorkspace === defaultWorkspace)
        XCTAssertEqual(defaultWorkspace.projectId, workspaceProjectDefaultId)
    }

    func testClosingProjectWindowsDeletesProjectWithoutMovingWindowsToFallback() async throws {
        let defaultWorkspace = Workspace.get(byName: "1")
        defaultWorkspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 217, parent: defaultWorkspace.rootTilingContainer)
        let project = createWorkspaceProject()
        let projectWorkspace = Workspace.get(byName: "2")
        projectWorkspace.markAsAutomaticallyNamed()
        projectWorkspace.assignProject(project.id)
        projectWorkspace.seedMonitorIfNeeded(mainMonitor)
        let projectWindow = TestWindow.new(id: 218, parent: projectWorkspace.rootTilingContainer)
        config.workspaceSidebar.projectDeletionAction = .closeWindows
        config.workspaceSidebar.projectLabels[project.id.rawValue] = "Temporary"
        config.workspaceSidebar.projectColors[project.id.rawValue] = "#60A5FA"

        try await deleteWorkspaceProjectFromSidebar(project.id)

        XCTAssertFalse(workspaceProjects().contains { $0.id == project.id })
        XCTAssertNil(Workspace.existing(byName: projectWorkspace.name))
        XCTAssertNil(projectWindow.nodeWorkspace)
        XCTAssertFalse(defaultWorkspace.allLeafWindowsRecursive.contains(projectWindow))
        XCTAssertNil(config.workspaceSidebar.projectLabels[project.id.rawValue])
        XCTAssertNil(config.workspaceSidebar.projectColors[project.id.rawValue])
    }

    func testClosingSidebarTabClosesAllWindowsWithoutMovingThemToFallback() async throws {
        let fallback = Workspace.get(byName: "1")
        fallback.markAsAutomaticallyNamed()
        let fallbackWindow = TestWindow.new(id: 219, parent: fallback.rootTilingContainer)
        let closing = Workspace.get(byName: "2")
        closing.markAsAutomaticallyNamed()
        let firstClosingWindow = TestWindow.new(id: 220, parent: closing.rootTilingContainer)
        let secondClosingWindow = TestWindow.new(id: 221, parent: closing.rootTilingContainer)
        _ = closing.focusWorkspace()

        try await closeWorkspaceWindowsFromSidebar(workspaceName: closing.name)

        XCTAssertNil(Workspace.existing(byName: closing.name))
        XCTAssertTrue(focus.workspace === fallback)
        XCTAssertEqual(fallback.allLeafWindowsRecursive, [fallbackWindow])
        XCTAssertNil(firstClosingWindow.parent)
        XCTAssertNil(secondClosingWindow.parent)
    }

    func testClosingSidebarTabFocusesTabImmediatelyAboveIt() async throws {
        let first = Workspace.get(byName: "close-order-first")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 232, parent: first.rootTilingContainer)
        let above = Workspace.get(byName: "close-order-above")
        above.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 233, parent: above.rootTilingContainer)
        let closing = Workspace.get(byName: "close-order-closing")
        closing.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 234, parent: closing.rootTilingContainer)
        let below = Workspace.get(byName: "close-order-below")
        below.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 235, parent: below.rootTilingContainer)
        _ = closing.focusWorkspace()

        try await closeWorkspaceWindowsFromSidebar(workspaceName: closing.name)

        XCTAssertNil(Workspace.existing(byName: closing.name))
        XCTAssertTrue(focus.workspace === above)
        XCTAssertFalse(focus.workspace === first)
        XCTAssertFalse(focus.workspace === below)
    }

    func testClosingSidebarTabIncludesMinimizedWindows() async throws {
        let fallback = Workspace.get(byName: "1")
        fallback.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 222, parent: fallback.rootTilingContainer)
        let closing = Workspace.get(byName: "2")
        closing.markAsAutomaticallyNamed()
        let regularWindow = TestWindow.new(id: 223, parent: closing.rootTilingContainer)
        let minimizedWindow = TestWindow.new(id: 224, parent: closing.rootTilingContainer)
        let floatingWindow = TestWindow.new(id: 229, parent: closing)
        let fullscreenWindow = TestWindow.new(id: 230, parent: closing.macOsNativeFullscreenWindowsContainer)
        let hiddenWindow = TestWindow.new(id: 231, parent: closing.macOsNativeHiddenAppsWindowsContainer)
        minimizedWindow.layoutReason = .macos(
            prevParentKind: .tilingContainer,
            prevWorkspaceName: closing.name
        )
        minimizedWindow.bind(
            to: macosMinimizedWindowsContainer,
            adaptiveWeight: WEIGHT_DOESNT_MATTER,
            index: INDEX_BIND_LAST
        )

        XCTAssertEqual(Set(windowsInWorkspace(closing).map(\.windowId)), [223, 224, 229, 230, 231])

        try await closeWorkspaceWindowsFromSidebar(workspaceName: closing.name)

        XCTAssertNil(Workspace.existing(byName: closing.name))
        XCTAssertNil(regularWindow.parent)
        XCTAssertNil(minimizedWindow.parent)
        XCTAssertNil(floatingWindow.parent)
        XCTAssertNil(fullscreenWindow.parent)
        XCTAssertNil(hiddenWindow.parent)
    }

    func testClosingEmptySidebarTabRemovesIt() async throws {
        let fallback = Workspace.get(byName: "1")
        fallback.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 225, parent: fallback.rootTilingContainer)
        let closing = Workspace.get(byName: "2")
        closing.markAsAutomaticallyNamed()

        try await closeWorkspaceWindowsFromSidebar(workspaceName: closing.name)

        XCTAssertNil(Workspace.existing(byName: closing.name))
        XCTAssertTrue(Workspace.existing(byName: fallback.name) === fallback)
    }

    func testBlockedWindowKeepsSidebarTabAndReportsRemainingCount() async throws {
        let fallback = Workspace.get(byName: "1")
        fallback.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 226, parent: fallback.rootTilingContainer)
        let closing = Workspace.get(byName: "2")
        closing.markAsAutomaticallyNamed()
        let closeableWindow = TestWindow.new(id: 227, parent: closing.rootTilingContainer)
        let blockedWindow = TestWindow.new(id: 228, parent: closing.rootTilingContainer)
        blockedWindow.refusesClose = true

        do {
            try await closeWorkspaceWindowsFromSidebar(workspaceName: closing.name)
            XCTFail("Expected a blocked close error")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Tab 'Tab 2' was not closed because 1 window stayed open."
            )
        }

        XCTAssertTrue(Workspace.existing(byName: closing.name) === closing)
        XCTAssertNil(closeableWindow.parent)
        XCTAssertNotNil(blockedWindow.parent)
        XCTAssertEqual(windowsInWorkspace(closing).map(\.windowId), [228])
    }

    func testSidebarTabCloseButtonSupportsMultiWindowTabs() {
        XCTAssertTrue(workspaceSidebarTabCloseButtonIsVisible(
            isCompact: false,
            isRenamingWorkspace: false,
            isPointerHoverVisible: true,
            windowCount: 2
        ))
        XCTAssertFalse(workspaceSidebarTabCloseButtonIsVisible(
            isCompact: false,
            isRenamingWorkspace: false,
            isPointerHoverVisible: true,
            windowCount: 0
        ))
        XCTAssertFalse(workspaceSidebarTabCloseButtonIsVisible(
            isCompact: true,
            isRenamingWorkspace: false,
            isPointerHoverVisible: true,
            windowCount: 2
        ))
        XCTAssertFalse(workspaceSidebarTabClosureRequiresConfirmation(windowCount: 1))
        XCTAssertTrue(workspaceSidebarTabClosureRequiresConfirmation(windowCount: 2))
    }

    func testCreatedProjectPersistsIdentityAndDeleteRemovesPersistedIdentity() throws {
        let project = createWorkspaceProject()

        XCTAssertEqual(config.workspaceSidebar.projectLabels[project.id.rawValue], project.name)
        try renameWorkspaceProject(project.id, displayName: "Work")
        XCTAssertEqual(config.workspaceSidebar.projectLabels[project.id.rawValue], "Work")
        config.workspaceSidebar.projectColors[project.id.rawValue] = "#60A5FA"
        try deleteWorkspaceProject(project.id)

        XCTAssertNil(config.workspaceSidebar.projectLabels[project.id.rawValue])
        XCTAssertNil(config.workspaceSidebar.projectColors[project.id.rawValue])
        XCTAssertFalse(workspaceProjects().contains { $0.id == project.id })
        XCTAssertNil(winMuxWorkspaceState.workspaceFoldersById[project.unfoldedFolderId])
    }

    func testPersistedEmptyFolderMetadataIsPrunedBeforeSidebarPresentation() async {
        let originalFocus = focus.workspace
        let folderId = WorkspaceFolderId("project-7")
        config.workspaceSidebar.folderLabels["project-7"] = "Research"
        config.workspaceSidebar.folderColors["project-7"] = "#006BFF"

        let state = await buildWorkspaceSidebarModelState()

        XCTAssertFalse(state.folders.contains { $0.id == folderId })
        XCTAssertNil(winMuxWorkspaceState.workspaceFoldersById[folderId])
        XCTAssertNil(config.workspaceSidebar.folderLabels[folderId.rawValue])
        XCTAssertNil(config.workspaceSidebar.folderColors[folderId.rawValue])
        XCTAssertEqual(focus.workspace, originalFocus)
    }

    func testCreatedEmptyOrdinaryFolderIsPrunedBeforeSidebarPresentation() async {
        let originalFocus = focus.workspace
        let folder = createWorkspaceFolder()

        XCTAssertTrue(folderWorkspaces(folderId: folder.id).isEmpty)

        let state = await buildWorkspaceSidebarModelState()

        XCTAssertFalse(state.folders.contains { $0.id == folder.id })
        XCTAssertNil(winMuxWorkspaceState.workspaceFoldersById[folder.id])
        XCTAssertEqual(focus.workspace, originalFocus)
    }

    func testMovingLastTabOutOfOrdinaryFolderRemovesFolderAndMetadata() throws {
        let tab = focus.workspace
        _ = TestWindow.new(id: 436, parent: tab.rootTilingContainer)
        let folderId = try XCTUnwrap(createWorkspaceFolderFromWorkspace(tab.name))
        config.workspaceSidebar.folderColors[folderId.rawValue] = "#006BFF"

        XCTAssertTrue(moveWorkspaceToSidebarFolder(tab.name, folderId: workspaceFolderDefaultId))

        XCTAssertEqual(tab.folderId, workspaceFolderDefaultId)
        XCTAssertNil(winMuxWorkspaceState.workspaceFoldersById[folderId])
        XCTAssertNil(config.workspaceSidebar.folderLabels[folderId.rawValue])
        XCTAssertNil(config.workspaceSidebar.folderColors[folderId.rawValue])
    }

    func testEmptyUnfoldedFolderIsNeverPruned() {
        let project = createWorkspaceProject()
        for workspace in Workspace.all where workspace.projectId == project.id {
            removeWorkspaceFromRegistry(workspace)
        }

        pruneEmptyWorkspaceTabGroups()

        XCTAssertNotNil(winMuxWorkspaceState.workspaceFoldersById[project.unfoldedFolderId])
    }

    func testLiveTabGroupCreationUsesUniqueIds() throws {
        let first = createWorkspaceFolder()
        let second = createWorkspaceFolder()

        XCTAssertEqual(first.id, "project-1")
        XCTAssertEqual(second.id, "project-2")
        XCTAssertEqual(
            workspaceFoldersInSidebarOrder().map(\.id).filter { $0.rawValue.hasPrefix("project-") },
            ["project-1", "project-2"]
        )
    }

    func testLiveTabGroupCreationAppendsAfterDeletedMiddleGroup() throws {
        let first = createWorkspaceFolder()
        let second = createWorkspaceFolder()
        let third = createWorkspaceFolder()

        try deleteWorkspaceFolder(second.id)
        let fourth = createWorkspaceFolder()

        XCTAssertEqual(first.id, "project-1")
        XCTAssertEqual(second.id, "project-2")
        XCTAssertEqual(third.id, "project-3")
        XCTAssertEqual(fourth.id, "project-4")
        XCTAssertEqual(
            workspaceFoldersInSidebarOrder().map(\.id).filter { $0.rawValue.hasPrefix("project-") },
            ["project-1", "project-3", "project-4"],
        )
    }

    func testLiveTabGroupNamesFollowStableInsertionOrder() throws {
        let first = createWorkspaceFolder()
        let second = createWorkspaceFolder()
        let third = createWorkspaceFolder()

        XCTAssertEqual(
            workspaceFoldersInSidebarOrder().map(\.id).filter { $0.rawValue.hasPrefix("project-") },
            [first.id, second.id, third.id],
        )
        XCTAssertEqual(
            workspaceFoldersInSidebarOrder().filter { $0.id.rawValue.hasPrefix("project-") }.map(\.name),
            ["Folder 1", "Folder 2", "Folder 3"],
        )
    }

    func testEmptyTabGroupDeletionFallsBackToDefaultProjectWhenProjectsAreHardDisabled() throws {
        let first = createWorkspaceProject()
        let second = createWorkspaceProject()

        XCTAssertEqual(workspaceProjectFallbackForDeletion(excluding: first.id), second.id)
        XCTAssertEqual(workspaceProjectFallbackForDeletion(excluding: second.id), first.id)
    }

    func testDeletingActiveFolderActivatesNextSidebarFolderWhenProjectsAreHardDisabled() throws {
        let first = createWorkspaceProject()
        let second = createWorkspaceProject()
        XCTAssertNotNil(switchWorkspaceProject(first.id, on: mainMonitor))

        try deleteWorkspaceProject(first.id)

        XCTAssertEqual(activeWorkspaceProjectId(for: mainMonitor), second.id)
        XCTAssertFalse(workspaceProjects().contains { $0.id == first.id })
        XCTAssertTrue(workspaceProjects().contains { $0.id == second.id })
    }

    func testFolderSwitchTracksActiveFolderOnMultipleDisplaysWhenProjectsAreHardDisabled() {
        let main = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Left",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        let secondary = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Main",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        setMonitorsForTests([main, secondary])
        let project = createWorkspaceProject()

        let mainWorkspace = switchWorkspaceProject(project.id, on: main)
        let secondaryWorkspace = switchWorkspaceProject(project.id, on: secondary)

        XCTAssertNotNil(mainWorkspace)
        XCTAssertNotNil(secondaryWorkspace)
        XCTAssertFalse(mainWorkspace === secondaryWorkspace)
        XCTAssertEqual(activeWorkspaceProjectId(for: main), project.id)
        XCTAssertEqual(activeWorkspaceProjectId(for: secondary), project.id)
        XCTAssertEqual(main.activeWorkspace.projectId, project.id)
        XCTAssertEqual(secondary.activeWorkspace.projectId, project.id)
        XCTAssertFalse(main.activeWorkspace === secondary.activeWorkspace)
    }

    func testProjectSwitchCanReturnToDefaultOnSameMonitor() throws {
        let defaultWorkspace = Workspace.get(byName: "1")
        defaultWorkspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 401, parent: defaultWorkspace.rootTilingContainer)
        XCTAssertTrue(mainMonitor.setActiveWorkspace(defaultWorkspace))
        let project = createWorkspaceProject()
        let projectWorkspace = try XCTUnwrap(switchWorkspaceProject(project.id, on: mainMonitor))

        XCTAssertTrue(mainMonitor.activeWorkspace === projectWorkspace)

        let returnedWorkspace = try XCTUnwrap(switchWorkspaceProject(workspaceProjectDefaultId, on: mainMonitor))

        XCTAssertTrue(mainMonitor.activeWorkspace === returnedWorkspace)
        XCTAssertEqual(returnedWorkspace.projectId, workspaceProjectDefaultId)
        XCTAssertTrue(returnedWorkspace === defaultWorkspace)
    }

}
