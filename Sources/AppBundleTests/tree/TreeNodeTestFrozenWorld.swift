@testable import AppBundle
import XCTest

extension TreeNodeTest {
    func testExitMacOsNativeUnconventionalStateRestoresWindowToPreviousWorkspaceWhileWorkspaceStaysAlive() async throws {
        let workspaceA = Workspace.get(byName: "a")
        let window = TestWindow.new(id: 1, parent: workspaceA.rootTilingContainer)
        let workspaceB = Workspace.get(byName: "b")

        window.layoutReason = .macos(prevParentKind: .tilingContainer, prevWorkspaceName: workspaceA.name)
        window.bind(to: macosMinimizedWindowsContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        _ = workspaceB.focusWorkspace()

        Workspace.reconcileWorkspaceState()
        XCTAssertEqual(Workspace.existing(byName: workspaceA.name), workspaceA)

        try await exitMacOsNativeUnconventionalState(
            window: window,
            prevParentKind: .tilingContainer,
            prevWorkspaceName: workspaceA.name,
            workspace: workspaceB,
        )

        let restoredWorkspace = Workspace.existing(byName: workspaceA.name).orDie()
        XCTAssertEqual(window.nodeWorkspace, restoredWorkspace)
        XCTAssertTrue(restoredWorkspace.rootTilingContainer.children.contains(window))
        XCTAssertEqual(restoredWorkspace.preferredMonitorPointForTesting, workspaceB.workspaceMonitor.rect.topLeftCorner)
    }

    func testPersistedFrozenWorldCodableRoundTrip() throws {
        let workspace = Workspace.get(byName: "1")
        let tabGroup = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: 1, .h, .tabGroup, index: 0)
        let fullscreenWindow = TestWindow.new(id: 11, parent: tabGroup, adaptiveWeight: 1)
        TestWindow.new(id: 12, parent: tabGroup, adaptiveWeight: 1)
        fullscreenWindow.isFullscreen = true
        fullscreenWindow.noOuterGapsInFullscreen = true
        fullscreenWindow.layoutReason = .macos(prevParentKind: .tilingContainer, prevWorkspaceName: workspace.name)

        let frozenWorld = FrozenWorld(
            workspaces: [FrozenWorkspace(workspace)],
            monitors: monitors.map(FrozenMonitor.init),
            windowIds: [11, 12],
            sidebar: FrozenSidebarState(restorableWorkspaces: [workspace]),
        )

        let data = try JSONEncoder().encode(frozenWorld)
        let decoded = try JSONDecoder().decode(FrozenWorld.self, from: data)

        XCTAssertEqual(decoded.windowIds, [11, 12])
        XCTAssertEqual(decoded.workspaces.count, 1)
        XCTAssertEqual(decoded.sidebar?.projects.singleOrNil()?.workspaceNames, [workspace.name])

        let frozenChild = try XCTUnwrap(decoded.workspaces.first?.rootTilingNode.children.first)
        switch frozenChild {
            case .container(let container):
                XCTAssertEqual(container.layout, .tabGroup)
                XCTAssertEqual(container.orientation, .h)
                XCTAssertEqual(container.children.count, 2)
                let fullscreenChild = try XCTUnwrap(container.children.first)
                guard case .window(let decodedWindow) = fullscreenChild else {
                    return XCTFail("Expected fullscreen window leaf in persisted frozen world")
                }
                XCTAssertTrue(decodedWindow.isFullscreen)
                XCTAssertTrue(decodedWindow.noOuterGapsInFullscreen)
                XCTAssertEqual(decodedWindow.layoutReason, .macos(prevParentKind: .tilingContainer, prevWorkspaceName: workspace.name))
            case .window:
                XCTFail("Expected nested container in persisted frozen world")
        }
    }

    func testFrozenWorldDecodesLegacyPayloadWithoutSidebarState() throws {
        let json = #"{"workspaces":[],"monitors":[],"windowIds":[]}"#

        let decoded = try JSONDecoder().decode(FrozenWorld.self, from: Data(json.utf8))

        XCTAssertNil(decoded.sidebar)
        XCTAssertTrue(decoded.workspaces.isEmpty)
        XCTAssertTrue(decoded.monitors.isEmpty)
        XCTAssertTrue(decoded.windowIds.isEmpty)
    }

    func testFrozenWorldDecodesLegacySidebarStateWithoutLabels() throws {
        let json = #"{"workspaces":[],"monitors":[],"windowIds":[],"sidebar":{"projects":[],"collapsedFolderIds":[]}}"#

        let decoded = try JSONDecoder().decode(FrozenWorld.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.sidebar?.workspaceLabels, [:])
        XCTAssertEqual(decoded.sidebar?.projectLabels, [:])
    }

    func testLegacyMultiFolderSidebarMigratesIntoMainAndRoundTripsIdempotently() throws {
        let json = ##"{"projects":[{"id":"project-2","name":"Client","order":2,"workspaceNames":["alpha","beta"]},{"id":"default","name":"Unfolded","order":9,"workspaceNames":["gamma"]}],"collapsedFolderIds":["project-2"],"workspaceLabels":{"alpha":"Alpha Tab","gamma":"Gamma Tab"},"projectLabels":{"project-2":"Client Label","default":"Unfolded"},"projectColors":{"project-2":"#60A5FA","default":"#9B8FC4"}}"##
        let migrated = try JSONDecoder().decode(FrozenSidebarState.self, from: Data(json.utf8))

        XCTAssertEqual(migrated.projects.map(\.id), [workspaceProjectDefaultId])
        XCTAssertEqual(migrated.projects[0].name, "Main")
        XCTAssertEqual(migrated.projects[0].folders.map(\.id), ["project-2", "default"])
        XCTAssertEqual(migrated.projects[0].folders.map(\.workspaceNames), [["alpha", "beta"], ["gamma"]])
        XCTAssertEqual(migrated.collapsedFolderIds, ["project-2"])
        XCTAssertEqual(migrated.workspaceLabels, ["alpha": "Alpha Tab", "gamma": "Gamma Tab"])
        XCTAssertEqual(migrated.projectLabels, ["default": "Main"])
        XCTAssertEqual(migrated.projectColors, [:])
        XCTAssertEqual(migrated.folderLabels, ["project-2": "Client Label", "default": "Unfolded"])
        XCTAssertEqual(migrated.folderColors, ["project-2": "#60A5FA", "default": "#9B8FC4"])

        restoreFrozenSidebarState(migrated, restoredWorkspaceNames: [], materializeMissingWorkspaces: true)
        XCTAssertEqual(workspaceProjects().map(\.id), [workspaceProjectDefaultId])
        XCTAssertEqual(workspaceFolders(in: workspaceProjectDefaultId).map(\.id), ["project-2", "default"])
        XCTAssertEqual(Workspace.existing(byName: "alpha")?.folderId, "project-2")
        XCTAssertEqual(Workspace.existing(byName: "beta")?.folderId, "project-2")
        XCTAssertEqual(Workspace.existing(byName: "gamma")?.folderId, "default")
        XCTAssertFalse(workspaceSidebarFolderIsExpanded(WorkspaceFolderId("project-2")))

        let checkpoint = FrozenSidebarState(restorableWorkspaces: Workspace.all.filter {
            ["alpha", "beta", "gamma"].contains($0.name)
        })
        let restarted = try JSONDecoder().decode(
            FrozenSidebarState.self,
            from: JSONEncoder.winMuxDefault.encode(checkpoint)
        )
        XCTAssertEqual(restarted.projects.map(\.id), [workspaceProjectDefaultId])
        XCTAssertEqual(restarted.projects[0].folders.map(\.id), ["project-2", "default"])
        XCTAssertEqual(restarted.projects[0].folders.map(\.workspaceNames), [["alpha", "beta"], ["gamma"]])
        XCTAssertEqual(restarted.folderLabels, migrated.folderLabels)
        XCTAssertEqual(restarted.folderColors, migrated.folderColors)
    }

    func testSnapshotCurrentFrozenWorldExcludesDetachedMinimizedWindow() {
        let workspace = Workspace.get(byName: "minimized")
        let window = TestWindow.new(id: 32, parent: workspace.rootTilingContainer)

        window.rememberMacOsLayoutOrigin(detachFromWorkspace: true)
        window.nativeIsMacosMinimized = true
        window.bind(to: macosMinimizedWindowsContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)

        let frozenWorld = snapshotCurrentFrozenWorld()

        XCTAssertTrue(frozenWorld.windowIds.isEmpty)
        XCTAssertTrue(frozenWorld.workspaces.isEmpty)
    }

    func testSnapshotCurrentFrozenWorldCapturesSidebarFolderOrderAndExpansion() {
        let first = Workspace.get(byName: "first")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 51, parent: first.rootTilingContainer)
        let second = Workspace.get(byName: "second")
        second.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 52, parent: second.rootTilingContainer)
        let folder = createWorkspaceFolder()
        first.assignFolder(folder.id)
        second.assignFolder(folder.id)
        var storedFolder = winMuxWorkspaceState.workspaceFoldersById[folder.id].orDie()
        storedFolder.workspaceOrder = [second.id, first.id]
        winMuxWorkspaceState.workspaceFoldersById[folder.id] = storedFolder
        setWorkspaceSidebarFolderExpanded(folder.id, isExpanded: false)

        let frozenWorld = snapshotCurrentFrozenWorld()
        let frozenFolder = frozenWorld.sidebar?.projects
            .first { $0.id == workspaceProjectDefaultId }?
            .folders.first { $0.id == folder.id }

        XCTAssertEqual(frozenFolder?.workspaceNames, ["second", "first"])
        XCTAssertTrue(frozenWorld.sidebar?.collapsedFolderIds.contains(folder.id) == true)
    }

    func testSnapshotCurrentFrozenWorldKeepsEmptySidebarFoldersForRestart() {
        let workspace = Workspace.get(byName: "retained")
        workspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 54, parent: workspace.rootTilingContainer)
        let emptyFolder = createWorkspaceFolder()

        let frozenWorld = snapshotCurrentFrozenWorld()

        XCTAssertTrue(frozenWorld.sidebar?.projects
            .first { $0.id == workspaceProjectDefaultId }?
            .folders.contains(where: { $0.id == emptyFolder.id }) == true)
    }

    func testDefaultFolderOrderNormalizationIsIdempotent() {
        let firstFolder = createWorkspaceFolder()
        let secondFolder = createWorkspaceFolder()
        var defaultProject = winMuxWorkspaceState.projectsById[workspaceProjectDefaultId].orDie()
        defaultProject.folderOrder = [
            workspaceFolderDefaultId,
            firstFolder.id,
            firstFolder.id,
        ]
        winMuxWorkspaceState.projectsById[workspaceProjectDefaultId] = defaultProject

        XCTAssertTrue(winMuxWorkspaceState.normalizeDefaultProjectFolderOrder())
        XCTAssertEqual(
            winMuxWorkspaceState.projectsById[workspaceProjectDefaultId]?.folderOrder,
            [firstFolder.id, secondFolder.id, workspaceFolderDefaultId]
        )
        XCTAssertFalse(winMuxWorkspaceState.normalizeDefaultProjectFolderOrder())
    }

    func testRestoreFrozenSidebarStateRestoresFolderWithoutMatchingWindowIds() {
        let first = Workspace.get(byName: "first")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 55, parent: first.rootTilingContainer)
        let folder = createWorkspaceFolder()
        first.assignFolder(folder.id)
        let sidebar = FrozenSidebarState(restorableWorkspaces: [first])

        first.assignFolder(workspaceFolderDefaultId)
        restoreFrozenSidebarState(sidebar, restoredWorkspaceNames: [first.name])

        XCTAssertEqual(first.folderId, folder.id)
        XCTAssertNotNil(winMuxWorkspaceState.workspaceFoldersById[folder.id])
    }

    func testRestorePersistedSidebarStateMaterializesMissingFolderTabs() throws {
        let json = #"{"projects":[{"id":"project-saved","name":"Saved","order":1,"workspaceNames":["saved-tab"],"linkedViewportIds":[]}],"collapsedFolderIds":[],"workspaceLabels":{"saved-tab":"Saved Tab"},"projectLabels":{"project-saved":"Saved"}}"#
        let sidebar = try JSONDecoder().decode(FrozenSidebarState.self, from: Data(json.utf8))

        restoreFrozenSidebarState(
            sidebar,
            restoredWorkspaceNames: [],
            materializeMissingWorkspaces: true
        )

        let workspace = try XCTUnwrap(Workspace.existing(byName: "saved-tab"))
        XCTAssertEqual(workspace.folderId, WorkspaceFolderId("project-saved"))
        XCTAssertEqual(config.workspaceSidebar.workspaceLabels["saved-tab"], "Saved Tab")
        XCTAssertEqual(
            winMuxWorkspaceState.workspaceFoldersById[WorkspaceFolderId("project-saved")]?.workspaceOrder,
            [workspace.id]
        )
    }

    func testSnapshotCurrentFrozenWorldCapturesSidebarRenamedTabsAndFolders() throws {
        let workspace = Workspace.get(byName: "renamed")
        workspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 53, parent: workspace.rootTilingContainer)
        let folder = createWorkspaceFolder()
        workspace.assignFolder(folder.id)
        try renameWorkspaceForSidebar(workspaceName: workspace.name, displayName: "Design")
        try renameWorkspaceFolder(folder.id, displayName: "Client")

        let frozenWorld = snapshotCurrentFrozenWorld()

        XCTAssertEqual(frozenWorld.sidebar?.workspaceLabels[workspace.name], "Design")
        XCTAssertEqual(frozenWorld.sidebar?.folderLabels[folder.id.rawValue], "Client")
    }

    func testRestoreFrozenWorldRestoresSidebarOrderAndCollapsedFolders() async throws {
        let first = Workspace.get(byName: "first")
        first.markAsAutomaticallyNamed()
        let firstWindow = TestWindow.new(id: 61, parent: first.rootTilingContainer)
        let second = Workspace.get(byName: "second")
        second.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 62, parent: second.rootTilingContainer)
        let folder = createWorkspaceFolder()
        first.assignFolder(folder.id)
        second.assignFolder(folder.id)
        var storedFolder = winMuxWorkspaceState.workspaceFoldersById[folder.id].orDie()
        storedFolder.workspaceOrder = [second.id, first.id]
        winMuxWorkspaceState.workspaceFoldersById[folder.id] = storedFolder
        setWorkspaceSidebarFolderExpanded(folder.id, isExpanded: false)
        let frozenWorld = snapshotCurrentFrozenWorld()

        first.assignFolder(workspaceFolderDefaultId)
        second.assignFolder(workspaceFolderDefaultId)
        setWorkspaceSidebarFolderExpanded(folder.id, isExpanded: true)

        let didRestore = try await restoreFrozenWorldIfNeeded(frozenWorld, newlyDetectedWindow: firstWindow)

        XCTAssertTrue(didRestore)
        XCTAssertEqual(first.folderId, folder.id)
        XCTAssertEqual(second.folderId, folder.id)
        XCTAssertEqual(
            winMuxWorkspaceState.workspaceFoldersById[folder.id]?.workspaceOrder,
            [second.id, first.id],
        )
        XCTAssertFalse(workspaceSidebarFolderIsExpanded(folder.id))
    }

    func testRestoreFrozenWorldRestoresSidebarRenamedTabsAndFolders() async throws {
        let workspace = Workspace.get(byName: "renamed")
        workspace.markAsAutomaticallyNamed()
        let window = TestWindow.new(id: 64, parent: workspace.rootTilingContainer)
        let folder = createWorkspaceFolder()
        workspace.assignFolder(folder.id)
        try renameWorkspaceForSidebar(workspaceName: workspace.name, displayName: "Design")
        try renameWorkspaceFolder(folder.id, displayName: "Client")
        let frozenWorld = snapshotCurrentFrozenWorld()

        config.workspaceSidebar.workspaceLabels.removeValue(forKey: workspace.name)
        config.workspaceSidebar.folderLabels.removeValue(forKey: folder.id.rawValue)
        workspace.assignFolder(workspaceFolderDefaultId)

        let didRestore = try await restoreFrozenWorldIfNeeded(frozenWorld, newlyDetectedWindow: window)

        XCTAssertTrue(didRestore)
        XCTAssertEqual(config.workspaceSidebar.workspaceLabels[workspace.name], "Design")
        XCTAssertEqual(config.workspaceSidebar.folderLabels[folder.id.rawValue], "Client")
    }

    func testRestoreFrozenWorldRemovesProvisionalFreshTabWithoutDuplicatingSavedTab() async throws {
        let savedWorkspace = Workspace.get(byName: "saved")
        savedWorkspace.markAsAutomaticallyNamed()
        let window = TestWindow.new(id: 65, parent: savedWorkspace.rootTilingContainer)
        XCTAssertTrue(mainMonitor.setActiveWorkspace(savedWorkspace))
        let frozenWorld = snapshotCurrentFrozenWorld()

        let provisionalWorkspace = workspaceForNewTilingWindow(
            defaultWorkspace: savedWorkspace,
            placement: .freshTab
        )
        window.bind(
            to: provisionalWorkspace.rootTilingContainer,
            adaptiveWeight: WEIGHT_AUTO,
            index: INDEX_BIND_LAST
        )
        XCTAssertTrue(mainMonitor.activeWorkspace === provisionalWorkspace)

        let didRestore = try await restoreFrozenWorldIfNeeded(frozenWorld, newlyDetectedWindow: window)

        XCTAssertTrue(didRestore)
        XCTAssertTrue(window.nodeWorkspace === savedWorkspace)
        XCTAssertNil(Workspace.existing(byName: provisionalWorkspace.name))
        XCTAssertEqual(
            Workspace.all.filter { $0.allLeafWindowsRecursive.contains(window) }.map(\.name),
            [savedWorkspace.name]
        )
    }

    func testRestoreFrozenWorldKeepsSidebarTabsOnTheirSavedMonitor() async throws {
        let main = TestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1000, height: 800),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1000, height: 760),
            isMain: true,
        )
        let secondary = TestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1000, topLeftY: 0, width: 1000, height: 800),
            visibleRect: Rect(topLeftX: 1000, topLeftY: 0, width: 1000, height: 760),
            isMain: false,
        )
        setMonitorsForTests([main, secondary])
        let workspace = Workspace.get(byName: "secondary")
        workspace.markAsAutomaticallyNamed()
        workspace.seedMonitorIfNeeded(secondary)
        let window = TestWindow.new(id: 63, parent: workspace.rootTilingContainer)
        let frozenWorld = snapshotCurrentFrozenWorld()

        workspace.preferredMonitorPoint = main.rect.topLeftCorner

        let didRestore = try await restoreFrozenWorldIfNeeded(frozenWorld, newlyDetectedWindow: window)

        XCTAssertTrue(didRestore)
        XCTAssertEqual(workspace.preferredMonitorPointForTesting, secondary.rect.topLeftCorner)
    }

    func testRestoreFrozenWorldIfNeededUsesNativeFallbackWorkspaceForMissingVisibleWorkspace() async throws {
        let occupiedWorkspace = Workspace.get(byName: "occupied")
        let window = TestWindow.new(id: 31, parent: occupiedWorkspace.rootTilingContainer)
        let emptyWorkspace = Workspace.get(byName: "empty")
        _ = emptyWorkspace.focusWorkspace()

        let frozenWorld = FrozenWorld(
            workspaces: [FrozenWorkspace(occupiedWorkspace)],
            monitors: monitors.map(FrozenMonitor.init),
            windowIds: [window.windowId],
        )

        _ = occupiedWorkspace.focusWorkspace()
        Workspace.reconcileWorkspaceState()
        XCTAssertNil(Workspace.existing(byName: emptyWorkspace.name))

        let didRestore = try await restoreFrozenWorldIfNeeded(frozenWorld, newlyDetectedWindow: window)
        XCTAssertTrue(didRestore)

        XCTAssertEqual(mainMonitor.activeWorkspace.projectId, workspaceProjectDefaultId)
        XCTAssertTrue(mainMonitor.activeWorkspace.isEffectivelyEmpty)
        XCTAssertTrue(mainMonitor.activeWorkspace !== occupiedWorkspace)
    }

    func testRestoreFrozenWorldIfNeededRestoresWindowFullscreenState() async throws {
        let workspace = Workspace.get(byName: "restore")
        let tiled = TestWindow.new(id: 41, parent: workspace.rootTilingContainer)
        let floating = TestWindow.new(id: 42, parent: workspace)
        tiled.isFullscreen = true
        tiled.noOuterGapsInFullscreen = true
        floating.isFullscreen = true
        floating.noOuterGapsInFullscreen = false

        let frozenWorld = FrozenWorld(
            workspaces: [FrozenWorkspace(workspace)],
            monitors: monitors.map(FrozenMonitor.init),
            windowIds: [tiled.windowId, floating.windowId],
        )

        tiled.isFullscreen = false
        tiled.noOuterGapsInFullscreen = false
        floating.isFullscreen = false
        floating.noOuterGapsInFullscreen = true

        let didRestore = try await restoreFrozenWorldIfNeeded(frozenWorld, newlyDetectedWindow: tiled)

        XCTAssertTrue(didRestore)
        XCTAssertTrue(tiled.isFullscreen)
        XCTAssertTrue(tiled.noOuterGapsInFullscreen)
        XCTAssertTrue(floating.isFullscreen)
        XCTAssertFalse(floating.noOuterGapsInFullscreen)
    }

    func testRestoreFrozenWorldMigratesLegacyTopTabGroupIntoSidebarTabs() async throws {
        let workspace = Workspace.get(byName: "restore-tabs")
        workspace.markAsAutomaticallyNamed()
        let tabGroup = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: 1, .h, .tabGroup, index: 0)
        let first = TestWindow.new(id: 141, parent: tabGroup, adaptiveWeight: 1)
        let active = TestWindow.new(id: 142, parent: tabGroup, adaptiveWeight: 1)
        active.markAsMostRecentChild()
        let frozenWorld = FrozenWorld(
            workspaces: [FrozenWorkspace(workspace)],
            monitors: monitors.map(FrozenMonitor.init),
            windowIds: [first.windowId, active.windowId],
        )
        guard case .container(let frozenTabGroup) = frozenWorld.workspaces[0].rootTilingNode.children[0] else {
            return XCTFail("Expected frozen legacy tab group")
        }
        XCTAssertEqual(frozenTabGroup.layout, .tabGroup)
        XCTAssertEqual(frozenTabGroup.children.count, 2)
        first.bind(to: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        active.bind(to: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        _ = tabGroup.bind(to: NilTreeNode.instance, adaptiveWeight: WEIGHT_DOESNT_MATTER, index: INDEX_BIND_LAST)
        XCTAssertFalse(workspace.rootTilingContainer.allTabbedContainersRecursive.contains { $0.layout == .tabGroup })

        let didRestore = try await restoreFrozenWorldIfNeeded(frozenWorld, newlyDetectedWindow: first)

        XCTAssertTrue(didRestore)
        XCTAssertFalse(Workspace.all.contains { workspace in
            workspace.rootTilingContainer.allTabbedContainersRecursive.contains { $0.layout == .tabGroup && $0.children.count > 1 }
        })
        XCTAssertTrue(active.nodeWorkspace === workspace)
        XCTAssertTrue(first.nodeWorkspace !== workspace)
        XCTAssertEqual(first.nodeWorkspace?.rootTilingContainer.children, [first])
        XCTAssertEqual(workspace.rootTilingContainer.children, [active])
        XCTAssertEqual(workspace.rootTilingContainer.layout, .tiles)
    }

    func testRestoreFrozenWorldIfNeededRetilesRestoredMinimizedWindowAfterNativeUnminimize() async throws {
        let workspace = Workspace.get(byName: "restore")
        let window = TestWindow.new(id: 43, parent: workspace.rootTilingContainer)
        window.rememberMacOsLayoutOrigin(detachFromWorkspace: true)
        window.nativeIsMacosMinimized = true
        window.bind(to: macosMinimizedWindowsContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)

        let frozenWorld = FrozenWorld(
            workspaces: [FrozenWorkspace(workspace)],
            monitors: monitors.map(FrozenMonitor.init),
            windowIds: [window.windowId],
        )

        let stagingWorkspace = Workspace.get(byName: "staging")
        window.nativeIsMacosMinimized = false
        window.layoutReason = .standard
        window.bindAsFloatingWindow(to: stagingWorkspace)

        let didRestore = try await restoreFrozenWorldIfNeeded(frozenWorld, newlyDetectedWindow: window)

        XCTAssertFalse(didRestore)
        XCTAssertEqual(window.nodeWorkspace, stagingWorkspace)
        XCTAssertTrue(stagingWorkspace.floatingWindows.contains(window))
        XCTAssertEqual(window.layoutReason, .standard)
    }

    func testRestoreFrozenWorldIfNeededKeepsStillMinimizedWindowInMinimizedContainer() async throws {
        let workspace = Workspace.get(byName: "restore")
        let window = TestWindow.new(id: 44, parent: workspace.rootTilingContainer)
        window.rememberMacOsLayoutOrigin(detachFromWorkspace: true)
        window.nativeIsMacosMinimized = true
        window.bind(to: macosMinimizedWindowsContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)

        let frozenWorld = FrozenWorld(
            workspaces: [FrozenWorkspace(workspace)],
            monitors: monitors.map(FrozenMonitor.init),
            windowIds: [window.windowId],
        )

        let stagingWorkspace = Workspace.get(byName: "staging")
        window.layoutReason = .standard
        window.bindAsFloatingWindow(to: stagingWorkspace)

        let didRestore = try await restoreFrozenWorldIfNeeded(frozenWorld, newlyDetectedWindow: window)

        XCTAssertFalse(didRestore)
        XCTAssertEqual(window.nodeWorkspace, stagingWorkspace)
        XCTAssertTrue(stagingWorkspace.floatingWindows.contains(window))
        XCTAssertEqual(window.layoutReason, .standard)
    }
}
