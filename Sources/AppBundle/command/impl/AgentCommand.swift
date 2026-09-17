import AppKit
import Common
import Foundation

struct AgentCommand: Command {
    let args: AgentCmdArgs
    var shouldResetClosedWindowsCache: Bool { args.subcommand.val == .apply }
    var canSkipPostCommandRefresh: Bool { args.subcommand.val != .apply }

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        switch args.subcommand.val {
            case .query:
                let snapshot = try await AgentSnapshot.query()
                guard let json = JSONEncoder.winMuxDefault.encodeToString(snapshot) else {
                    return io.err("Failed to encode agent snapshot")
                }
                if let path = args.path {
                    try json.write(to: URL(filePath: path), atomically: true, encoding: .utf8)
                    return true
                }
                return io.out(json)
            case .check:
                let request: AgentRequest
                do {
                    request = try AgentRequest.read(path: args.path.orDie())
                } catch {
                    return io.err("Failed to read agent JSON: \(describeAgentJsonError(error))")
                }
                let errors = try await request.validate()
                if errors.isEmpty {
                    return io.out("OK")
                }
                return io.err(errors.joinErrors())
            case .apply:
                let request: AgentRequest
                do {
                    request = try AgentRequest.read(path: args.path.orDie())
                } catch {
                    return io.err("Failed to read agent JSON: \(describeAgentJsonError(error))")
                }
                let errors = try await request.validate()
                if !errors.isEmpty {
                    return io.err(errors.joinErrors())
                }
                try await request.apply()
                return true
            case .skill:
                return io.out(agentSkillText)
        }
    }
}

private func describeAgentJsonError(_ error: Error) -> String {
    func path(_ codingPath: [any CodingKey]) -> String {
        let result = codingPath.map(\.stringValue).joined(separator: ".")
        return result.isEmpty ? "<root>" : result
    }
    switch error {
        case DecodingError.keyNotFound(let key, let context):
            return "missing key '\(key.stringValue)' at \(path(context.codingPath)): \(context.debugDescription)"
        case DecodingError.typeMismatch(_, let context):
            return "type mismatch at \(path(context.codingPath)): \(context.debugDescription)"
        case DecodingError.valueNotFound(_, let context):
            return "missing value at \(path(context.codingPath)): \(context.debugDescription)"
        case DecodingError.dataCorrupted(let context):
            return "invalid data at \(path(context.codingPath)): \(context.debugDescription)"
        default:
            return error.localizedDescription
    }
}

private let agentSkillText = """
    ---
    name: winmux-agent
    description: Use when arranging WinMux windows through the agent JSON interface. Query to a file, read that exact file, edit it, then apply that exact file.
    ---

    # WinMux Agent

    You MUST use the file workflow. Do not guess operation names. Do not search the repository for docs. This skill is the command reference.

    Required workflow for every user request:
    1. Query the current state into a JSON file:
       `winmux agent query --path /tmp/winmux-agent.json`
    2. Read the file you just wrote:
       `/tmp/winmux-agent.json`
       Important: `query --path` writes the JSON to the path. It does not print the JSON to stdout. Running `ls /tmp/winmux-agent.json` is not enough; you must read the file contents.
    3. Edit only the `edit` object inside `/tmp/winmux-agent.json`.
       Treat `schemaVersion`, `snapshotId`, `worldId`, `inventory`, and `reasoning` as read-only context. Do not edit titles, app names, frames, panes, Tab inventory, or the world id.
    4. For a small change, replace the entire `edit.operations` array with only the operations for the current user request. Do not append to operations left by an earlier request.
    5. For a full Tab redesign, edit `edit.layout.tabs` instead of `edit.operations`. Legacy `edit.layout.workspaces` is still accepted.
    6. Apply the same file:
       `winmux agent apply --path /tmp/winmux-agent.json`
    7. If apply says the JSON is stale or the `worldId` does not match, discard `/tmp/winmux-agent.json`, run the query command again, read the new file, redo the edit, and apply again.
    8. Return a short summary of what changed.

    Usually skip the separate check command. `apply` validates before changing anything. Use `winmux agent check --path /tmp/winmux-agent.json` only for complex edits or after a failed apply.

    The file includes a `worldId` freshness guard. If windows move, close, change fullscreen state, or the user manually changes the layout, discard the file and query again.

    For small changes, replace the entire `edit.operations` array. Do not append to old operations unless the user asked for one multi-step batch. Prefer operations for focus, moving one window, swapping, placing one pane, setting WinMux fullscreen, closing, or parking windows.

    For full Tab setup, edit `edit.layout.tabs`. Use layout mode for requests like "set up my coding Tab" or "organize all windows into Tabs". Legacy `edit.layout.workspaces` is still accepted.

    WinMux Tabs are managed in the sidebar. A Tab can contain a composed split layout with multiple windows. Do not create old top folders or sidebar folders through agent JSON. Use split/window layout nodes to compose multiple windows inside one Tab.

    If the user says "all Chrome windows" or "all IDEs", scan every item in `inventory.windows` and include every matching `windowId`. Do not stop after the first match. Existing legacy `inventory.tabGroups` may appear for old state; you may move or resize those panes, but do not create new folders.

    `createTabGroup`, `addWindowToTabGroup`, `setActiveTab`, and layout nodes with `"kind": "tabGroup"` are disabled. To put windows together, use `placePane` or `setTabLayout` with `"split"` and `"window"` nodes.

    Read the query file before choosing IDs:
    - Find windows in `inventory.windows`. Match by `appName`, `title`, and `windowId`.
    - Legacy folders may exist in `inventory.tabGroups`. Use `tabGroupId` only when moving or editing an existing legacy folder.
    - Find current layout in `reasoning.panes`, `reasoning.relations`, and `reasoning.rawTrees`.
    - Use `size` and `sizeAxis` from the query file to understand current proportions before resizing.
    - Never invent a `windowId`, `paneId`, `tabGroupId`, or Tab name if the query file already gives the correct value.

    Canonical operation type names are camelCase. Common snake_case aliases are accepted. Prefer Tab-named operation aliases; legacy Workspace-named aliases are still accepted.

    Pane refs:
    - Window: `{ "windowId": 123 }` or pane id `"pane-123"`
    - Legacy folder: `{ "tabGroupId": "tabgroup-123" }` or pane id `"pane-tabgroup-123"`

    All `edit.operations` commands:
    - `focusWindow`: `{ "type": "focusWindow", "windowId": 123 }`
    - `focusWindow` by match: `{ "type": "focusWindow", "match": { "appName": "Google Chrome", "titleContains": "Docs" } }`
    - `focusTab`: `{ "type": "focusTab", "tab": "2" }`
    - `moveWindowToTab`: `{ "type": "moveWindowToTab", "windowId": 123, "tab": "2", "focus": true }`
    - `moveTabGroupToTab` for existing legacy folders: `{ "type": "moveTabGroupToTab", "tabGroupId": "tabgroup-123", "tab": "2", "focus": true }`
    - `swapPanes`: `{ "type": "swapPanes", "paneId1": "pane-123", "paneId2": "pane-456" }`
    - `swapPanes` alt: `{ "type": "swapPanes", "a": { "windowId": 123 }, "b": { "tabGroupId": "tabgroup-456" } }`
    - `placePane`: `{ "type": "placePane", "pane": { "windowId": 123 }, "relation": "below", "target": { "windowId": 456 } }`
    - `moveWindowOutOfTabGroup` for existing legacy folders: `{ "type": "moveWindowOutOfTabGroup", "windowId": 123 }`
    - `setWinMuxFullscreen`: `{ "type": "setWinMuxFullscreen", "windowId": 123, "value": true, "noOuterGaps": true }`
    - `setFloating`: `{ "type": "setFloating", "windowId": 123, "value": true }`
    - `closeWindow`: `{ "type": "closeWindow", "windowId": 123, "quitAppIfLastWindow": true }`
    - `parkWindow`: `{ "type": "parkWindow", "pane": { "windowId": 123 }, "tab": "__agent_parked" }`
    - `setPaneSize`: `{ "type": "setPaneSize", "pane": { "windowId": 123 }, "size": 0.8 }`
    - `setPaneSize` percent alt: `{ "type": "setPaneSize", "pane": { "tabGroupId": "tabgroup-123" }, "sizePercent": 80 }`
    - `setPaneSize` vertical split: `{ "type": "setPaneSize", "pane": { "windowId": 123 }, "axis": "vertical", "size": 0.75 }`
    - `setTabLayout`: `{ "type": "setTabLayout", "layout": { "name": "1", "layout": { "kind": "window", "windowId": 123 } } }`

    For a small change, the `edit` object in the queried file should look like this. Keep the rest of the queried file unchanged:
    ```json
    {
      "edit": {
        "operations": [
          { "type": "focusWindow", "windowId": 123 }
        ]
      }
    }
    ```

    Relations for `placePane`: `leftOf`, `rightOf`, `above`, `below`.

    WinMux fullscreen is not macOS native fullscreen. Use `setWinMuxFullscreen`.

    If the user wants a window not to show in the current Tab but does not ask to close it, use `parkWindow` or `moveWindowToTab`, not native minimize.

    Full layout mode:
    - Edit `edit.layout.tabs`.
    - Replace `edit.operations` with an empty array unless the user explicitly asked for extra operations in the same batch.
    - Prefer layout mode when the user asks to design or reorganize a Tab, especially when the request includes exact sizes like "80/20", "left takes 80%", or multiple panes in one Tab.
    - A split's `direction` describes how children are arranged: `horizontal` means left/right; `vertical` means top/bottom.
    - Tab layout shape: `{ "name": "coding", "layout": <layoutNode>, "focus": { "windowId": 123 }, "floating": [{ "windowId": 456 }] }`
    - Split node: `{ "kind": "split", "direction": "horizontal", "children": [<layoutNode>, <layoutNode>], "size": 0.5 }`
    - Window node: `{ "kind": "window", "windowId": 123, "size": 0.5 }`
    - Directions: `horizontal`, `vertical`.
    - `size` is a proportional share of the parent split. Use `0.8` for 80%. `80` and `sizePercent: 80` are also accepted. If a sibling omits `size`, it receives an equal share of the remaining space.
    - For `setPaneSize`, add `"axis": "vertical"` when resizing a top/bottom split and `"axis": "horizontal"` when resizing a left/right split. Without `axis`, WinMux uses the nearest split containing the pane.
    - For "Chrome 80%, IDE column 20%, terminal below IDE", use a horizontal root split with Chrome windows arranged as split/window nodes at `size: 0.8` and a vertical split `size: 0.2` containing the IDE and terminal windows.

    For a full layout redesign, the `edit` object in the queried file should look like this. Keep the rest of the queried file unchanged:
    ```json
    {
      "edit": {
        "layout": {
          "tabs": [
            {
              "name": "1",
              "layout": {
                "kind": "split",
                "direction": "horizontal",
                "children": [
                  { "kind": "window", "windowId": 123, "size": 0.8 },
                  { "kind": "window", "windowId": 456, "size": 0.2 }
                ]
              },
              "focus": { "windowId": 123 }
            }
          ]
        }
      }
    }
    ```
    """
