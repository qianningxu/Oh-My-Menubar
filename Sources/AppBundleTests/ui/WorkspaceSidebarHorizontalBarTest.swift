import AppKit
@testable import AppBundle
import XCTest

final class WorkspaceSidebarHorizontalBarTest: XCTestCase {
    func testProjectMenuAnchorSitsAboveBottomBar() {
        let control = NSRect(x: 240, y: 8, width: 48, height: 48)
        let anchor = workspaceSidebarProjectMenuAnchorFrame(for: control)

        XCTAssertEqual(anchor.minX, control.minX)
        XCTAssertEqual(anchor.minY, control.maxY + WinMuxSpacing.comfortable)
        XCTAssertEqual(anchor.size, CGSize(width: 1, height: 1))
    }

    func testNotchedDisplayPlacesWorkspaceBarBesideNotch() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1728, height: 1117)
        let leftSafeArea = NSRect(x: 0, y: 1085, width: 771, height: 32)
        let rightSafeArea = NSRect(x: 957, y: 1085, width: 771, height: 32)

        let left = workspaceSidebarTopBarRegionFrame(
            screenFrame: screenFrame,
            auxiliaryTopLeftArea: leftSafeArea,
            barHeight: 32,
        )
        let right = menuBarStatusWidgetRegionFrame(
            screenFrame: screenFrame,
            auxiliaryTopRightArea: rightSafeArea,
            barHeight: 32,
        )
        let panel = workspaceSidebarFloatingProjectBarPanelFrame(
            screenFrame: screenFrame,
            visibleFrame: NSRect(x: 0, y: 0, width: 1728, height: 1085),
            barSize: CGSize(width: 420, height: 32),
            notchLeadingEdge: leftSafeArea.maxX
        )

        XCTAssertEqual(left, NSRect(x: 0, y: 1041, width: 1728, height: 44))
        XCTAssertEqual(right, NSRect(x: 0, y: 1085, width: 1728, height: 32))
        XCTAssertEqual(panel.width, 420)
        XCTAssertEqual(panel.maxX, leftSafeArea.maxX - WinMuxSpacing.compact)
        XCTAssertEqual(panel.minY, 1085)
    }

    func testNonNotchedDisplayUsesTwoFullWidthRows() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)

        let left = workspaceSidebarTopBarRegionFrame(
            screenFrame: screenFrame,
            auxiliaryTopLeftArea: nil,
            barHeight: 32,
        )
        let right = menuBarStatusWidgetRegionFrame(
            screenFrame: screenFrame,
            auxiliaryTopRightArea: nil,
            barHeight: 32,
        )

        XCTAssertEqual(left.minX, screenFrame.minX)
        XCTAssertEqual(right.maxX, screenFrame.maxX)
        XCTAssertEqual(left.maxX, right.maxX)
        XCTAssertEqual(left.maxY, right.minY)
        XCTAssertGreaterThan(left.width, 0)
        XCTAssertGreaterThan(right.width, 0)
    }

    func testSecondaryDisplayKeepsNegativeScreenOrigin() {
        let screenFrame = NSRect(x: -1440, y: 120, width: 1440, height: 900)

        let panel = workspaceSidebarFloatingProjectBarPanelFrame(
            screenFrame: screenFrame,
            visibleFrame: NSRect(x: -1432, y: 145, width: 1432, height: 851),
            barSize: CGSize(width: 420, height: 32)
        )

        XCTAssertEqual(panel.midX, screenFrame.midX)
        XCTAssertEqual(panel.minY, 992)
        XCTAssertEqual(panel.width, 420)
    }

    func testFloatingWorkspaceBarIsCenteredInMenuStripWithoutNotch() {
        let frame = workspaceSidebarFloatingProjectBarPanelFrame(
            screenFrame: NSRect(x: -1440, y: 120, width: 1440, height: 900),
            visibleFrame: NSRect(x: -1440, y: 120, width: 1440, height: 870),
            barSize: CGSize(width: 420, height: 32)
        )

        XCTAssertEqual(frame.width, 420)
        XCTAssertEqual(frame.height, 32)
        XCTAssertEqual(frame.midX, -720)
        XCTAssertEqual(frame.minY, 989)
    }

    func testFloatingProjectBarShadowOutsetPreservesVisibleBarPosition() {
        let outset = WinMuxBarStyle.workspaceBarShadowOutset
        let frame = workspaceSidebarFloatingProjectBarPanelFrame(
            screenFrame: NSRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: NSRect(x: 0, y: 40, width: 1440, height: 836),
            barSize: CGSize(width: 420 + outset * 2, height: 48 + outset * 2),
            contentOutset: outset
        )
        let visualFrame = workspaceSidebarFloatingProjectBarVisualFrame(
            panelFrame: frame,
            contentOutset: outset
        )

        XCTAssertEqual(visualFrame.size, CGSize(width: 420, height: 48))
        XCTAssertEqual(visualFrame.minY, 864)
        XCTAssertEqual(visualFrame.midX, 720)
    }

    func testWorkspaceBarNeverReservesTiledWindowSpace() {
        XCTAssertEqual(
            workspaceSidebarProjectBarVisibleReservation(autoHideEnabled: false),
            0
        )
        XCTAssertEqual(workspaceSidebarProjectBarVisibleReservation(autoHideEnabled: true), 0)
    }

    func testAutoHideTopEdgeRevealAndKeepVisibleRegions() {
        let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let bar = NSRect(x: 300, y: 768, width: 400, height: 32)

        XCTAssertTrue(workspaceSidebarAutoHideShouldShow(
            isCurrentlyVisible: false,
            pointer: CGPoint(x: 50, y: 799),
            screenFrame: screen,
            barFrame: bar,
            isInteractionLocked: false
        ))
        XCTAssertTrue(workspaceSidebarAutoHideShouldShow(
            isCurrentlyVisible: true,
            pointer: CGPoint(x: 500, y: 780),
            screenFrame: screen,
            barFrame: bar,
            isInteractionLocked: false
        ))
        XCTAssertFalse(workspaceSidebarAutoHideShouldShow(
            isCurrentlyVisible: true,
            pointer: CGPoint(x: 500, y: 700),
            screenFrame: screen,
            barFrame: bar,
            isInteractionLocked: false
        ))
        XCTAssertTrue(workspaceSidebarAutoHideShouldShow(
            isCurrentlyVisible: true,
            pointer: CGPoint(x: 500, y: 700),
            screenFrame: screen,
            barFrame: bar,
            isInteractionLocked: true
        ))
    }

    func testHorizontalReorderUsesTabMidpointsAndKeepsFolderDestination() {
        let folder = WorkspaceFolderId("folder-a")
        let frames = [
            WorkspaceSidebarHorizontalTabFrame(
                workspaceName: "first",
                folderId: folder,
                frame: CGRect(x: 0, y: 0, width: 100, height: 32),
            ),
            WorkspaceSidebarHorizontalTabFrame(
                workspaceName: "second",
                folderId: WorkspaceFolderId("folder-b"),
                frame: CGRect(x: 108, y: 0, width: 100, height: 32),
            ),
            WorkspaceSidebarHorizontalTabFrame(
                workspaceName: "third",
                folderId: WorkspaceFolderId("folder-c"),
                frame: CGRect(x: 216, y: 0, width: 100, height: 32),
            ),
        ]

        let before = workspaceSidebarHorizontalReorderTarget(
            sourceWorkspaceName: "first",
            pointer: CGPoint(x: 120, y: 16),
            frames: frames,
        )
        let after = workspaceSidebarHorizontalReorderTarget(
            sourceWorkspaceName: "first",
            pointer: CGPoint(x: 180, y: 16),
            frames: frames,
        )

        XCTAssertEqual(before, WorkspaceSidebarHorizontalReorderTarget(
            workspaceName: "second",
            folderId: WorkspaceFolderId("folder-b"),
            placement: .before("second"),
        ))
        XCTAssertEqual(after, WorkspaceSidebarHorizontalReorderTarget(
            workspaceName: "second",
            folderId: WorkspaceFolderId("folder-b"),
            placement: .after("second"),
        ))
    }

    func testHorizontalProjectionShowsOnlyActiveProjectAsOneTabPerWorkspace() {
        let activeProject = workspaceProjectDefaultId
        let otherProject = WorkspaceProjectId("other")
        let childWindow = WorkspaceSidebarWindowViewModel(
            windowId: 101,
            workspaceName: "composed",
            appName: "Safari",
            appBundleId: "com.apple.Safari",
            appBundlePath: "/Applications/Safari.app",
            title: "Docs",
            isFocused: false,
        )
        let childGroup = WorkspaceSidebarTabGroupViewModel(
            representativeWindowId: 101,
            workspaceName: "composed",
            title: "Docs",
            windowCount: 2,
            isFocused: false,
            tabs: [childWindow],
        )
        let workspaces = [
            makeWorkspace(name: "other-project", projectId: otherProject),
            makeWorkspace(name: "first", projectId: activeProject),
            WorkspaceSidebarWorkspaceViewModel(
                name: "composed",
                projectId: activeProject,
                displayName: "Composed",
                sidebarLabel: "Composed",
                isGeneratedName: false,
                tabSummary: WorkspaceSidebarTabSummaryViewModel(
                    title: "Docs & Notes",
                    subtitle: nil,
                    appBundleId: "com.apple.Safari",
                    appBundlePath: "/Applications/Safari.app",
                    windowCount: 2,
                    isEmpty: false,
                ),
                monitorScopeId: workspaceSidebarDefaultScopeId,
                monitorName: nil,
                isFocused: false,
                isVisible: true,
                items: [
                    WorkspaceSidebarItemViewModel(kind: .window(childWindow)),
                    WorkspaceSidebarItemViewModel(kind: .tabGroup(childGroup)),
                ],
            ),
        ]
        let snapshot = WorkspaceSidebarSnapshot(
            workspaces: workspaces,
            projects: [
                WorkspaceSidebarProjectViewModel(id: activeProject, displayName: "Main", colorHex: nil),
                WorkspaceSidebarProjectViewModel(id: otherProject, displayName: "Other", colorHex: nil),
            ],
            folders: [
                WorkspaceSidebarFolderViewModel(
                    id: WorkspaceFolderId("folder-hidden"),
                    projectId: activeProject,
                    displayName: "Hidden Folder",
                    colorHex: nil,
                    isUnfolded: true,
                ),
            ],
            activeProjectId: activeProject,
            monitorScopes: [],
            selectedMonitorScopeId: workspaceSidebarDefaultScopeId,
            targetMonitorScopeId: workspaceSidebarDefaultScopeId,
            focusedMonitorScopeId: workspaceSidebarDefaultScopeId,
            visibleWidth: 240,
            isPinnedExpanded: true,
            hoveredWorkspaceName: nil,
            dropPreview: nil,
            configuration: WorkspaceSidebarConfiguration(
                collapsedWidth: 44,
                expandedWidth: 240,
                topPadding: 8,
                showMonitorSelector: true,
                showsDate: true,
                showsStatusPills: true,
                widgets: [WorkspaceSidebarWidgetConfig(id: "ignored-widget")],
            ),
        )

        let visible = workspaceSidebarHorizontalVisibleWorkspaces(in: snapshot)

        XCTAssertEqual(visible.map(\.name), ["first", "composed"])
        XCTAssertEqual(visible.filter { $0.name == "composed" }.count, 1)
        XCTAssertEqual(visible.first(where: { $0.name == "composed" })?.items.count, 2)
        XCTAssertFalse(visible.map(\.name).contains("other-project"))
    }

    func testPopupHeightIsPositiveAndFiveMinuteRotationRemainsConfigured() {
        XCTAssertGreaterThan(
            workspaceSidebarHorizontalProjectPopupHeight(projectCount: 3),
            workspaceSidebarProjectPopupRowHeight,
        )
        XCTAssertEqual(menuBarProjectProgressRefreshInterval, 5 * 60)
    }

    func testTopBarProjectDestinationsExcludeCurrentProject() {
        let current = WorkspaceSidebarProjectViewModel(
            id: "current",
            displayName: "Current",
            colorHex: nil,
        )
        let destination = WorkspaceSidebarProjectViewModel(
            id: "destination",
            displayName: "Destination",
            colorHex: nil,
        )

        XCTAssertEqual(
            workspaceSidebarProjectDestinations(
                projects: [current, destination],
                currentProjectId: current.id,
            ).map(\.id),
            [destination.id],
        )
    }

    private func makeWorkspace(
        name: String,
        projectId: WorkspaceProjectId,
    ) -> WorkspaceSidebarWorkspaceViewModel {
        WorkspaceSidebarWorkspaceViewModel(
            name: name,
            projectId: projectId,
            displayName: name.capitalized,
            sidebarLabel: name,
            isGeneratedName: false,
            monitorScopeId: workspaceSidebarDefaultScopeId,
            monitorName: nil,
            isFocused: false,
            isVisible: true,
            items: [],
        )
    }
}
