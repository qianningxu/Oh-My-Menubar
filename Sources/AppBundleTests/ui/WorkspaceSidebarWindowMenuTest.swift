@testable import AppBundle
import XCTest

final class WorkspaceSidebarWindowMenuTest: XCTestCase {
    func testMarksFloatingWindowRows() {
        let item = WorkspaceSidebarWindowMenuItem(
            windowId: 10,
            title: "NetEase Music",
            tabName: nil,
            isFloating: true,
            isFocused: false
        )

        XCTAssertEqual(item.menuTitle, "NetEase Music — Floating")
    }

    func testBuildsMenuRowsOnlyForTheSelectedWorkspace() {
        let first = makeWorkspace(name: "1", displayName: "ChatGPT", windowId: 11, appName: "ChatGPT")
        let second = makeWorkspace(name: "2", displayName: "Browser", windowId: 12, appName: "Safari")

        let firstItems = workspaceSidebarTiledWindowMenuItems(workspaces: [first])
        let secondItems = workspaceSidebarTiledWindowMenuItems(workspaces: [second])

        XCTAssertEqual(firstItems.map(\.menuTitle), ["ChatGPT — ChatGPT"])
        XCTAssertEqual(firstItems.map(\.windowId), [11])
        XCTAssertEqual(secondItems.map(\.menuTitle), ["Safari — Browser"])
        XCTAssertEqual(secondItems.map(\.windowId), [12])
    }

    private func makeWorkspace(
        name: String,
        displayName: String,
        windowId: UInt32,
        appName: String
    ) -> WorkspaceSidebarWorkspaceViewModel {
        WorkspaceSidebarWorkspaceViewModel(
            name: name,
            projectId: workspaceProjectDefaultId,
            displayName: displayName,
            sidebarLabel: "",
            isGeneratedName: false,
            monitorScopeId: "main",
            monitorName: nil,
            isFocused: false,
            isVisible: true,
            items: [WorkspaceSidebarItemViewModel(kind: .window(WorkspaceSidebarWindowViewModel(
                windowId: windowId,
                workspaceName: name,
                appName: appName,
                appBundleId: nil,
                appBundlePath: nil,
                title: nil,
                isFocused: false
            )))]
        )
    }
}
