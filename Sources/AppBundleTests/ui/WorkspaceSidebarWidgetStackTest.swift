@testable import AppBundle
import Foundation
import XCTest

final class WorkspaceSidebarWidgetStackTest: XCTestCase {
    func testTaskListWidgetsAreAlwaysHidden() {
        let tasks = widget(id: "tasks", type: .builtInTasks)
        let todoList = widget(id: "todo-list", type: .builtInTodoList)

        XCTAssertFalse(workspaceSidebarWidgetIsVisible(tasks, showsNotePad: false, isCompact: false))
        XCTAssertFalse(workspaceSidebarWidgetIsVisible(tasks, showsNotePad: false, isCompact: true))
        XCTAssertFalse(workspaceSidebarWidgetIsVisible(todoList, showsNotePad: false, isCompact: false))
        XCTAssertFalse(workspaceSidebarHasVisibleWidgets([tasks, todoList], showsNotePad: false, isCompact: false))
        XCTAssertFalse(workspaceSidebarHasVisibleWidgets([tasks], showsNotePad: false, isCompact: true))
    }

    func testPeriodicallyFocusIsExpandedOnly() {
        let periodicallyFocus = widget(id: "toggl-weekly-focus", type: .builtInTogglWeeklyFocus)

        XCTAssertTrue(workspaceSidebarWidgetIsVisible(periodicallyFocus, showsNotePad: false, isCompact: false))
        XCTAssertFalse(workspaceSidebarWidgetIsVisible(periodicallyFocus, showsNotePad: false, isCompact: true))
    }

    func testRotationGroupsKeepFirstPositionAndCollectEnabledMembers() {
        let widgets = [
            widget(id: "time-date", type: .builtInTimeDate),
            widget(id: "toggl-weekly-focus", type: .builtInTogglWeeklyFocus, rotationGroup: "focus", rotationIntervalSeconds: 300),
            widget(id: "spending", type: .builtInSpendingCategories, rotationGroup: "focus"),
            widget(id: "custom", type: .plugin, bundle: "CustomWidget.bundle", rotationGroup: "reports", rotationIntervalSeconds: 120),
            widget(id: "schedule-heatmap", type: .builtInScheduleHeatmap, rotationGroup: "reports"),
        ]

        let items = WorkspaceSidebarWidgetStackItem.items(for: widgets)

        assertEquals(items.map(\.id), ["time-date", "rotation-focus", "rotation-reports"])
        guard case .rotationGroup(let focusId, let focusWidgets, let focusIntervalSeconds) = items[1] else {
            return XCTFail("Expected focus rotation group")
        }
        assertEquals(focusId, "focus")
        assertEquals(focusWidgets.map(\.id), ["toggl-weekly-focus", "spending"])
        assertEquals(focusIntervalSeconds, 300)

        guard case .rotationGroup(let reportsId, let reportsWidgets, let reportsIntervalSeconds) = items[2] else {
            return XCTFail("Expected reports rotation group")
        }
        assertEquals(reportsId, "reports")
        assertEquals(reportsWidgets.map(\.id), ["custom", "schedule-heatmap"])
        assertEquals(reportsIntervalSeconds, 120)
    }

    func testSingleWidgetRotationGroupRendersAsPlainWidget() {
        let widgets = [
            widget(id: "time-date", type: .builtInTimeDate),
            widget(id: "toggl-weekly-focus", type: .builtInTogglWeeklyFocus, rotationGroup: "focus", rotationIntervalSeconds: 300),
        ]

        let items = WorkspaceSidebarWidgetStackItem.items(for: widgets)

        assertEquals(items, [
            .widget(widgets[0]),
            .widget(widgets[1]),
        ])
    }

    func testRotationGroupUsesDefaultIntervalAndReferenceDateSlots() {
        let widgets = [
            widget(id: "toggl-weekly-focus", type: .builtInTogglWeeklyFocus, rotationGroup: "focus"),
            widget(id: "schedule-heatmap", type: .builtInScheduleHeatmap, rotationGroup: "focus"),
        ]

        let items = WorkspaceSidebarWidgetStackItem.items(for: widgets)

        guard case .rotationGroup(_, let groupWidgets, let intervalSeconds) = items.first else {
            return XCTFail("Expected rotation group")
        }
        assertEquals(intervalSeconds, defaultWorkspaceSidebarWidgetRotationIntervalSeconds)
        assertEquals(
            WorkspaceSidebarWidgetStackItem.activeWidget(
                in: groupWidgets,
                intervalSeconds: intervalSeconds,
                at: Date(timeIntervalSinceReferenceDate: 299),
            )?.id,
            "toggl-weekly-focus",
        )
        assertEquals(
            WorkspaceSidebarWidgetStackItem.activeWidget(
                in: groupWidgets,
                intervalSeconds: intervalSeconds,
                at: Date(timeIntervalSinceReferenceDate: 300),
            )?.id,
            "schedule-heatmap",
        )
        assertEquals(
            WorkspaceSidebarWidgetStackItem.activeWidget(
                in: groupWidgets,
                intervalSeconds: intervalSeconds,
                at: Date(timeIntervalSinceReferenceDate: 600),
            )?.id,
            "toggl-weekly-focus",
        )
    }

    private func widget(
        id: String,
        type: WorkspaceSidebarWidgetType,
        enabled: Bool = true,
        bundle: String? = nil,
        rotationGroup: String? = nil,
        rotationIntervalSeconds: Int? = nil,
    ) -> WorkspaceSidebarWidgetConfig {
        WorkspaceSidebarWidgetConfig(
            id: id,
            type: type,
            enabled: enabled,
            bundle: bundle,
            rotationGroup: rotationGroup,
            rotationIntervalSeconds: rotationIntervalSeconds,
        )
    }
}
