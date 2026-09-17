@testable import AppBundle
import Common
import XCTest

final class WorkspaceSidebarSessionTest: XCTestCase {
    func testProjectDeletionOnlyReconcilesWhenClosingNativeWindows() {
        XCTAssertEqual(
            workspaceSidebarProjectDeletionPostRefreshPolicy(for: .closeWindows),
            .reconcileNativeWindowInventory
        )
        XCTAssertEqual(
            workspaceSidebarProjectDeletionPostRefreshPolicy(for: .moveWindowsToFallback),
            .none
        )
    }

    @MainActor
    func testInMemorySidebarSessionSkipsTrailingFullRefresh() async {
        setUpWorkspacesForTests()
        var scheduledEvents: [String] = []
        setScheduledRefreshOverrideForTests { event, _ in
            scheduledEvents.append(event.description)
        }
        defer { setScheduledRefreshOverrideForTests(nil) }

        let session = runWorkspaceSidebarSession {}
        await session?.value

        XCTAssertEqual(scheduledEvents, [])
    }

    @MainActor
    func testNativeInventoryMutationSchedulesTrailingFullRefresh() async throws {
        setUpWorkspacesForTests()
        var scheduledEvents: [String] = []
        setScheduledRefreshOverrideForTests { event, _ in
            scheduledEvents.append(event.description)
        }
        defer { setScheduledRefreshOverrideForTests(nil) }

        let session = runWorkspaceSidebarSession(postRefresh: .reconcileNativeWindowInventory) {}
        await session?.value
        try await waitForScheduledRefreshForTests()

        XCTAssertEqual(scheduledEvents, [RefreshSessionEvent.menuBarButton.description])
    }

    @MainActor
    func testNativeInventoryMutationStillSchedulesRefreshWhenBodyThrows() async throws {
        setUpWorkspacesForTests()
        var scheduledEvents: [String] = []
        setScheduledRefreshOverrideForTests { event, _ in
            scheduledEvents.append(event.description)
        }
        defer { setScheduledRefreshOverrideForTests(nil) }

        let session = runWorkspaceSidebarSession(postRefresh: .reconcileNativeWindowInventory) {
            throw WorkspaceSidebarSessionTestError.expected
        }
        await session?.value
        try await waitForScheduledRefreshForTests()

        XCTAssertEqual(scheduledEvents, [RefreshSessionEvent.menuBarButton.description])
    }
}

private enum WorkspaceSidebarSessionTestError: Error {
    case expected
}
