import AppKit
@testable import AppBundle
import XCTest

struct WorkspaceSidebarDragTestMonitor: Monitor {
    let monitorAppKitNsScreenScreensId: Int
    let name: String
    let rect: Rect
    let visibleRect: Rect
    let isMain: Bool

    var width: CGFloat { rect.width }
    var height: CGFloat { rect.height }
}

private final class WorkspaceSidebarDragPointerObserver: NSObject {
    var endedPointer: CGPoint?

    @objc func handlePointerEnded(_ notification: Notification) {
        endedPointer = (notification.userInfo?[workspaceSidebarDragPointerUserInfoKey] as? NSValue)?.pointValue
    }
}

private func makeWorkspaceSidebarSearchFixture() -> [WorkspaceSidebarWorkspaceViewModel] {
    let releaseNotes = WorkspaceSidebarWindowViewModel(
        windowId: 101,
        workspaceName: "coding",
        appName: "Xcode",
        appBundleId: "com.apple.dt.Xcode",
        appBundlePath: "/Applications/Xcode.app",
        title: "ReleaseNotes.swift",
        isFocused: false,
    )
    let terminal = WorkspaceSidebarWindowViewModel(
        windowId: 102,
        workspaceName: "coding",
        appName: "Terminal",
        appBundleId: "com.apple.Terminal",
        appBundlePath: "/System/Applications/Utilities/Terminal.app",
        title: "server",
        isFocused: false,
    )
    let browserTab = WorkspaceSidebarWindowViewModel(
        windowId: 202,
        workspaceName: "research",
        appName: "Safari",
        appBundleId: "com.apple.Safari",
        appBundlePath: "/Applications/Safari.app",
        title: "WindowServer docs",
        isFocused: false,
    )
    let notesTab = WorkspaceSidebarWindowViewModel(
        windowId: 203,
        workspaceName: "research",
        appName: "Notes",
        appBundleId: "com.apple.Notes",
        appBundlePath: "/System/Applications/Notes.app",
        title: "Ideas",
        isFocused: false,
    )
    let browserGroup = WorkspaceSidebarTabGroupViewModel(
        representativeWindowId: 201,
        workspaceName: "research",
        title: "Docs",
        windowCount: 2,
        isFocused: false,
        tabs: [browserTab, notesTab],
    )

    return [
        WorkspaceSidebarWorkspaceViewModel(
            name: "coding",
            projectId: workspaceProjectDefaultId,
            displayName: "Coding",
            sidebarLabel: "Coding",
            isGeneratedName: false,
            tabSummary: WorkspaceSidebarTabSummaryViewModel(
                title: "ReleaseNotes.swift",
                subtitle: "Xcode",
                appBundleId: "com.apple.dt.Xcode",
                appBundlePath: "/Applications/Xcode.app",
                windowCount: 2,
                isEmpty: false,
            ),
            monitorScopeId: workspaceSidebarDefaultScopeId,
            monitorName: nil,
            isFocused: false,
            isVisible: true,
            items: [
                WorkspaceSidebarItemViewModel(kind: .window(releaseNotes)),
                WorkspaceSidebarItemViewModel(kind: .window(terminal)),
            ],
        ),
        WorkspaceSidebarWorkspaceViewModel(
            name: "research",
            projectId: workspaceProjectDefaultId,
            displayName: "Research",
            sidebarLabel: "Research",
            isGeneratedName: false,
            tabSummary: WorkspaceSidebarTabSummaryViewModel(
                title: "WindowServer docs",
                subtitle: "Safari",
                appBundleId: "com.apple.Safari",
                appBundlePath: "/Applications/Safari.app",
                windowCount: 2,
                isEmpty: false,
            ),
            monitorScopeId: workspaceSidebarDefaultScopeId,
            monitorName: nil,
            isFocused: false,
            isVisible: true,
            items: [WorkspaceSidebarItemViewModel(kind: .tabGroup(browserGroup))],
        ),
    ]
}

private func workspaceSidebarSnapshotForTopFilterBar(
    projects: [WorkspaceSidebarProjectViewModel],
    monitorScopes: [WorkspaceSidebarMonitorScopeViewModel],
) -> WorkspaceSidebarSnapshot {
    WorkspaceSidebarSnapshot(
        workspaces: [],
        projects: projects,
        activeProjectId: workspaceProjectDefaultId,
        monitorScopes: monitorScopes,
        selectedMonitorScopeId: workspaceSidebarDefaultScopeId,
        targetMonitorScopeId: workspaceSidebarDefaultScopeId,
        focusedMonitorScopeId: "",
        visibleWidth: 240,
        isPinnedExpanded: false,
        hoveredWorkspaceName: nil,
        dropPreview: nil,
        configuration: WorkspaceSidebarConfiguration(
            collapsedWidth: 44,
            expandedWidth: 240,
            topPadding: 8,
            showMonitorSelector: true,
            showsDate: false,
            showsStatusPills: false,
            widgets: [],
        ),
    )
}

final class WorkspaceSidebarDragTest: XCTestCase {
    @MainActor
    func testTopFilterBarHidesForSingleProjectWithoutFocusFilter() {
        let view = WorkspaceSidebarView(snapshot: workspaceSidebarSnapshotForTopFilterBar(
            projects: [
                WorkspaceSidebarProjectViewModel(id: workspaceProjectDefaultId, displayName: "Default", colorHex: nil),
            ],
            monitorScopes: [
                WorkspaceSidebarMonitorScopeViewModel(
                    id: workspaceSidebarDefaultScopeId,
                    displayName: "Default",
                    subtitle: nil,
                    systemImageName: "display",
                    isFocusedMonitor: false,
                ),
            ],
        ))

        XCTAssertFalse(view.shouldShowTopFilterBar)
    }

    @MainActor
    func testTopFilterBarShowsWhenFocusFilterIsEnabled() {
        let view = WorkspaceSidebarView(snapshot: workspaceSidebarSnapshotForTopFilterBar(
            projects: [
                WorkspaceSidebarProjectViewModel(id: workspaceProjectDefaultId, displayName: "Default", colorHex: nil),
            ],
            monitorScopes: [
                WorkspaceSidebarMonitorScopeViewModel(
                    id: workspaceSidebarDefaultScopeId,
                    displayName: "Default",
                    subtitle: nil,
                    systemImageName: "display",
                    isFocusedMonitor: false,
                ),
                WorkspaceSidebarMonitorScopeViewModel(
                    id: workspaceSidebarFocusedScopeId,
                    displayName: "Focused",
                    subtitle: nil,
                    systemImageName: "scope",
                    isFocusedMonitor: false,
                ),
            ],
        ))

        XCTAssertTrue(view.shouldShowTopFilterBar)
    }

    @MainActor
    func testNormalSidebarContentFrameWidthIgnoresStaleWideVisibleWidth() {
        let layout = WorkspaceSidebarConfiguration(
            collapsedWidth: 44,
            expandedWidth: 240,
            topPadding: 8,
            showMonitorSelector: true,
            showsDate: false,
            showsStatusPills: false,
            widgets: [],
        )
        let snapshot = WorkspaceSidebarSnapshot(
            workspaces: [],
            projects: [
                WorkspaceSidebarProjectViewModel(id: workspaceProjectDefaultId, displayName: "Default", colorHex: nil),
            ],
            activeProjectId: workspaceProjectDefaultId,
            monitorScopes: [],
            selectedMonitorScopeId: workspaceSidebarDefaultScopeId,
            targetMonitorScopeId: workspaceSidebarDefaultScopeId,
            focusedMonitorScopeId: "",
            visibleWidth: 480,
            isPinnedExpanded: false,
            hoveredWorkspaceName: nil,
            dropPreview: nil,
            configuration: layout,
        )
        let view = WorkspaceSidebarView(snapshot: snapshot)
        let frameWidth = view.workspaceSidebarContentFrameWidth(expansionProgress: 1)

        XCTAssertEqual(frameWidth, workspaceSidebarExpandedSectionWidth(layout: layout))
        XCTAssertLessThan(frameWidth, snapshot.visibleWidth)
    }

    func testSidebarTabRowsShareVisualMetricsAcrossNestingLevels() {
        XCTAssertEqual(workspaceSidebarWorkspaceSectionHeaderHeight, workspaceSidebarTabRowHeight)
        XCTAssertEqual(workspaceSidebarNestedTabRowHeight, workspaceSidebarTabRowHeight)
        XCTAssertEqual(workspaceSidebarWorkspaceSectionHeightExpanded, workspaceSidebarTabRowHeight)
        XCTAssertEqual(workspaceSidebarHeaderRowLeadingPadding, workspaceSidebarRowHorizontalPadding)
        XCTAssertEqual(workspaceSidebarWindowRowsLeadingIndent, 0)
        XCTAssertEqual(workspaceSidebarListItemSpacing, workspaceSidebarUnifiedGap / 2)
        XCTAssertEqual(workspaceSidebarNestedRowSpacing, workspaceSidebarUnifiedGap / 2)
        XCTAssertEqual(workspaceSidebarFolderOuterVerticalMargin, 2)
        XCTAssertGreaterThan(workspaceSidebarTabGroupChildLeadingIndent, workspaceSidebarRowHorizontalPadding)
    }

    func testExpandedEmptyFolderDoesNotReserveContentHeight() {
        XCTAssertFalse(workspaceSidebarFolderShowsContent(
            isExpanded: true,
            hasItems: false,
            isWorkspaceDragTargeted: false,
            isShowingProjectedContent: false
        ))
        XCTAssertTrue(workspaceSidebarFolderShowsContent(
            isExpanded: true,
            hasItems: true,
            isWorkspaceDragTargeted: false,
            isShowingProjectedContent: false
        ))
    }

    func testEmptyFolderStillShowsProjectedDragContent() {
        XCTAssertTrue(workspaceSidebarFolderShowsContent(
            isExpanded: true,
            hasItems: false,
            isWorkspaceDragTargeted: false,
            isShowingProjectedContent: true
        ))
    }

    func testWorkspaceDragKeepsSourceAndOnlyLatestHoveredFolderVisuallyExpanded() {
        let source = WorkspaceProjectId("folder-1")
        let middle = WorkspaceProjectId("folder-2")
        let destination = WorkspaceProjectId("folder-3")
        let folders = [source, middle, destination]

        func visuallyExpandedFolders(hoveredFolder: WorkspaceProjectId) -> Set<WorkspaceProjectId> {
            Set(folders.filter { folderId in
                workspaceSidebarFolderIsVisuallyExpanded(
                    isExpanded: folderId == source,
                    isWorkspaceDragTargeted: folderId == hoveredFolder,
                    isShowingProjectedContent: false
                )
            })
        }

        XCTAssertEqual(visuallyExpandedFolders(hoveredFolder: middle), [source, middle])
        XCTAssertEqual(visuallyExpandedFolders(hoveredFolder: destination), [source, destination])
    }

    @MainActor
    func testTopFilterBarIgnoresProjectsForHardTabMigration() {
        let view = WorkspaceSidebarView(snapshot: workspaceSidebarSnapshotForTopFilterBar(
            projects: [
                WorkspaceSidebarProjectViewModel(id: workspaceProjectDefaultId, displayName: "Default", colorHex: nil),
                WorkspaceSidebarProjectViewModel(id: "project-1", displayName: "Folder 1", colorHex: nil),
            ],
            monitorScopes: [
                WorkspaceSidebarMonitorScopeViewModel(
                    id: workspaceSidebarDefaultScopeId,
                    displayName: "Default",
                    subtitle: nil,
                    systemImageName: "display",
                    isFocusedMonitor: false,
                ),
            ],
        ))

        XCTAssertFalse(view.shouldShowTopFilterBar)
    }

    @MainActor
    func testSidebarTopBarPlusCreatesNewTabOnTargetMonitor() {
        let snapshot = WorkspaceSidebarSnapshot(
            workspaces: [],
            projects: [
                WorkspaceSidebarProjectViewModel(id: workspaceProjectDefaultId, displayName: "Default", colorHex: nil),
            ],
            activeProjectId: workspaceProjectDefaultId,
            monitorScopes: [],
            selectedMonitorScopeId: workspaceSidebarDefaultScopeId,
            targetMonitorScopeId: "monitor:target",
            focusedMonitorScopeId: "monitor:focused",
            visibleWidth: 240,
            isPinnedExpanded: false,
            hoveredWorkspaceName: nil,
            dropPreview: nil,
            configuration: WorkspaceSidebarConfiguration(
                collapsedWidth: 44,
                expandedWidth: 240,
                topPadding: 8,
                showMonitorSelector: false,
                showsDate: false,
                showsStatusPills: false,
                widgets: [],
            ),
        )

        let action = WorkspaceSidebarView(snapshot: snapshot).sidebarNewTabAction()

        XCTAssertEqual(action, .createWorkspace(projectId: workspaceProjectDefaultId, monitorScopeId: "monitor:target"))
    }

    @MainActor
    func testWorkspaceSidebarSnapshotKeepsLegacyProjectIdsForTabGroups() async {
        setUpWorkspacesForTests()
        let project = createWorkspaceProject()
        let projectWorkspace = Workspace.all.first { $0.projectId == project.id }.orDie()
        _ = TestWindow.new(id: 901, parent: projectWorkspace.rootTilingContainer)
        let projectWorkspaceNames = Set(Workspace.all.filter { $0.projectId == project.id }.map(\.name))

        XCTAssertFalse(projectWorkspaceNames.isEmpty)
        XCTAssertFalse(projectWorkspaceNames.contains(focus.workspace.name))

        let sidebarWorkspaces = await buildWorkspaceSidebarWorkspaceViewModels(
            currentFocus: focus,
            workspaceLabels: [:],
            availableMonitors: sortedMonitors,
        )
        let flattenedProjectWorkspaceNames = Set(sidebarWorkspaces.filter { projectWorkspaceNames.contains($0.name) }.map(\.name))

        XCTAssertEqual(flattenedProjectWorkspaceNames, projectWorkspaceNames)
        XCTAssertTrue(sidebarWorkspaces.contains { $0.projectId == project.id })
    }

    @MainActor
    func testFolderSectionsKeepUnfoldedAtBottom() {
        let projectId = WorkspaceProjectId("project-1")
        let emptyProjectId = WorkspaceProjectId("project-empty")
        var workspaces = makeWorkspaceSidebarSearchFixture()
        let groupedWindow = WorkspaceSidebarWindowViewModel(
            windowId: 301,
            workspaceName: "grouped",
            appName: "Dia",
            appBundleId: "company.thebrowser.dia",
            appBundlePath: "/Applications/Dia.app",
            title: "Client brief",
            isFocused: false,
        )
        let grouped = WorkspaceSidebarWorkspaceViewModel(
            name: "grouped",
            projectId: workspaceProjectDefaultId,
            folderId: WorkspaceFolderId(projectId),
            displayName: "Grouped",
            sidebarLabel: "Grouped",
            isGeneratedName: false,
            tabSummary: WorkspaceSidebarTabSummaryViewModel(
                title: "Client brief",
                subtitle: "Dia",
                appBundleId: "company.thebrowser.dia",
                appBundlePath: "/Applications/Dia.app",
                windowCount: 1,
                isEmpty: false,
            ),
            monitorScopeId: workspaceSidebarDefaultScopeId,
            monitorName: nil,
            isFocused: false,
            isVisible: false,
            items: [WorkspaceSidebarItemViewModel(kind: .window(groupedWindow))],
        )
        let emptyGrouped = WorkspaceSidebarWorkspaceViewModel(
            name: "empty-grouped",
            projectId: workspaceProjectDefaultId,
            folderId: WorkspaceFolderId(emptyProjectId),
            displayName: "New Tab",
            sidebarLabel: "",
            isGeneratedName: true,
            tabSummary: .empty,
            monitorScopeId: workspaceSidebarDefaultScopeId,
            monitorName: nil,
            isFocused: false,
            isVisible: false,
            items: [],
        )
        workspaces.append(grouped)
        workspaces.append(emptyGrouped)

        let sections = workspaceSidebarFolderSections(
            projectId: workspaceProjectDefaultId,
            workspaces: workspaces,
            folders: [
                WorkspaceSidebarFolderViewModel(id: WorkspaceFolderId(projectId), projectId: workspaceProjectDefaultId, displayName: "Client", colorHex: nil, isUnfolded: false),
                WorkspaceSidebarFolderViewModel(id: WorkspaceFolderId(emptyProjectId), projectId: workspaceProjectDefaultId, displayName: "Empty", colorHex: nil, isUnfolded: false),
                WorkspaceSidebarFolderViewModel(id: workspaceFolderDefaultId, projectId: workspaceProjectDefaultId, displayName: workspaceDefaultFolderDisplayName, colorHex: nil, isUnfolded: true),
            ],
        )

        XCTAssertEqual(sections.map(\.project.id), [projectId, emptyProjectId, workspaceProjectDefaultId])
        XCTAssertEqual(sections[0].project.displayName, "Client")
        XCTAssertEqual(sections[0].workspaces.map(\.name), ["grouped"])
        XCTAssertEqual(sections[1].project.displayName, "Empty")
        XCTAssertEqual(sections[1].workspaces.map(\.name), [])
        XCTAssertTrue(sections[2].isDefault)
        XCTAssertEqual(sections[2].workspaces.map(\.name), ["coding", "research"])
        XCTAssertTrue(workspaceSidebarFolderUsesGroupPresentation(sections[0].folder))
        XCTAssertFalse(workspaceSidebarFolderUsesGroupPresentation(sections[2].folder))
    }

    func testCompactFolderSectionsKeepOnlyCurrentFolder() {
        let currentProjectId = WorkspaceProjectId("project-current")
        let targetScopeId = "monitor:0.0,0.0"
        let currentFolderWorkspace = WorkspaceSidebarWorkspaceViewModel(
            name: "active-codex",
            projectId: workspaceProjectDefaultId,
            folderId: WorkspaceFolderId(currentProjectId),
            displayName: "Codex",
            sidebarLabel: "",
            isGeneratedName: false,
            tabSummary: WorkspaceSidebarTabSummaryViewModel(
                title: "Codex",
                subtitle: nil,
                appBundleId: "com.openai.codex",
                appBundlePath: "/Applications/Codex.app",
                windowCount: 1,
                isEmpty: false,
            ),
            monitorScopeId: targetScopeId,
            monitorName: nil,
            isFocused: true,
            isVisible: true,
            items: [],
        )
        let unfoldedWorkspace = WorkspaceSidebarWorkspaceViewModel(
            name: "self",
            projectId: workspaceProjectDefaultId,
            displayName: "Self",
            sidebarLabel: "",
            isGeneratedName: false,
            tabSummary: WorkspaceSidebarTabSummaryViewModel(
                title: "Self",
                subtitle: nil,
                appBundleId: "dev.self",
                appBundlePath: "/Applications/Self.app",
                windowCount: 1,
                isEmpty: false,
            ),
            monitorScopeId: targetScopeId,
            monitorName: nil,
            isFocused: false,
            isVisible: false,
            items: [],
        )
        let sections = workspaceSidebarFolderSections(
            projectId: workspaceProjectDefaultId,
            workspaces: [currentFolderWorkspace, unfoldedWorkspace],
            folders: [
                WorkspaceSidebarFolderViewModel(id: WorkspaceFolderId(currentProjectId), projectId: workspaceProjectDefaultId, displayName: "s&p backtest", colorHex: nil, isUnfolded: false),
                WorkspaceSidebarFolderViewModel(id: workspaceFolderDefaultId, projectId: workspaceProjectDefaultId, displayName: workspaceDefaultFolderDisplayName, colorHex: nil, isUnfolded: true),
            ]
        )
        let compactSections = workspaceSidebarCompactFolderSections(
            sections,
            currentProjectId: workspaceSidebarCurrentFolderProjectId(
                workspaces: [currentFolderWorkspace, unfoldedWorkspace],
                targetMonitorScopeId: targetScopeId
            )
        )

        XCTAssertEqual(sections.map(\.project.id), [currentProjectId, workspaceProjectDefaultId])
        XCTAssertEqual(compactSections.map(\.project.id), [currentProjectId])
        XCTAssertEqual(compactSections.singleOrNil()?.workspaces.map(\.name), ["active-codex"])
    }

    @MainActor
    func testFolderSectionsKeepEmptyUnfoldedFolderWhenAllTabsAreFoldered() {
        let projectId = WorkspaceProjectId("project-1")
        let emptyDefault = WorkspaceSidebarWorkspaceViewModel(
            name: "empty-default",
            projectId: workspaceProjectDefaultId,
            displayName: "Tab 1",
            sidebarLabel: "",
            isGeneratedName: true,
            tabSummary: .empty,
            monitorScopeId: workspaceSidebarDefaultScopeId,
            monitorName: nil,
            isFocused: true,
            isVisible: true,
            items: [],
        )
        let foldered = WorkspaceSidebarWorkspaceViewModel(
            name: "foldered",
            projectId: workspaceProjectDefaultId,
            folderId: WorkspaceFolderId(projectId),
            displayName: "Foldered",
            sidebarLabel: "",
            isGeneratedName: false,
            tabSummary: WorkspaceSidebarTabSummaryViewModel(
                title: "Foldered",
                subtitle: nil,
                appBundleId: nil,
                appBundlePath: nil,
                windowCount: 1,
                isEmpty: false,
            ),
            monitorScopeId: workspaceSidebarDefaultScopeId,
            monitorName: nil,
            isFocused: false,
            isVisible: false,
            items: [],
        )

        let sections = workspaceSidebarFolderSections(
            projectId: workspaceProjectDefaultId,
            workspaces: [emptyDefault, foldered],
            folders: [
                WorkspaceSidebarFolderViewModel(id: WorkspaceFolderId(projectId), projectId: workspaceProjectDefaultId, displayName: "Folder", colorHex: nil, isUnfolded: false),
                WorkspaceSidebarFolderViewModel(id: workspaceFolderDefaultId, projectId: workspaceProjectDefaultId, displayName: workspaceDefaultFolderDisplayName, colorHex: nil, isUnfolded: true),
            ],
        )

        XCTAssertEqual(sections.map(\.project.id), [projectId, workspaceProjectDefaultId])
        XCTAssertEqual(sections[0].workspaces.map(\.name), ["foldered"])
        XCTAssertEqual(sections[1].workspaces.map(\.name), [])
    }

    @MainActor
    func testSidebarAutoHidePreferenceDefaultsToStickyAndRoundTrips() {
        resetWorkspaceSidebarUIPreferencesForTests()

        XCTAssertFalse(workspaceSidebarAutoHidePreference())
        XCTAssertTrue(workspaceSidebarPinnedExpandedPreference())

        setWorkspaceSidebarAutoHidePreference(true)
        XCTAssertTrue(workspaceSidebarAutoHidePreference())
        XCTAssertFalse(workspaceSidebarPinnedExpandedPreference())
        XCTAssertTrue(TrayMenuModel.shared.isWorkspaceSidebarAutoHideEnabled)
        XCTAssertFalse(TrayMenuModel.shared.isWorkspaceSidebarPinnedExpanded)

        setWorkspaceSidebarPinnedExpandedPreference(false)
        XCTAssertTrue(workspaceSidebarAutoHidePreference())
        XCTAssertFalse(workspaceSidebarPinnedExpandedPreference())

        setWorkspaceSidebarPinnedExpandedPreference(true)
        XCTAssertFalse(workspaceSidebarAutoHidePreference())
        XCTAssertTrue(workspaceSidebarPinnedExpandedPreference())
        XCTAssertFalse(TrayMenuModel.shared.isWorkspaceSidebarAutoHideEnabled)
        XCTAssertTrue(TrayMenuModel.shared.isWorkspaceSidebarPinnedExpanded)
    }

    @MainActor
    func testSidebarAppearancePreferenceParsesLightAndDark() {
        XCTAssertEqual(workspaceSidebarAppearancePreference(rawValue: "light"), .light)
        XCTAssertEqual(workspaceSidebarAppearancePreference(rawValue: "dark"), .dark)
        XCTAssertNil(workspaceSidebarAppearancePreference(rawValue: ""))
    }

    func testHiddenNotePadDoesNotHideOtherWidgets() {
        var notePad = WorkspaceSidebarWidgetConfig()
        notePad.id = "todo-list"
        notePad.type = .builtInTodoList

        var weeklyRing = WorkspaceSidebarWidgetConfig()
        weeklyRing.id = "period-heatmap"
        weeklyRing.type = .builtInPeriodHeatmap

        XCTAssertFalse(workspaceSidebarWidgetIsVisible(notePad, showsNotePad: false))
        XCTAssertTrue(workspaceSidebarWidgetIsVisible(weeklyRing, showsNotePad: false))
        XCTAssertTrue(workspaceSidebarHasVisibleWidgets([notePad, weeklyRing], showsNotePad: false))
    }

    @MainActor
    func testFolderExpansionPreferenceAllowsMultipleFoldersExpanded() {
        setUpWorkspacesForTests()
        let first = createWorkspaceFolder()
        let second = createWorkspaceFolder()

        XCTAssertTrue(workspaceSidebarFolderIsExpanded(workspaceFolderDefaultId))
        XCTAssertTrue(workspaceSidebarFolderIsExpanded(first.id))
        XCTAssertTrue(workspaceSidebarFolderIsExpanded(second.id))

        setWorkspaceSidebarFolderExpanded(first.id, isExpanded: false)
        XCTAssertTrue(workspaceSidebarFolderIsExpanded(workspaceFolderDefaultId))
        XCTAssertFalse(workspaceSidebarFolderIsExpanded(first.id))
        XCTAssertTrue(workspaceSidebarFolderIsExpanded(second.id))

        setWorkspaceSidebarFolderExpanded(first.id, isExpanded: true)
        XCTAssertTrue(workspaceSidebarFolderIsExpanded(workspaceFolderDefaultId))
        XCTAssertTrue(workspaceSidebarFolderIsExpanded(first.id))
        XCTAssertTrue(workspaceSidebarFolderIsExpanded(second.id))

        setWorkspaceSidebarFolderExpanded(second.id, isExpanded: false)
        XCTAssertTrue(workspaceSidebarFolderIsExpanded(workspaceFolderDefaultId))
        XCTAssertTrue(workspaceSidebarFolderIsExpanded(first.id))
        XCTAssertFalse(workspaceSidebarFolderIsExpanded(second.id))
    }

    func testFolderExpansionMigratesLegacyProjectPreferenceToUnfoldedFolder() {
        setUpWorkspacesForTests()
        let project = createWorkspaceProject()
        let unfoldedFolderId = winMuxWorkspaceState.unfoldedFolderId(for: project.id)
        UserDefaults.standard.setValue(
            [project.id.rawValue, "unknown-folder"],
            forKey: "workspaceSidebar.collapsedFolderIds"
        )

        XCTAssertFalse(workspaceSidebarFolderIsExpanded(unfoldedFolderId))
        XCTAssertTrue(normalizeWorkspaceSidebarFolderExpansionPreference())
        XCTAssertEqual(
            collapsedWorkspaceSidebarFolderIdsPreference(),
            [unfoldedFolderId.rawValue]
        )
    }

    @MainActor
    func testWorkspaceSidebarTabSummaryUsesOnlyManualLabel() async throws {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "coding")
        workspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        _ = TestWindow.new(id: 2, parent: workspace.rootTilingContainer).focusWindow()

        let sidebarWorkspaces = await buildWorkspaceSidebarWorkspaceViewModels(
            currentFocus: focus,
            workspaceLabels: [workspace.name: "Research"],
            availableMonitors: sortedMonitors,
        )
        let model = try XCTUnwrap(sidebarWorkspaces.first { $0.name == workspace.name })

        XCTAssertEqual(model.displayName, "Research")
        XCTAssertEqual(model.tabSummary.title, "Research")
        XCTAssertNil(model.tabSummary.subtitle)
        XCTAssertEqual(model.tabSummary.windowCount, 2)
        XCTAssertFalse(model.tabSummary.isEmpty)
    }

    @MainActor
    func testWorkspaceSidebarManualTabTitleSticksWhenFocusedWindowChanges() async throws {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "coding")
        workspace.markAsAutomaticallyNamed()
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let second = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        _ = first.focusWindow()

        var sidebarWorkspaces = await buildWorkspaceSidebarWorkspaceViewModels(
            currentFocus: focus,
            workspaceLabels: [workspace.name: "Research"],
            availableMonitors: sortedMonitors,
        )
        var model = try XCTUnwrap(sidebarWorkspaces.first { $0.name == workspace.name })

        XCTAssertEqual(model.tabSummary.title, "Research")
        XCTAssertNil(model.tabSummary.subtitle)

        _ = second.focusWindow()
        sidebarWorkspaces = await buildWorkspaceSidebarWorkspaceViewModels(
            currentFocus: focus,
            workspaceLabels: [workspace.name: "Research"],
            availableMonitors: sortedMonitors,
        )
        model = try XCTUnwrap(sidebarWorkspaces.first { $0.name == workspace.name })

        XCTAssertEqual(model.tabSummary.title, "Research")
        XCTAssertNil(model.tabSummary.subtitle)
        XCTAssertEqual(model.tabSummary.windowCount, 2)
    }

    @MainActor
    func testWorkspaceSidebarComposedTabSummaryUsesAppNamesWithoutManualLabel() async throws {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "coding")
        workspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        _ = TestWindow.new(id: 2, parent: workspace.rootTilingContainer).focusWindow()

        let sidebarWorkspaces = await buildWorkspaceSidebarWorkspaceViewModels(
            currentFocus: focus,
            workspaceLabels: [:],
            availableMonitors: sortedMonitors,
        )
        let model = try XCTUnwrap(sidebarWorkspaces.first { $0.name == workspace.name })

        XCTAssertEqual(model.tabSummary.title, "bobko.WinMux.test-app & 1 other")
        XCTAssertNil(model.tabSummary.subtitle)
        XCTAssertEqual(model.tabSummary.windowCount, 2)
    }

    @MainActor
    func testWorkspaceSidebarComposedTabSummaryUsesRepresentativeAppAndOtherCount() async throws {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "coding")
        workspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        _ = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        _ = TestWindow.new(id: 3, parent: workspace.rootTilingContainer).focusWindow()

        let sidebarWorkspaces = await buildWorkspaceSidebarWorkspaceViewModels(
            currentFocus: focus,
            workspaceLabels: [:],
            availableMonitors: sortedMonitors,
        )
        let model = try XCTUnwrap(sidebarWorkspaces.first { $0.name == workspace.name })

        XCTAssertEqual(model.tabSummary.title, "bobko.WinMux.test-app & 2 others")
        XCTAssertNil(model.tabSummary.subtitle)
        XCTAssertEqual(model.tabSummary.windowCount, 3)
    }

    @MainActor
    func testWorkspaceSidebarModelExcludesHiddenEmptyTabs() async throws {
        setUpWorkspacesForTests()
        let active = Workspace.get(byName: "active")
        active.markAsAutomaticallyNamed()
        active.seedMonitorIfNeeded(mainMonitor)
        _ = TestWindow.new(id: 1, parent: active.rootTilingContainer).focusWindow()
        let empty = Workspace.get(byName: "empty")
        empty.markAsAutomaticallyNamed()
        empty.seedMonitorIfNeeded(mainMonitor)

        let sidebarWorkspaces = await buildWorkspaceSidebarWorkspaceViewModels(
            currentFocus: focus,
            workspaceLabels: [:],
            availableMonitors: sortedMonitors,
        )

        XCTAssertTrue(sidebarWorkspaces.contains { $0.name == active.name })
        XCTAssertFalse(sidebarWorkspaces.contains { $0.name == empty.name })
    }

    @MainActor
    func testWindowIntentPreviewRendersAboveProjectTabs() {
        XCTAssertGreaterThan(
            WindowDropIntentOverlayPanelController.shared.level.rawValue,
            WorkspaceSidebarPanel.shared.level.rawValue,
        )
    }

    @MainActor
    func testWindowChromeUsesNormalAppWindowLayer() {
        XCTAssertEqual(
            WinMuxPanelLayer.windowChrome.level.rawValue,
            NSWindow.Level.normal.rawValue,
        )
        XCTAssertLessThan(
            WinMuxPanelLayer.workspaceBackground.level.rawValue,
            WinMuxPanelLayer.windowChrome.level.rawValue,
        )
        XCTAssertLessThan(
            WinMuxPanelLayer.windowChrome.level.rawValue,
            WinMuxPanelLayer.windowIntentPreview.level.rawValue,
        )
    }

    @MainActor
    func testWorkspaceSidebarLayerIsAboveNonMenuWinMuxPanels() {
        for layer in WinMuxPanelLayer.allCases where layer != .workspaceSidebar && layer != .workspaceSidebarActionMenu {
            XCTAssertLessThan(
                layer.level.rawValue,
                WinMuxPanelLayer.workspaceSidebar.level.rawValue,
                "\(layer) should render below the workspace sidebar",
            )
        }
    }

    func testLeftMouseButtonPressedUsesBitmask() {
        XCTAssertTrue(isLeftMouseButtonPressed(mask: 0b1))
        XCTAssertTrue(isLeftMouseButtonPressed(mask: 0b11))
        XCTAssertFalse(isLeftMouseButtonPressed(mask: 0b10))
        XCTAssertFalse(isLeftMouseButtonPressed(mask: 0))
    }

    func testWorkspaceSidebarDragInProgressRecognizesSidebarMoveSession() {
        XCTAssertTrue(isWorkspaceSidebarDragInProgress(kind: .move, startedInSidebar: true))
    }

    func testWorkspaceSidebarDragInProgressIgnoresNonSidebarMoves() {
        XCTAssertFalse(isWorkspaceSidebarDragInProgress(kind: .move, startedInSidebar: false))
        XCTAssertFalse(isWorkspaceSidebarDragInProgress(kind: .none, startedInSidebar: true))
    }

    @MainActor
    func testWorkspaceSidebarItemDragCanBeResetAfterMissedEnd() {
        resetWorkspaceSidebarItemDrag()
        beginWorkspaceSidebarItemDrag()
        beginWorkspaceSidebarItemDrag()

        XCTAssertTrue(isWorkspaceSidebarItemDragActive())

        resetWorkspaceSidebarItemDrag()

        XCTAssertFalse(isWorkspaceSidebarItemDragActive())
    }

    @MainActor
    func testGlobalMouseUpFallbackEndsPureSidebarItemDrag() {
        resetWorkspaceSidebarItemDrag()
        beginWorkspaceSidebarItemDrag()
        MousePointerTracker.shared.note(point: CGPoint(x: 21, y: 34))
        let observer = WorkspaceSidebarDragPointerObserver()
        NotificationCenter.default.addObserver(
            observer,
            selector: #selector(WorkspaceSidebarDragPointerObserver.handlePointerEnded(_:)),
            name: workspaceSidebarDragPointerEndedNotification,
            object: nil,
        )
        defer {
            NotificationCenter.default.removeObserver(observer)
            resetWorkspaceSidebarItemDrag()
        }

        finishWorkspaceSidebarDragAfterGlobalMouseUp()

        XCTAssertFalse(isWorkspaceSidebarItemDragActive())
        XCTAssertEqual(observer.endedPointer, CGPoint(x: 21, y: 34))
    }

    @MainActor
    func testWorkspaceSidebarActionsExposeWindowAndTabGroupDragClosures() {
        var received: [String] = []
        let pointer = CGPoint(x: 12, y: 34)
        let actions = WorkspaceSidebarActions(
            windowDragChanged: { windowId, pointer in
                received.append("window-changed:\(windowId):\(pointer.x),\(pointer.y)")
            },
            windowDragEnded: { _, pointer in
                received.append("window-ended:\(pointer.x),\(pointer.y)")
            },
            tabGroupDragChanged: { windowId, pointer in
                received.append("group-changed:\(windowId):\(pointer.x),\(pointer.y)")
            },
            tabGroupDragEnded: { _, pointer in
                received.append("group-ended:\(pointer.x),\(pointer.y)")
            },
        )

        actions.windowDragChanged(101, pointer)
        actions.windowDragEnded(101, pointer)
        actions.tabGroupDragChanged(202, pointer)
        actions.tabGroupDragEnded(202, pointer)

        XCTAssertEqual(received, [
            "window-changed:101:12.0,34.0",
            "window-ended:12.0,34.0",
            "group-changed:202:12.0,34.0",
            "group-ended:12.0,34.0",
        ])
    }

    @MainActor
    func testWorkspaceSidebarFallbackWorkspaceNameFindsWindowsAndTabGroups() {
        let previousWorkspaces = TrayMenuModel.shared.workspaceSidebarWorkspaces
        defer { TrayMenuModel.shared.workspaceSidebarWorkspaces = previousWorkspaces }

        let window = WorkspaceSidebarWindowViewModel(
            windowId: 101,
            workspaceName: "coding",
            appName: "Editor",
            appBundleId: nil,
            appBundlePath: nil,
            title: "File.swift",
            isFocused: false,
        )
        let tab = WorkspaceSidebarWindowViewModel(
            windowId: 202,
            workspaceName: "research",
            appName: "Browser",
            appBundleId: nil,
            appBundlePath: nil,
            title: "Docs",
            isFocused: false,
        )
        let group = WorkspaceSidebarTabGroupViewModel(
            representativeWindowId: 201,
            workspaceName: "research",
            title: "Research",
            windowCount: 1,
            isFocused: false,
            tabs: [tab],
        )
        TrayMenuModel.shared.workspaceSidebarWorkspaces = [
            WorkspaceSidebarWorkspaceViewModel(
                name: "coding",
                projectId: workspaceProjectDefaultId,
                displayName: "Coding",
                sidebarLabel: "Coding",
                isGeneratedName: false,
                monitorScopeId: workspaceSidebarDefaultScopeId,
                monitorName: nil,
                isFocused: false,
                isVisible: true,
                items: [WorkspaceSidebarItemViewModel(kind: .window(window))],
            ),
            WorkspaceSidebarWorkspaceViewModel(
                name: "research",
                projectId: workspaceProjectDefaultId,
                displayName: "Research",
                sidebarLabel: "Research",
                isGeneratedName: false,
                monitorScopeId: workspaceSidebarDefaultScopeId,
                monitorName: nil,
                isFocused: false,
                isVisible: true,
                items: [WorkspaceSidebarItemViewModel(kind: .tabGroup(group))],
            ),
        ]

        XCTAssertEqual(workspaceSidebarFallbackWorkspaceName(for: 101), "coding")
        XCTAssertEqual(workspaceSidebarFallbackWorkspaceName(for: 201), "research")
        XCTAssertEqual(workspaceSidebarFallbackWorkspaceName(for: 202), "research")
        XCTAssertNil(workspaceSidebarFallbackWorkspaceName(for: 999))
    }

    func testWorkspaceSidebarSearchFiltersByWindowTitleAndAppName() {
        let workspaces = makeWorkspaceSidebarSearchFixture()

        let titleResults = workspaceSidebarFilteredWorkspacesByProject(
            [workspaceProjectDefaultId: workspaces],
            projects: [],
            query: "release",
        )[workspaceProjectDefaultId] ?? []
        XCTAssertEqual(titleResults.map(\.name), ["coding"])
        XCTAssertEqual(titleResults.first?.items.map(\.id), ["window:101"])

        let appResults = workspaceSidebarFilteredWorkspacesByProject(
            [workspaceProjectDefaultId: workspaces],
            projects: [],
            query: "safari",
        )[workspaceProjectDefaultId] ?? []
        XCTAssertEqual(appResults.map(\.name), ["research"])
        XCTAssertEqual(appResults.first?.items.map(\.id), ["group:201"])
        if case .tabGroup(let group) = appResults.first?.items.first?.kind {
            XCTAssertEqual(group.searchVisibleTabs?.map(\.windowId), [202])
        } else {
            XCTFail("Expected matching folder")
        }
        XCTAssertEqual(workspaceSidebarSearchSelections(workspaces: appResults), [.workspace("research")])
    }

    func testWorkspaceSidebarSearchKeepsFlatTabRowForTabMatch() {
        let workspaces = makeWorkspaceSidebarSearchFixture()

        let results = workspaceSidebarFilteredWorkspacesByProject(
            [workspaceProjectDefaultId: workspaces],
            projects: [],
            query: "coding",
        )[workspaceProjectDefaultId] ?? []

        XCTAssertEqual(results.map(\.name), ["coding"])
        XCTAssertEqual(results.first?.items.map(\.id), ["window:101", "window:102"])
        XCTAssertEqual(workspaceSidebarSearchSelections(workspaces: results), [.workspace("coding")])
    }

    func testWorkspaceSidebarSearchIsDisabledForSidebarEntryPoints() {
        let workspaces = makeWorkspaceSidebarSearchFixture()

        XCTAssertFalse(workspaceSidebarSearchIsEnabled)
        XCTAssertEqual(workspaceSidebarEffectiveSearchQuery("safari"), "")

        let results = workspaceSidebarFilteredWorkspacesByProject(
            [workspaceProjectDefaultId: workspaces],
            projects: [],
            query: workspaceSidebarEffectiveSearchQuery("safari"),
        )[workspaceProjectDefaultId] ?? []

        XCTAssertEqual(results.map(\.name), ["coding", "research"])
    }

    func testWorkspaceSidebarInlineTextDeletesLastWord() {
        XCTAssertEqual("release notes".deletingLastWord(), "release ")
        XCTAssertEqual("release notes   ".deletingLastWord(), "release ")
        XCTAssertEqual("release".deletingLastWord(), "")
    }

    func testWorkspaceSidebarDragPayloadRoundTripsWindowAndTabGroupIds() {
        XCTAssertEqual(
            WorkspaceSidebarDragPayload(encodedValue: WorkspaceSidebarDragPayload.window(17).encodedValue),
            .window(17),
        )
        XCTAssertEqual(
            WorkspaceSidebarDragPayload(encodedValue: WorkspaceSidebarDragPayload.tabGroup(23).encodedValue),
            .tabGroup(23),
        )
        XCTAssertNil(WorkspaceSidebarDragPayload(encodedValue: "bogus:23"))
    }

    func testWorkspaceSidebarCreateScopeUsesFocusedScopeForSyntheticSelections() {
        XCTAssertEqual(workspaceSidebarWorkspaceCreateScope(
            selectedScopeId: workspaceSidebarDefaultScopeId,
            targetMonitorScopeId: "monitor:target",
            focusedScopeId: "monitor:a"
        ), "monitor:target")
        XCTAssertEqual(workspaceSidebarWorkspaceCreateScope(
            selectedScopeId: workspaceSidebarFocusedScopeId,
            targetMonitorScopeId: "monitor:target",
            focusedScopeId: "monitor:a"
        ), "monitor:a")
        XCTAssertEqual(workspaceSidebarWorkspaceCreateScope(
            selectedScopeId: "monitor:b",
            targetMonitorScopeId: "monitor:target",
            focusedScopeId: "monitor:a"
        ), "monitor:b")
    }

    func testWorkspaceSidebarActivationRequiresNoEditAndNoDrag() {
        XCTAssertTrue(shouldHandleWorkspaceSidebarActivation(isEditing: false, isSidebarDragInProgress: false))
        XCTAssertFalse(shouldHandleWorkspaceSidebarActivation(isEditing: true, isSidebarDragInProgress: false))
        XCTAssertFalse(shouldHandleWorkspaceSidebarActivation(isEditing: false, isSidebarDragInProgress: true))
    }

    func testWorkspaceSidebarActivationBlocksWhileAnyWorkspaceIsEditing() {
        XCTAssertFalse(
            shouldHandleWorkspaceSidebarActivation(
                editingWorkspaceName: "a",
                isSidebarDragInProgress: false,
            ),
        )
        XCTAssertTrue(
            shouldHandleWorkspaceSidebarActivation(
                editingWorkspaceName: nil,
                isSidebarDragInProgress: false,
            ),
        )
    }

    func testWorkspaceSidebarDoubleClickRenameRequiresExpandedIdleTab() {
        XCTAssertTrue(shouldHandleWorkspaceSidebarRenameFromDoubleClick(
            isCompact: false,
            isEditing: false,
            isSidebarDragInProgress: false,
        ))
        XCTAssertFalse(shouldHandleWorkspaceSidebarRenameFromDoubleClick(
            isCompact: true,
            isEditing: false,
            isSidebarDragInProgress: false,
        ))
        XCTAssertFalse(shouldHandleWorkspaceSidebarRenameFromDoubleClick(
            isCompact: false,
            isEditing: true,
            isSidebarDragInProgress: false,
        ))
        XCTAssertFalse(shouldHandleWorkspaceSidebarRenameFromDoubleClick(
            isCompact: false,
            isEditing: false,
            isSidebarDragInProgress: true,
        ))
    }

    func testPendingWorkspaceActivationHighlightsUntilVisibleOnTargetMonitor() {
        let workspaces = makeWorkspaceSidebarSearchFixture()
        let target = workspaces[0]
        let pending = WorkspaceSidebarPendingActivation(
            workspaceName: target.name,
            targetMonitorScopeId: target.monitorScopeId
        )

        XCTAssertTrue(workspaceSidebarPendingActivationMatches(
            pending,
            workspace: target,
            targetMonitorScopeId: target.monitorScopeId,
            isActiveOnTargetMonitor: false
        ))
        XCTAssertFalse(workspaceSidebarPendingActivationMatches(
            pending,
            workspace: target,
            targetMonitorScopeId: target.monitorScopeId,
            isActiveOnTargetMonitor: true
        ))
        XCTAssertFalse(workspaceSidebarPendingActivationMatches(
            pending,
            workspace: target,
            targetMonitorScopeId: "monitor:other",
            isActiveOnTargetMonitor: false
        ))
        XCTAssertTrue(workspaceSidebarPendingActivationHasResolved(
            pending,
            workspaces: workspaces
        ))
        XCTAssertFalse(workspaceSidebarPendingActivationHasResolved(
            WorkspaceSidebarPendingActivation(
                workspaceName: target.name,
                targetMonitorScopeId: "monitor:other"
            ),
            workspaces: workspaces
        ))
    }

    func testProjectSwipeDirectionRequiresHorizontalIntent() {
        XCTAssertEqual(
            workspaceSidebarProjectSwipeDirection(horizontalTranslation: -40, verticalTranslation: 4),
            1,
        )
        XCTAssertEqual(
            workspaceSidebarProjectSwipeDirection(horizontalTranslation: 40, verticalTranslation: 4),
            -1,
        )
        XCTAssertNil(
            workspaceSidebarProjectSwipeDirection(horizontalTranslation: -40, verticalTranslation: 38),
        )
        XCTAssertNil(
            workspaceSidebarProjectSwipeDirection(horizontalTranslation: -4, verticalTranslation: 0),
        )
    }

    func testProjectSwipeCaptureIsDisabledForSidebarFoldersWhenProjectsAreDisabled() {
        XCTAssertFalse(workspaceSidebarProjectSwipeCaptureIsEnabled(
            projectsEnabled: false,
            projectCount: 0,
            isCompact: false
        ))
        XCTAssertFalse(workspaceSidebarProjectSwipeCaptureIsEnabled(
            projectsEnabled: false,
            projectCount: 2,
            isCompact: false
        ))
        XCTAssertFalse(workspaceSidebarProjectSwipeCaptureIsEnabled(
            projectsEnabled: true,
            projectCount: 0,
            isCompact: false
        ))
        XCTAssertFalse(workspaceSidebarProjectSwipeCaptureIsEnabled(
            projectsEnabled: true,
            projectCount: 1,
            isCompact: false
        ))
    }

    func testProjectSwipeNavigatesWithoutWrapping() {
        XCTAssertEqual(
            workspaceSidebarProjectIndexAfterSwipe(currentIndex: 1, projectCount: 3, direction: 1),
            2,
        )
        XCTAssertEqual(
            workspaceSidebarProjectIndexAfterSwipe(currentIndex: 1, projectCount: 3, direction: -1),
            0,
        )
        XCTAssertNil(
            workspaceSidebarProjectIndexAfterSwipe(currentIndex: 2, projectCount: 3, direction: 1),
        )
        XCTAssertNil(
            workspaceSidebarProjectIndexAfterSwipe(currentIndex: 0, projectCount: 3, direction: -1),
        )
    }

    func testProjectSwipeCreatesOnlyPastEdgesAfterBreakPoint() {
        XCTAssertFalse(
            shouldCreateWorkspaceSidebarProjectAfterSwipe(
                currentIndex: 1,
                projectCount: 3,
                direction: 1,
                distance: 120,
            ),
        )
        XCTAssertFalse(
            shouldCreateWorkspaceSidebarProjectAfterSwipe(
                currentIndex: 2,
                projectCount: 3,
                direction: 1,
                distance: 96,
            ),
        )
        XCTAssertTrue(
            shouldCreateWorkspaceSidebarProjectAfterSwipe(
                currentIndex: 2,
                projectCount: 3,
                direction: 1,
                distance: 110,
            ),
        )
        XCTAssertTrue(
            shouldCreateWorkspaceSidebarProjectAfterSwipe(
                currentIndex: 0,
                projectCount: 3,
                direction: -1,
                distance: 110,
            ),
        )
    }

    func testProjectSwipeFormationProgressOnlyAtEdges() {
        XCTAssertEqual(
            workspaceSidebarProjectEdgeCreationProgress(
                currentIndex: 1,
                projectCount: 3,
                direction: 1,
                distance: 100,
            ),
            0,
        )
        XCTAssertEqual(
            workspaceSidebarProjectEdgeCreationProgress(
                currentIndex: 2,
                projectCount: 3,
                direction: 1,
                distance: 22,
            ),
            0,
        )
        XCTAssertEqual(
            workspaceSidebarProjectEdgeCreationProgress(
                currentIndex: 2,
                projectCount: 3,
                direction: 1,
                distance: 104,
            ),
            1,
        )
    }

    func testProjectSwipeSwitchProgressReachesOneAtNavigationThreshold() {
        XCTAssertEqual(workspaceSidebarProjectSwipeSwitchProgress(distance: 0), 0)
        XCTAssertEqual(workspaceSidebarProjectSwipeSwitchProgress(distance: 22), 0.5)
        XCTAssertEqual(workspaceSidebarProjectSwipeSwitchProgress(distance: 44), 1)
        XCTAssertEqual(workspaceSidebarProjectSwipeSwitchProgress(distance: 64), 1)
    }

    func testProjectPagerDragTracksRealAdjacentPagesDirectly() {
        XCTAssertEqual(
            workspaceSidebarProjectPagerDragOffset(
                horizontalTranslation: -60,
                currentIndex: 0,
                projectCount: 2,
                pageWidth: 200,
            ),
            -60,
        )
        XCTAssertEqual(
            workspaceSidebarProjectPagerDragOffset(
                horizontalTranslation: -240,
                currentIndex: 0,
                projectCount: 2,
                pageWidth: 200,
            ),
            -200,
        )
    }

    func testProjectPagerDragUsesResistanceAtProjectEdges() {
        XCTAssertEqual(
            workspaceSidebarProjectPagerDragOffset(
                horizontalTranslation: 120,
                currentIndex: 0,
                projectCount: 1,
                pageWidth: 200,
            ),
            52,
        )
        XCTAssertEqual(
            workspaceSidebarProjectPagerDragOffset(
                horizontalTranslation: -120,
                currentIndex: 0,
                projectCount: 1,
                pageWidth: 200,
            ),
            -52,
        )
    }

    func testProjectHueIsStableAndNormalized() {
        let firstHue = workspaceSidebarProjectHue(projectId: "project-alpha")
        let secondHue = workspaceSidebarProjectHue(projectId: "project-alpha")

        XCTAssertEqual(firstHue, secondHue)
        XCTAssertGreaterThanOrEqual(firstHue, 0)
        XCTAssertLessThan(firstHue, 1)
    }

    func testProjectColorHexNormalizes() {
        XCTAssertEqual(normalizedWorkspaceSidebarColorHex("#60a5fa"), "#60A5FA")
        XCTAssertEqual(normalizedWorkspaceSidebarColorHex("f87171"), "#F87171")
        XCTAssertNil(normalizedWorkspaceSidebarColorHex("#12345"))
        XCTAssertNil(normalizedWorkspaceSidebarColorHex("tomato"))
    }

    func testProjectColorUsesConfiguredHexWhenPresent() {
        XCTAssertNotNil(workspaceSidebarColor(hex: "#60A5FA"))
        XCTAssertNil(workspaceSidebarColor(hex: "not-a-color"))
    }

    func testProjectSwipeScrollDeltaUsesDragDirection() {
        XCTAssertEqual(
            workspaceSidebarProjectSwipeTranslationAfterScroll(currentTranslation: 0, scrollingDeltaX: 24),
            -24,
        )
        XCTAssertEqual(
            workspaceSidebarProjectSwipeTranslationAfterScroll(currentTranslation: -24, scrollingDeltaX: -10),
            -14,
        )
    }

    func testWorkspaceSidebarFocusedMonitorScopeOnlyMatchesFocusedMonitor() {
        XCTAssertTrue(
            workspaceSidebarWorkspaceMatchesScope(
                workspaceMonitorScopeId: "monitor:0.0,0.0",
                selectedScopeId: workspaceSidebarFocusedScopeId,
                focusedMonitorScopeId: "monitor:0.0,0.0",
            ),
        )
        XCTAssertFalse(
            workspaceSidebarWorkspaceMatchesScope(
                workspaceMonitorScopeId: "monitor:1440.0,0.0",
                selectedScopeId: workspaceSidebarFocusedScopeId,
                focusedMonitorScopeId: "monitor:0.0,0.0",
            ),
        )
    }

    func testWorkspaceSidebarDefaultScopeIsRawAllScopeBeforePanelResolution() {
        XCTAssertTrue(
            workspaceSidebarWorkspaceMatchesScope(
                workspaceMonitorScopeId: "monitor:1440.0,0.0",
                selectedScopeId: workspaceSidebarDefaultScopeId,
                focusedMonitorScopeId: "monitor:0.0,0.0",
            ),
        )
    }

    func testWorkspaceSidebarDefaultTabListScopeResolvesToPanelMonitor() {
        XCTAssertEqual(
            workspaceSidebarTabListScopeId(
                selectedScopeId: workspaceSidebarDefaultScopeId,
                targetMonitorScopeId: "monitor:1440.0,0.0"
            ),
            "monitor:1440.0,0.0"
        )
        XCTAssertEqual(
            workspaceSidebarTabListScopeId(
                selectedScopeId: "monitor:0.0,0.0",
                targetMonitorScopeId: "monitor:1440.0,0.0"
            ),
            "monitor:0.0,0.0"
        )
    }

    func testVisibleWorkspaceNamesDefaultScopeUsesPanelMonitor() {
        let mainScope = "monitor:0.0,0.0"
        let secondaryScope = "monitor:1440.0,0.0"
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

        XCTAssertEqual(
            visibleWorkspaceNamesForSidebar(
                workspaces: workspaces,
                selectedMonitorScopeId: workspaceSidebarDefaultScopeId,
                focusedMonitorScopeId: mainScope,
                targetMonitorScopeId: secondaryScope,
            ),
            ["secondary-tab"]
        )
    }

    func testWorkspaceSidebarExplicitMonitorScopeOnlyMatchesThatMonitor() {
        XCTAssertTrue(
            workspaceSidebarWorkspaceMatchesScope(
                workspaceMonitorScopeId: "monitor:1440.0,0.0",
                selectedScopeId: "monitor:1440.0,0.0",
                focusedMonitorScopeId: "monitor:0.0,0.0",
            ),
        )
        XCTAssertFalse(
            workspaceSidebarWorkspaceMatchesScope(
                workspaceMonitorScopeId: "monitor:0.0,0.0",
                selectedScopeId: "monitor:1440.0,0.0",
                focusedMonitorScopeId: "monitor:0.0,0.0",
            ),
        )
    }

    func testWorkspaceSidebarInUseOverlayOnlyAppliesToVisibleOtherMonitor() {
        let workspace = WorkspaceSidebarWorkspaceViewModel(
            name: "2",
            projectId: workspaceProjectDefaultId,
            displayName: "2",
            sidebarLabel: "2",
            isGeneratedName: false,
            monitorScopeId: "monitor:1440.0,0.0",
            monitorName: "Side Display",
            isFocused: false,
            isVisible: true,
            items: [],
        )
        XCTAssertTrue(
            workspaceSidebarWorkspaceIsInUseOnOtherDisplay(
                workspace,
                selectedScopeId: "monitor:0.0,0.0",
            ),
        )
        XCTAssertFalse(
            workspaceSidebarWorkspaceIsInUseOnOtherDisplay(
                workspace,
                selectedScopeId: "monitor:1440.0,0.0",
            ),
        )
    }

    func testWorkspaceSidebarHoverCueWidthStaysCollapsed() {
        XCTAssertEqual(
            workspaceSidebarHoverCueWidth(collapsedWidth: 28, expandedWidth: 160),
            CGFloat(28),
        )
    }

    func testWorkspaceSidebarHoverCueWidthDoesNotProtrudeTowardExpandedWidth() {
        XCTAssertEqual(
            workspaceSidebarHoverCueWidth(collapsedWidth: 28, expandedWidth: 34),
            CGFloat(28),
        )
    }

    func testWorkspaceSidebarStatusBottomPaddingMatchesLeadingEdgePadding() {
        XCTAssertEqual(
            workspaceSidebarStatusBottomPadding(isCompact: true),
            workspaceSidebarOuterLeadingPadding(isCompact: true),
        )
        XCTAssertEqual(
            workspaceSidebarStatusBottomPadding(isCompact: false),
            workspaceSidebarOuterLeadingPadding(isCompact: false),
        )
    }

    func testWorkspaceSidebarHoverExpansionRequiresAtLeastThreeQuarterDepth() {
        XCTAssertFalse(
            isWorkspaceSidebarHoverDeepEnoughToExpand(
                mouseX: 8,
                sidebarMinX: 0,
                collapsedWidth: 28,
            ),
        )
        XCTAssertTrue(
            isWorkspaceSidebarHoverDeepEnoughToExpand(
                mouseX: 7,
                sidebarMinX: 0,
                collapsedWidth: 28,
            ),
        )
        XCTAssertTrue(
            isWorkspaceSidebarHoverDeepEnoughToExpand(
                mouseX: 14,
                sidebarMinX: 8,
                collapsedWidth: 28,
            ),
        )
    }

    func testMouseWindowDragInProgressRequiresMoveSessionWindowAndPressedButton() {
        XCTAssertTrue(isMouseWindowDragInProgress(kind: .move, draggedWindowId: 7, isLeftMouseButtonDown: true))
        XCTAssertFalse(isMouseWindowDragInProgress(kind: .none, draggedWindowId: 7, isLeftMouseButtonDown: true))
        XCTAssertFalse(isMouseWindowDragInProgress(kind: .move, draggedWindowId: nil, isLeftMouseButtonDown: true))
        XCTAssertFalse(isMouseWindowDragInProgress(kind: .move, draggedWindowId: 7, isLeftMouseButtonDown: false))
    }

    func testWorkspaceSidebarExpansionDelayOnlyAppliesToPassiveCollapsedHover() {
        XCTAssertTrue(
            shouldDelayWorkspaceSidebarExpansion(
                isExpanded: false,
                isExpansionLocked: false,
                isMouseWindowDragInProgress: false,
            ),
        )
        XCTAssertFalse(
            shouldDelayWorkspaceSidebarExpansion(
                isExpanded: true,
                isExpansionLocked: false,
                isMouseWindowDragInProgress: false,
            ),
        )
        XCTAssertFalse(
            shouldDelayWorkspaceSidebarExpansion(
                isExpanded: false,
                isExpansionLocked: true,
                isMouseWindowDragInProgress: false,
            ),
        )
        XCTAssertFalse(
            shouldDelayWorkspaceSidebarExpansion(
                isExpanded: false,
                isExpansionLocked: false,
                isMouseWindowDragInProgress: true,
            ),
        )
    }

    func testWorkspaceSidebarHoverExpansionIsSuppressedForSidebarOriginatedDrags() {
        XCTAssertTrue(
            shouldSuppressWorkspaceSidebarHoverExpansionForDrag(
                isSidebarItemDragActive: true,
                isSidebarOriginatedDrag: false,
            ),
        )
        XCTAssertTrue(
            shouldSuppressWorkspaceSidebarHoverExpansionForDrag(
                isSidebarItemDragActive: false,
                isSidebarOriginatedDrag: true,
            ),
        )
        XCTAssertFalse(
            shouldSuppressWorkspaceSidebarHoverExpansionForDrag(
                isSidebarItemDragActive: false,
                isSidebarOriginatedDrag: false,
            ),
        )
    }

    @MainActor
    func testChromeIsNotSuppressedForWinMuxFullscreen() {
        setUpWorkspacesForTests()
        let window = TestWindow.new(id: 7010, parent: focus.workspace.rootTilingContainer)
        window.isFullscreen = true

        XCTAssertFalse(shouldSuppressChromeForFullscreenContent(on: mainMonitor))
        XCTAssertFalse(shouldSuppressWorkspaceSidebarForFullscreenContent())
    }

    @MainActor
    func testChromeIsSuppressedForNativeFullscreen() {
        setUpWorkspacesForTests()
        shouldSuppressChromeForNativeFullscreenContent = true
        defer { shouldSuppressChromeForNativeFullscreenContent = false }

        XCTAssertTrue(shouldSuppressChromeForFullscreenContent(on: mainMonitor))
        XCTAssertTrue(shouldSuppressWorkspaceSidebarForFullscreenContent())
    }

    func testWorkspaceHoverExitDoesNotClearNewerHoveredWorkspace() {
        XCTAssertEqual(
            nextWorkspaceSidebarHoveredWorkspaceName(
                currentHoveredWorkspaceName: "b",
                workspaceName: "a",
                isHovering: false,
            ),
            "b",
        )
    }

    func testWorkspaceHoverExitClearsMatchingHoveredWorkspace() {
        XCTAssertNil(
            nextWorkspaceSidebarHoveredWorkspaceName(
                currentHoveredWorkspaceName: "a",
                workspaceName: "a",
                isHovering: false,
            ),
        )
    }

    func testWindowHoverExitDoesNotClearNewerHoveredWindow() {
        XCTAssertEqual(
            nextWorkspaceSidebarHoveredWindowId(
                currentHoveredWindowId: 2,
                windowId: 1,
                isHovering: false,
            ),
            2,
        )
    }

    func testWindowHoverExitClearsMatchingHoveredWindow() {
        XCTAssertNil(
            nextWorkspaceSidebarHoveredWindowId(
                currentHoveredWindowId: 1,
                windowId: 1,
                isHovering: false,
            ),
        )
    }

}
