import AppKit
@testable import AppBundle
import XCTest

extension WorkspaceSidebarDragTest {
    func testAppInfoPlistExportsSidebarDragPayloadType() throws {
        let infoPlist = projectRoot.appending(component: "resources/WinMuxInfo.plist")
        let data = try Data(contentsOf: infoPlist)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            "Expected WinMuxInfo.plist to parse as a dictionary",
        )
        let declarations = try XCTUnwrap(
            plist["UTExportedTypeDeclarations"] as? [[String: Any]],
            "WinMuxInfo.plist must export the custom sidebar drag payload type",
        )

        let declaration = declarations.first {
            ($0["UTTypeIdentifier"] as? String) == workspaceSidebarDragPayloadType.identifier
        }
        XCTAssertNotNil(declaration)
        XCTAssertEqual(declaration?["UTTypeDescription"] as? String, "WinMux Sidebar Drag Payload")
        XCTAssertEqual(declaration?["UTTypeConformsTo"] as? [String], ["public.data"])
    }

    func testSameWorkspaceSidebarDropTargetIsNotActionable() {
        XCTAssertFalse(
            isActionableSidebarWorkspaceDropTarget(
                sourceWorkspaceName: "1",
                targetKind: .workspace("1"),
            ),
        )
    }

    func testDifferentWorkspaceSidebarDropTargetIsActionable() {
        XCTAssertTrue(
            isActionableSidebarWorkspaceDropTarget(
                sourceWorkspaceName: "1",
                targetKind: .workspace("2"),
            ),
        )
    }

    func testNewWorkspaceSidebarDropTargetIsActionable() {
        XCTAssertTrue(
            isActionableSidebarWorkspaceDropTarget(
                sourceWorkspaceName: "1",
                targetKind: .newWorkspace(projectId: workspaceProjectDefaultId, monitorScopeId: workspaceSidebarDefaultScopeId),
            ),
        )
    }

    func testFolderSidebarDropTargetIsActionable() {
        XCTAssertTrue(
            isActionableSidebarWorkspaceDropTarget(
                sourceWorkspaceName: "1",
                targetKind: .folder("project-1", monitorScopeId: workspaceSidebarDefaultScopeId),
            ),
        )
    }

    func testBlankSidebarAreaIsNotActionable() {
        XCTAssertFalse(
            isActionableSidebarWorkspaceDropTarget(
                sourceWorkspaceName: "1",
                targetKind: nil,
            ),
        )
    }

    func testMonitorSidebarDropTargetIsActionable() {
        XCTAssertTrue(
            isActionableSidebarWorkspaceDropTarget(
                sourceWorkspaceName: "1",
                targetKind: .monitor("monitor:1920.0,0.0"),
            ),
        )
    }

    @MainActor
    func testSidebarDropTargetPrefersSpecificChildOverFolderBlock() {
        let targets = [
            WorkspaceSidebarDropTarget(
                kind: .folder("project-1", monitorScopeId: workspaceSidebarDefaultScopeId),
                rect: Rect(topLeftX: 0, topLeftY: 0, width: 220, height: 180)
            ),
            WorkspaceSidebarDropTarget(
                kind: .workspace("child"),
                rect: Rect(topLeftX: 20, topLeftY: 60, width: 180, height: 32)
            ),
        ]

        XCTAssertEqual(
            workspaceSidebarDropTarget(
                in: targets,
                panelVisibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 240, height: 400),
                at: CGPoint(x: 40, y: 76)
            )?.kind,
            .workspace("child")
        )
    }

    @MainActor
    func testSidebarNewWorkspaceTargetUsesDropPointMonitorBeforeSourceMonitor() {
        let main = WorkspaceSidebarDragTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let secondary = WorkspaceSidebarDragTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([main, secondary])
        defer { setMonitorsForTests(nil) }

        let target = workspaceSidebarTargetMonitor(
            selectedMonitor: nil,
            fallbackPoint: CGPoint(x: 2000, y: 20),
            fallbackWindowMonitor: main,
            focusedMonitor: main,
        )

        XCTAssertEqual(target.rect.topLeftCorner, secondary.rect.topLeftCorner)
    }

    @MainActor
    func testSidebarNewWorkspaceTargetHonorsExplicitMonitorSelection() {
        let main = WorkspaceSidebarDragTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let secondary = WorkspaceSidebarDragTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([main, secondary])
        defer { setMonitorsForTests(nil) }

        let target = workspaceSidebarTargetMonitor(
            selectedMonitor: main,
            fallbackPoint: CGPoint(x: 2000, y: 20),
            fallbackWindowMonitor: secondary,
            focusedMonitor: secondary,
        )

        XCTAssertEqual(target.rect.topLeftCorner, main.rect.topLeftCorner)
    }

    @MainActor
    func testMonitorScopeResolvesMonitorPoint() {
        let secondary = WorkspaceSidebarDragTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([secondary])
        defer { setMonitorsForTests(nil) }

        let scopeId = workspaceSidebarMonitorScopeId(for: secondary)

        XCTAssertEqual(workspaceSidebarMonitorScopePoint(scopeId), secondary.rect.topLeftCorner)
        XCTAssertEqual(workspaceSidebarMonitor(forScopeId: scopeId)?.rect.topLeftCorner, secondary.rect.topLeftCorner)
    }

    @MainActor
    func testSidebarWorkspaceClickDoesNotFocusWorkspaceVisibleOnOtherMonitor() {
        let main = WorkspaceSidebarDragTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let secondary = WorkspaceSidebarDragTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([main, secondary])
        defer { setMonitorsForTests(nil) }

        let mainWorkspace = Workspace.get(byName: "main")
        let secondaryWorkspace = Workspace.get(byName: "secondary")
        XCTAssertTrue(main.setActiveWorkspace(mainWorkspace))
        XCTAssertTrue(secondary.setActiveWorkspace(secondaryWorkspace))
        XCTAssertTrue(mainWorkspace.focusWorkspace())

        XCTAssertFalse(focusWorkspaceFromSidebar(
            secondaryWorkspace,
            targetMonitorScopeId: workspaceSidebarMonitorScopeId(for: main),
        ))
        XCTAssertEqual(main.activeWorkspace, mainWorkspace)
        XCTAssertEqual(secondary.activeWorkspace, secondaryWorkspace)
        XCTAssertEqual(focus.workspace, mainWorkspace)
    }

    @MainActor
    func testSidebarWorkspaceClickActivatesHiddenWorkspaceOnOwningPanelMonitor() {
        let main = WorkspaceSidebarDragTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let secondary = WorkspaceSidebarDragTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([main, secondary])
        defer { setMonitorsForTests(nil) }

        let mainWorkspace = Workspace.get(byName: "main")
        let secondaryWorkspace = Workspace.get(byName: "secondary")
        let hiddenWorkspace = Workspace.get(byName: "hidden")
        XCTAssertTrue(main.setActiveWorkspace(mainWorkspace))
        XCTAssertTrue(secondary.setActiveWorkspace(secondaryWorkspace))
        XCTAssertTrue(mainWorkspace.focusWorkspace())

        XCTAssertTrue(focusWorkspaceFromSidebar(
            hiddenWorkspace,
            targetMonitorScopeId: workspaceSidebarMonitorScopeId(for: secondary),
        ))
        XCTAssertEqual(main.activeWorkspace, mainWorkspace)
        XCTAssertEqual(secondary.activeWorkspace, hiddenWorkspace)
        XCTAssertEqual(focus.workspace, hiddenWorkspace)
    }

    @MainActor
    func testMonitorScopeSelectionIsPanelLocal() {
        let previousSharedScope = TrayMenuModel.shared.workspaceSidebarSelectedMonitorScopeId
        TrayMenuModel.shared.workspaceSidebarSelectedMonitorScopeId = workspaceSidebarDefaultScopeId
        defer { TrayMenuModel.shared.workspaceSidebarSelectedMonitorScopeId = previousSharedScope }

        let mainModel = TrayMenuModel()
        let secondaryModel = TrayMenuModel()
        mainModel.workspaceSidebarMonitorScopes = [
            WorkspaceSidebarMonitorScopeViewModel(
                id: workspaceSidebarDefaultScopeId,
                displayName: "Default",
                subtitle: nil,
                systemImageName: "display",
                isFocusedMonitor: false,
            ),
            WorkspaceSidebarMonitorScopeViewModel(
                id: "monitor:1440.0,0.0",
                displayName: "Secondary",
                subtitle: nil,
                systemImageName: "display",
                isFocusedMonitor: false,
            ),
        ]
        secondaryModel.workspaceSidebarMonitorScopes = mainModel.workspaceSidebarMonitorScopes

        selectWorkspaceSidebarMonitorScope("monitor:1440.0,0.0", viewModel: mainModel)

        XCTAssertEqual(mainModel.workspaceSidebarSelectedMonitorScopeId, "monitor:1440.0,0.0")
        XCTAssertEqual(secondaryModel.workspaceSidebarSelectedMonitorScopeId, workspaceSidebarDefaultScopeId)
        XCTAssertEqual(TrayMenuModel.shared.workspaceSidebarSelectedMonitorScopeId, workspaceSidebarDefaultScopeId)
    }

    @MainActor
    func testMonitorScopesOmitDisabledFocusAndAllFilters() {
        let main = WorkspaceSidebarDragTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let secondary = WorkspaceSidebarDragTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )

        let scopes = buildWorkspaceSidebarMonitorScopes(
            sortedMonitors: [main, secondary],
            focusedMonitorScopeId: workspaceSidebarMonitorScopeId(for: main),
        )

        XCTAssertEqual(scopes.map(\.id), [
            workspaceSidebarDefaultScopeId,
            workspaceSidebarMonitorScopeId(for: main),
            workspaceSidebarMonitorScopeId(for: secondary),
        ])
    }

    @MainActor
    func testWorkspaceSidebarFocusFilterDefaultsOff() {
        XCTAssertFalse(defaultConfig.workspaceSidebar.enableFocus)
    }

    @MainActor
    func testMonitorScopesIncludeFocusFilterWhenEnabled() {
        let previous = config.workspaceSidebar.enableFocus
        config.workspaceSidebar.enableFocus = true
        defer { config.workspaceSidebar.enableFocus = previous }
        let main = WorkspaceSidebarDragTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )

        let scopes = buildWorkspaceSidebarMonitorScopes(
            sortedMonitors: [main],
            focusedMonitorScopeId: workspaceSidebarMonitorScopeId(for: main),
        )

        XCTAssertEqual(scopes.map(\.id), [
            workspaceSidebarDefaultScopeId,
            workspaceSidebarFocusedScopeId,
            workspaceSidebarMonitorScopeId(for: main),
        ])
    }

    func testVisibleWorkspacesAreGroupedByProjectAndScope() {
        let focusedScope = "monitor:0.0"
        let otherScope = "monitor:1920.0"
        let workspaces = [
            WorkspaceSidebarWorkspaceViewModel(
                name: "1",
                projectId: "default",
                displayName: "1",
                sidebarLabel: "",
                isGeneratedName: false,
                monitorScopeId: focusedScope,
                monitorName: nil,
                isFocused: true,
                isVisible: true,
                items: [],
            ),
            WorkspaceSidebarWorkspaceViewModel(
                name: "2",
                projectId: "project-b",
                displayName: "2",
                sidebarLabel: "",
                isGeneratedName: false,
                monitorScopeId: otherScope,
                monitorName: nil,
                isFocused: false,
                isVisible: true,
                items: [],
            ),
        ]

        let grouped = workspaceSidebarVisibleWorkspacesByProject(
            workspaces: workspaces,
            selectedScopeId: workspaceSidebarFocusedScopeId,
            focusedMonitorScopeId: focusedScope,
        )

        XCTAssertEqual(grouped["default"]?.map(\.name), ["1"])
        XCTAssertNil(grouped["project-b"])
    }

    func testHardTabListDefaultScopeUsesPanelMonitor() {
        let mainScope = "monitor:0.0"
        let secondaryScope = "monitor:1920.0"
        let workspaces = [
            WorkspaceSidebarWorkspaceViewModel(
                name: "main-tab",
                projectId: workspaceProjectDefaultId,
                displayName: "Main",
                sidebarLabel: "",
                isGeneratedName: true,
                monitorScopeId: mainScope,
                monitorName: nil,
                isFocused: true,
                isVisible: true,
                items: [],
            ),
            WorkspaceSidebarWorkspaceViewModel(
                name: "secondary-tab",
                projectId: workspaceProjectDefaultId,
                displayName: "Secondary",
                sidebarLabel: "",
                isGeneratedName: true,
                monitorScopeId: secondaryScope,
                monitorName: nil,
                isFocused: false,
                isVisible: true,
                items: [],
            ),
        ]

        let grouped = workspaceSidebarVisibleWorkspacesByProject(
            workspaces: workspaces,
            selectedScopeId: workspaceSidebarDefaultScopeId,
            focusedMonitorScopeId: mainScope,
            targetMonitorScopeId: secondaryScope,
            projectsEnabled: false,
        )

        XCTAssertEqual(grouped[workspaceProjectDefaultId]?.map(\.name), ["secondary-tab"])
    }

    func testProjectPagerRendersOnlyCurrentAndSwipeTargetPages() {
        XCTAssertTrue(shouldRenderWorkspaceSidebarProjectPage(index: 1, displayIndex: 1, swipeDirection: nil, projectCount: 4))
        XCTAssertFalse(shouldRenderWorkspaceSidebarProjectPage(index: 0, displayIndex: 1, swipeDirection: nil, projectCount: 4))
        XCTAssertTrue(shouldRenderWorkspaceSidebarProjectPage(index: 2, displayIndex: 1, swipeDirection: 1, projectCount: 4))
        XCTAssertFalse(shouldRenderWorkspaceSidebarProjectPage(index: 3, displayIndex: 1, swipeDirection: 1, projectCount: 4))
    }

    func testProjectPagerIsRemovedFromAllSidebarModes() {
        XCTAssertFalse(workspaceSidebarShouldShowProjectPager(projectsEnabled: true, isCompact: true))
        XCTAssertFalse(workspaceSidebarShouldShowProjectPager(projectsEnabled: true, isCompact: false))
        XCTAssertFalse(workspaceSidebarShouldShowProjectPager(projectsEnabled: false, isCompact: false))
    }

    func testProjectSwipeCaptureIsRemovedFromAllSidebarModes() {
        XCTAssertFalse(workspaceSidebarProjectSwipeCaptureIsEnabled(
            projectsEnabled: true,
            projectCount: 3,
            isCompact: true
        ))
        XCTAssertFalse(workspaceSidebarProjectSwipeCaptureIsEnabled(
            projectsEnabled: true,
            projectCount: 3,
            isCompact: false
        ))
        XCTAssertFalse(workspaceSidebarProjectSwipeCaptureIsEnabled(
            projectsEnabled: true,
            projectCount: 0,
            isCompact: false
        ))
    }
}
