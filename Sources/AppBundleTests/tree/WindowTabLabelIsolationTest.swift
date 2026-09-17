@testable import AppBundle
import XCTest

@MainActor
final class WindowTabLabelIsolationTest: XCTestCase {
    func testSameAppAndTitleHaveIndependentNamesThroughRestoreAndReset() async throws {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let first = TestWindow.new(id: 701, parent: workspace.rootTilingContainer)
        let second = TestWindow.new(id: 702, parent: workspace.rootTilingContainer)
        first.windowTitle = "ChatGPT"
        second.windowTitle = "ChatGPT"

        try await renameWindowTab(windowId: first.windowId, displayName: "Research")
        let untouched = await tabDisplayTitle(for: second)
        XCTAssertEqual(untouched, "ChatGPT")
        try await renameWindowTab(windowId: second.windowId, displayName: "Writing")
        resetWindowTabLabelsForTests()
        // Persistence must be per-window even when the native title changes.
        first.windowTitle = "New conversation"
        resetCachedWindowTitles()
        let restoredFirst = await tabDisplayTitle(for: first)
        let restoredSecond = await tabDisplayTitle(for: second)
        XCTAssertEqual(restoredFirst, "Research")
        XCTAssertEqual(restoredSecond, "Writing")

        try await resetWindowTabLabel(windowId: first.windowId)
        let resetFirst = await tabDisplayTitle(for: first)
        let preservedSecond = await tabDisplayTitle(for: second)
        XCTAssertEqual(resetFirst, "New conversation")
        XCTAssertEqual(preservedSecond, "Writing")
    }

    func testLegacySharedAliasIsIgnoredWhenTitleIsAmbiguous() async throws {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let first = TestWindow.new(id: 703, parent: workspace.rootTilingContainer)
        let second = TestWindow.new(id: 704, parent: workspace.rootTilingContainer)
        first.windowTitle = "ChatGPT"
        second.windowTitle = "ChatGPT"
        config.windowTabs.tabLabels[windowTabLabelKey(app: first.app, rawTitle: "ChatGPT")] = "Old shared name"
        let firstTitle = await tabDisplayTitle(for: first)
        let secondTitle = await tabDisplayTitle(for: second)
        XCTAssertEqual(firstTitle, "ChatGPT")
        XCTAssertEqual(secondTitle, "ChatGPT")
    }

    func testUniqueLegacyAliasRemainsReadableAndCanBeReset() async throws {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let window = TestWindow.new(id: 705, parent: workspace.rootTilingContainer)
        window.windowTitle = "Unique conversation"
        config.windowTabs.tabLabels[windowTabLabelKey(app: window.app, rawTitle: "Unique conversation")] = "Old name"
        let legacyTitle = await tabDisplayTitle(for: window)
        XCTAssertEqual(legacyTitle, "Old name")
        try await resetWindowTabLabel(windowId: window.windowId)
        let resetTitle = await tabDisplayTitle(for: window)
        XCTAssertEqual(resetTitle, "Unique conversation")
    }
}
