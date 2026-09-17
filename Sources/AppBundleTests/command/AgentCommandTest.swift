@testable import AppBundle
import Foundation
import XCTest

@MainActor
final class AgentCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParse() {
        XCTAssertTrue(parseCommand("agent query").cmdOrNil is AgentCommand)
        XCTAssertTrue(parseCommand("agent query --path /tmp/winmux-agent.json").cmdOrNil is AgentCommand)
        XCTAssertEqual(parseCommand("agent apply").errorOrNil, "--path is mandatory for 'check' and 'apply'")
        XCTAssertEqual(parseCommand("agent skill --path /tmp/winmux-agent.json").errorOrNil, "--path is incompatible with 'skill'")
    }

    func testSkill() async throws {
        let result = try await parseCommand("agent skill").cmdOrDie.run(.defaultEnv, .emptyStdin)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.joined(separator: "\n").contains("name: winmux-agent"))
        XCTAssertTrue(result.stdout.joined(separator: "\n").contains("setWinMuxFullscreen"))
        XCTAssertTrue(result.stdout.joined(separator: "\n").contains("\"swapPanes\""))
        XCTAssertTrue(result.stdout.joined(separator: "\n").contains("All `edit.operations` commands"))
        XCTAssertTrue(result.stdout.joined(separator: "\n").contains("createTabGroup`, `addWindowToTabGroup`, `setActiveTab`"))
        XCTAssertTrue(result.stdout.joined(separator: "\n").contains("setPaneSize"))
        XCTAssertTrue(result.stdout.joined(separator: "\n").contains("setTabLayout"))
        XCTAssertTrue(result.stdout.joined(separator: "\n").contains("focusTab"))
        XCTAssertTrue(result.stdout.joined(separator: "\n").contains("moveWindowToTab"))
        XCTAssertTrue(result.stdout.joined(separator: "\n").contains("edit.layout.tabs"))
        XCTAssertTrue(result.stdout.joined(separator: "\n").contains("Full layout mode"))
        XCTAssertTrue(result.stdout.joined(separator: "\n").contains("Use `0.8` for 80%"))
        XCTAssertTrue(result.stdout.joined(separator: "\n").contains("\"axis\": \"vertical\""))
        XCTAssertTrue(result.stdout.joined(separator: "\n").contains("replace the entire `edit.operations` array"))
        XCTAssertTrue(result.stdout.joined(separator: "\n").contains("Do not create old top folders or sidebar folders"))
    }

    func testAgentAcceptsTabNamedOperationAliases() async throws {
        let source = Workspace.get(byName: "a")
        let target = Workspace.get(byName: "b")
        target.seedMonitorIfNeeded(mainMonitor)
        let parked = Workspace.get(byName: "parked")
        parked.seedMonitorIfNeeded(mainMonitor)
        _ = TestWindow.new(id: 1, parent: source.rootTilingContainer)
        _ = TestWindow.new(id: 2, parent: source.rootTilingContainer)

        let path = try writeAgentJson("""
            {
              "schemaVersion": 1,
              "edit": {
                "operations": [
                  { "type": "moveWindowToTab", "windowId": 1, "tab": "b", "focus": true },
                  { "type": "focusTab", "tab": "b" },
                  { "type": "parkWindow", "pane": { "windowId": 2 }, "tab": "parked" }
                ]
              }
            }
            """)

        let result = try await parseCommand("agent apply --path \(path.path)").cmdOrDie.run(.defaultEnv, .emptyStdin)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(target.allLeafWindowsRecursive.map(\.windowId), [1])
        XCTAssertEqual(parked.allLeafWindowsRecursive.map(\.windowId), [2])
        XCTAssertTrue(focus.workspace === target)
    }

    func testQueryIncludesPanesAndTabGroups() async throws {
        let workspace = Workspace.get(byName: "a")
        let root = workspace.rootTilingContainer
        _ = TestWindow.new(id: 1, parent: root)
        let group = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        _ = TestWindow.new(id: 2, parent: group)
        _ = TestWindow.new(id: 3, parent: group)

        let result = try await parseCommand("agent query").cmdOrDie.run(.defaultEnv, .emptyStdin)

        XCTAssertEqual(result.exitCode, 0)
        let out = result.stdout.joined(separator: "\n")
        XCTAssertTrue(out.contains("\"tabGroupId\" : \"tabgroup-2\""))
        XCTAssertTrue(out.contains("\"paneId\" : \"pane-tabgroup-2\""))
        XCTAssertTrue(out.contains("\"size\" : 0.5"))
        XCTAssertTrue(out.contains("\"sizeAxis\" : \"horizontal\""))
        XCTAssertTrue(out.contains("\"operations\" : ["))
        XCTAssertTrue(out.contains("\"worldId\" : "))
    }

    func testQueryExposesTabAliasesBesideLegacyWorkspaceFields() async throws {
        let workspace = Workspace.get(byName: "10")
        workspace.markAsAutomaticallyNamed()
        let root = workspace.rootTilingContainer
        _ = TestWindow.new(id: 1, parent: root)
        _ = TestWindow.new(id: 2, parent: root)

        let result = try await parseCommand("agent query").cmdOrDie.run(.defaultEnv, .emptyStdin)

        XCTAssertEqual(result.exitCode, 0)
        let data = Data(result.stdout.joined(separator: "\n").utf8)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let inventory = try XCTUnwrap(object["inventory"] as? [String: Any])
        let tabs = try XCTUnwrap(inventory["tabs"] as? [[String: Any]])
        let workspaces = try XCTUnwrap(inventory["workspaces"] as? [[String: Any]])
        let expectedTabName = workspaceDisplayName(workspace.name)
        let tab = try XCTUnwrap(tabs.first { ($0["name"] as? String) == "10" })
        XCTAssertEqual(tab["tab"] as? String, expectedTabName)
        XCTAssertEqual(tab["displayName"] as? String, expectedTabName)
        XCTAssertEqual(tab["name"] as? String, "10")
        XCTAssertEqual(workspaces.count, tabs.count)

        let windows = try XCTUnwrap(inventory["windows"] as? [[String: Any]])
        let window = try XCTUnwrap(windows.first { ($0["windowId"] as? Int) == 1 })
        XCTAssertEqual(window["tab"] as? String, expectedTabName)
        XCTAssertEqual(window["workspace"] as? String, "10")

        let reasoning = try XCTUnwrap(object["reasoning"] as? [String: Any])
        let panes = try XCTUnwrap(reasoning["panes"] as? [[String: Any]])
        let pane = try XCTUnwrap(panes.first { ($0["paneId"] as? String) == "pane-1" })
        XCTAssertEqual(pane["tab"] as? String, expectedTabName)
        XCTAssertEqual(pane["workspace"] as? String, "10")
        let rawTrees = try XCTUnwrap(reasoning["rawTrees"] as? [[String: Any]])
        let rawTree = try XCTUnwrap(rawTrees.first { ($0["workspace"] as? String) == "10" })
        XCTAssertEqual(rawTree["tab"] as? String, expectedTabName)
    }

    func testCheckRejectsStaleWorldId() async throws {
        let path = try writeAgentJson("""
            {
              "schemaVersion": 1,
              "snapshotId": "old",
              "worldId": "stale",
              "edit": { "operations": [] }
            }
            """)

        let result = try await parseCommand("agent check --path \(path.path)").cmdOrDie.run(.defaultEnv, .emptyStdin)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.joined(separator: "\n").contains("Agent JSON is stale"))
    }

    func testStaleWorldIdStopsBeforeOperationValidation() async throws {
        let path = try writeAgentJson("""
            {
              "schemaVersion": 1,
              "snapshotId": "old",
              "worldId": "stale",
              "edit": {
                "operations": [
                  { "type": "placePane", "pane": { "tabGroupId": "tabgroup-missing" }, "relation": "leftOf", "target": { "tabGroupId": "tabgroup-also-missing" } }
                ]
              }
            }
            """)

        let result = try await parseCommand("agent check --path \(path.path)").cmdOrDie.run(.defaultEnv, .emptyStdin)

        let stderr = result.stderr.joined(separator: "\n")
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(stderr.contains("Agent JSON is stale"))
        XCTAssertFalse(stderr.contains("placePane"))
    }

    func testWorldIdIgnoresFocusChanges() async throws {
        let root = Workspace.get(byName: "a").rootTilingContainer
        let first = TestWindow.new(id: 1, parent: root)
        let second = TestWindow.new(id: 2, parent: root)

        _ = first.focusWindow()
        let firstWorldId = try await queryWorldId()
        _ = second.focusWindow()
        let secondWorldId = try await queryWorldId()

        XCTAssertEqual(firstWorldId, secondWorldId)
    }

    func testMoveTabGroupToWorkspaceIsMigratedIntoSidebarTabsAfterApply() async throws {
        let source = Workspace.get(byName: "a")
        let group = TilingContainer(parent: source.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        _ = TestWindow.new(id: 2, parent: group)
        _ = TestWindow.new(id: 3, parent: group)

        let path = try writeAgentJson("""
            {
              "schemaVersion": 1,
              "edit": {
                "operations": [
                  { "type": "moveTabGroupToWorkspace", "tabGroupId": "tabgroup-2", "workspace": "b" }
                ]
              }
            }
            """)

        let result = try await parseCommand("agent apply --path \(path.path)").cmdOrDie.run(.defaultEnv, .emptyStdin)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(Workspace.all.contains { workspaceContainsAgentTabGroupForTests($0) })
        let targetWindows = Workspace.all
            .filter { $0.name == "b" || $0.preferredMonitorPointForTesting == Workspace.get(byName: "b").preferredMonitorPointForTesting }
            .flatMap(\.allLeafWindowsRecursive)
            .map(\.windowId)
            .sorted()
        XCTAssertEqual(targetWindows, [2, 3])
    }

    func testSwapPanesAcceptsPaneIdAliases() async throws {
        let root = Workspace.get(byName: "a").rootTilingContainer
        _ = TestWindow.new(id: 1, parent: root)
        _ = TestWindow.new(id: 2, parent: root)

        let path = try writeAgentJson("""
            {
              "schemaVersion": 1,
              "edit": {
                "operations": [
                  { "type": "swapPanes", "paneId1": "pane-1", "paneId2": "pane-2" }
                ]
              }
            }
            """)

        let result = try await parseCommand("agent apply --path \(path.path)").cmdOrDie.run(.defaultEnv, .emptyStdin)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(root.children.compactMap { ($0 as? Window)?.windowId }, [2, 1])
    }

    func testSwapPanesAcceptsSnakeCaseAndWindowIdAliases() async throws {
        let root = Workspace.get(byName: "a").rootTilingContainer
        _ = TestWindow.new(id: 1, parent: root)
        _ = TestWindow.new(id: 2, parent: root)

        let path = try writeAgentJson("""
            {
              "schemaVersion": 1,
              "edit": {
                "operations": [
                  { "type": "swap_windows", "windowId1": 1, "windowId2": 2 }
                ]
              }
            }
            """)

        let result = try await parseCommand("agent apply --path \(path.path)").cmdOrDie.run(.defaultEnv, .emptyStdin)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(root.children.compactMap { ($0 as? Window)?.windowId }, [2, 1])
    }

    func testPlacePaneAndSetWinMuxFullscreen() async throws {
        let root = Workspace.get(byName: "a").rootTilingContainer
        _ = TestWindow.new(id: 1, parent: root)
        let editor = TestWindow.new(id: 2, parent: root)

        let path = try writeAgentJson("""
            {
              "schemaVersion": 1,
              "edit": {
                "operations": [
                  { "type": "placePane", "pane": { "windowId": 2 }, "relation": "leftOf", "target": { "windowId": 1 } },
                  { "type": "setWinMuxFullscreen", "windowId": 2, "value": true, "noOuterGaps": true }
                ]
              }
            }
            """)

        let result = try await parseCommand("agent apply --path \(path.path)").cmdOrDie.run(.defaultEnv, .emptyStdin)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(root.children.compactMap { ($0 as? Window)?.windowId }, [2, 1])
        XCTAssertTrue(editor.isFullscreen)
        XCTAssertTrue(editor.noOuterGapsInFullscreen)
    }

    func testCreateTabGroupIsDisabledForSidebarTabs() async throws {
        let root = Workspace.get(byName: "a").rootTilingContainer
        _ = TestWindow.new(id: 1, parent: root)
        _ = TestWindow.new(id: 2, parent: root)
        _ = TestWindow.new(id: 3, parent: root)

        let path = try writeAgentJson("""
            {
              "schemaVersion": 1,
              "edit": {
                "operations": [
                  {
                    "type": "createTabGroup",
                    "tabGroupId": "tabgroup-new-all",
                    "windows": [1, 2, 3],
                    "activeWindowId": 2
                  }
                ]
              }
            }
            """)

        let result = try await parseCommand("agent apply --path \(path.path)").cmdOrDie.run(.defaultEnv, .emptyStdin)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.joined(separator: "\n").contains("Folder creation through legacy JSON is disabled"))
        XCTAssertTrue(root.allAgentTabGroupsForTests.isEmpty)
    }

    func testCreateTabGroupDoesNotCreateNewWorkspaceWhenDisabled() async throws {
        let main = TestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let secondary = TestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([main, secondary])
        let source = Workspace.get(byName: "source")
        source.seedMonitorIfNeeded(secondary)
        _ = TestWindow.new(id: 11, parent: source.rootTilingContainer)
        _ = TestWindow.new(id: 12, parent: source.rootTilingContainer)

        let path = try writeAgentJson("""
            {
              "schemaVersion": 1,
              "edit": {
                "operations": [
                  {
                    "type": "createTabGroup",
                    "workspace": "tabs",
                    "windows": [11, 12]
                  }
                ]
              }
            }
            """)

        let result = try await parseCommand("agent apply --path \(path.path)").cmdOrDie.run(.defaultEnv, .emptyStdin)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.joined(separator: "\n").contains("Folder creation through legacy JSON is disabled"))
        XCTAssertNil(Workspace.existing(byName: "tabs"))
    }

    func testCreateTabGroupRejectsDisabledOperationAndDuplicateWindows() async throws {
        let root = Workspace.get(byName: "a").rootTilingContainer
        _ = TestWindow.new(id: 1, parent: root)
        _ = TestWindow.new(id: 2, parent: root)

        let path = try writeAgentJson("""
            {
              "schemaVersion": 1,
              "edit": {
                "operations": [
                  { "type": "createTabGroup", "tabs": [1, 2, 1] }
                ]
              }
            }
            """)

        let result = try await parseCommand("agent check --path \(path.path)").cmdOrDie.run(.defaultEnv, .emptyStdin)

        XCTAssertEqual(result.exitCode, 1)
        let stderr = result.stderr.joined(separator: "\n")
        XCTAssertTrue(stderr.contains("Folder creation through legacy JSON is disabled"))
        XCTAssertTrue(stderr.contains("Legacy folder JSON: window 1 appears more than once"))
    }

    func testAddWindowToLegacyFolderGuidesTowardTabLayout() async throws {
        let root = Workspace.get(byName: "a").rootTilingContainer
        let legacyFolder = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        _ = TestWindow.new(id: 1, parent: legacyFolder)
        _ = TestWindow.new(id: 2, parent: root)

        let path = try writeAgentJson("""
            {
              "schemaVersion": 1,
              "edit": {
                "operations": [
                  { "type": "addWindowToTabGroup", "windowId": 2, "tabGroupId": "tabgroup-1" }
                ]
              }
            }
            """)

        let result = try await parseCommand("agent check --path \(path.path)").cmdOrDie.run(.defaultEnv, .emptyStdin)

        let stderr = result.stderr.joined(separator: "\n")
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(stderr.contains("Adding windows through legacy folder JSON is disabled"))
        XCTAssertTrue(stderr.contains("use placePane or setTabLayout with split nodes instead"))
        XCTAssertFalse(stderr.contains("setWorkspaceLayout"))
    }

    func testLegacyTopTabApplyOperationsAreInertWhenValidationIsBypassed() async throws {
        let root = Workspace.get(byName: "a").rootTilingContainer
        let first = TestWindow.new(id: 1, parent: root)
        let second = TestWindow.new(id: 2, parent: root)
        var context = AgentApplyContext()

        try await AgentOperation
            .createTabGroup(tabGroupId: "new-tabs", workspace: nil, tabs: [1, 2], activeWindowId: 2)
            .apply(context: &context)

        XCTAssertTrue(context.tabGroupAliases.isEmpty)
        XCTAssertTrue(root.allAgentTabGroupsForTests.isEmpty)
        XCTAssertEqual(root.children.compactMap { ($0 as? Window)?.windowId }, [1, 2])
        XCTAssertTrue(first.parent === root)
        XCTAssertTrue(second.parent === root)

        let legacyGroup = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let legacyFirst = TestWindow.new(id: 3, parent: legacyGroup)
        _ = TestWindow.new(id: 4, parent: legacyGroup)
        legacyFirst.markAsMostRecentChild()
        context.tabGroupAliases["legacy"] = legacyGroup

        try await AgentOperation
            .addWindowToTabGroup(windowId: 1, tabGroupId: "legacy", activeWindowId: 1)
            .apply(context: &context)
        try await AgentOperation
            .setActiveTab(tabGroupId: "legacy", windowId: 4)
            .apply(context: &context)

        XCTAssertTrue(first.parent === root)
        XCTAssertEqual(legacyGroup.children.compactMap { ($0 as? Window)?.windowId }, [3, 4])
        XCTAssertTrue(legacyGroup.mostRecentWindowRecursive === legacyFirst)
    }

}


func writeAgentJson(_ json: String) throws -> URL {
    let url = URL(filePath: NSTemporaryDirectory())
        .appending(path: "winmux-agent-\(UUID().uuidString).json")
    try json.write(to: url, atomically: true, encoding: .utf8)
    return url
}

@MainActor
func queryWorldId() async throws -> String {
    let result = try await parseCommand("agent query").cmdOrDie.run(.defaultEnv, .emptyStdin)
    let data = try XCTUnwrap(result.stdout.joined(separator: "\n").data(using: .utf8))
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    return try XCTUnwrap(json["worldId"] as? String)
}

extension TilingContainer {
    @MainActor
    var allAgentTabGroupsForTests: [TilingContainer] {
        var result: [TilingContainer] = []
        func visit(_ node: TreeNode) {
            guard let container = node as? TilingContainer else { return }
            if container.layout == .tabGroup, container.children.count > 1 {
                result.append(container)
                return
            }
            for child in container.children {
                visit(child)
            }
        }
        visit(self)
        return result
    }

    @MainActor
    var agentWindowIdsForTests: [UInt32] {
        children.compactMap { $0.anyLeafWindowRecursive?.windowId }
    }
}

@MainActor
private func workspaceContainsAgentTabGroupForTests(_ workspace: Workspace) -> Bool {
    containsAgentTabGroupForTests(workspace.rootTilingContainer)
}

@MainActor
private func containsAgentTabGroupForTests(_ node: TreeNode) -> Bool {
    if let container = node as? TilingContainer, container.layout == .tabGroup, container.children.count > 1 {
        return true
    }
    return node.children.contains(where: containsAgentTabGroupForTests)
}
