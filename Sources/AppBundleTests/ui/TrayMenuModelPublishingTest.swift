import Combine
@testable import AppBundle
import XCTest

final class TrayMenuModelPublishingTest: XCTestCase {
    func testSetIfChangedPublishesOnlyNewValues() {
        let model = TrayMenuModel()
        var publishedValues: [String] = []
        let subscription = model.$trayText.dropFirst().sink { publishedValues.append($0) }
        defer { subscription.cancel() }

        XCTAssertFalse(model.setIfChanged(\.trayText, to: ""))
        XCTAssertTrue(model.setIfChanged(\.trayText, to: "A"))
        XCTAssertFalse(model.setIfChanged(\.trayText, to: "A"))

        XCTAssertEqual(publishedValues, ["A"])
    }

    @MainActor
    func testExpandSidebarSkipsAlreadyAppliedState() {
        setUpWorkspacesForTests()
        let panel = WorkspaceSidebarPanel.shared
        panel.viewModel.isWorkspaceSidebarExpanded = true
        panel.viewModel.workspaceSidebarVisibleWidth = 320
        var expansionNotifications = 0
        var publishedExpansionStates: [Bool] = []
        let notificationSubscription = NotificationCenter.default.publisher(
            for: workspaceSidebarWillExpandNotification,
            object: panel
        ).sink { _ in expansionNotifications += 1 }
        let modelSubscription = panel.viewModel.$isWorkspaceSidebarExpanded
            .dropFirst()
            .sink { publishedExpansionStates.append($0) }
        defer {
            notificationSubscription.cancel()
            modelSubscription.cancel()
            panel.viewModel.isWorkspaceSidebarExpanded = false
            panel.viewModel.workspaceSidebarVisibleWidth = 0
        }

        panel.expandSidebar(to: 320)

        XCTAssertEqual(expansionNotifications, 0)
        XCTAssertEqual(publishedExpansionStates, [])
    }

    @MainActor
    func testSidebarModelSyncSkipsDuplicatesAndPreservesLocalState() {
        setUpWorkspacesForTests()
        let panel = WorkspaceSidebarPanel.shared
        panel.viewModel.workspaceSidebarVisibleWidth = 321
        panel.viewModel.isWorkspaceSidebarExpanded = true
        panel.viewModel.isWorkspaceSidebarPinnedExpanded = true
        TrayMenuModel.shared.workspaceSidebarTopPadding = 12
        panel.syncModelFromShared()

        var panelChangeCount = 0
        let subscription = panel.viewModel.objectWillChange.sink { panelChangeCount += 1 }
        defer {
            subscription.cancel()
            panel.viewModel.workspaceSidebarVisibleWidth = 0
            panel.viewModel.isWorkspaceSidebarExpanded = false
            panel.viewModel.isWorkspaceSidebarPinnedExpanded = false
        }

        panel.syncModelFromShared()
        XCTAssertEqual(panelChangeCount, 0)

        TrayMenuModel.shared.trayText = "not-used-by-sidebar"
        panel.syncModelFromShared()
        XCTAssertEqual(panelChangeCount, 0)

        TrayMenuModel.shared.workspaceSidebarTopPadding = 13
        panel.syncModelFromShared()
        XCTAssertEqual(panelChangeCount, 1)
        XCTAssertEqual(panel.viewModel.workspaceSidebarTopPadding, 13)
        XCTAssertEqual(panel.viewModel.workspaceSidebarVisibleWidth, 321)
        XCTAssertTrue(panel.viewModel.isWorkspaceSidebarExpanded)
        XCTAssertTrue(panel.viewModel.isWorkspaceSidebarPinnedExpanded)
    }
}
