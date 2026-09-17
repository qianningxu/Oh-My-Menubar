import XCTest

final class CliDescriptionGeneratedTest: XCTestCase {
    func testTabCommandsArePrimaryAndWorkspaceCommandsAreLegacyAliases() throws {
        let descriptions = try String(contentsOf: projectRoot.appending(path: "Sources/Cli/subcommandDescriptionsGenerated.swift"))

        XCTAssertTrue(descriptions.contains(#"["  tab", "Focus the specified tab"]"#))
        XCTAssertTrue(descriptions.contains(#"["  workspace", "Legacy alias for tab"]"#))
        XCTAssertTrue(descriptions.contains(#"["  list-tabs", "Print tabs that satisfy conditions"]"#))
        XCTAssertTrue(descriptions.contains(#"["  list-workspaces", "Legacy alias for list-tabs"]"#))
        XCTAssertTrue(descriptions.contains(#"["  project", "Focus the specified project"]"#))
        XCTAssertTrue(descriptions.contains(#"["  folder", "Legacy alias for project"]"#))
        XCTAssertTrue(descriptions.contains(#"["  move-node-to-project", "Move the focused window to the specified project"]"#))
        XCTAssertTrue(descriptions.contains(#"["  move-node-to-folder", "Legacy alias for move-node-to-project"]"#))
        XCTAssertTrue(descriptions.contains(#"["  move-node-to-tab", "Move the focused window to the specified tab"]"#))
        XCTAssertTrue(descriptions.contains(#"["  move-node-to-workspace", "Legacy alias for move-node-to-tab"]"#))
        XCTAssertTrue(descriptions.contains(#"["  reorder-tab", "Reorder a tab before or after another tab"]"#))
        XCTAssertTrue(descriptions.contains(#"["  reorder-workspace", "Legacy alias for reorder-tab"]"#))
        XCTAssertTrue(descriptions.contains(#"["  stack-with", "Put the focused window into the same window stack as the nearest window in the specified direction."]"#))
        XCTAssertFalse(descriptions.contains(#"["  move-node-to-project", "Disabled legacy folder command"]"#))
        XCTAssertFalse(descriptions.contains("Alias for flatten-workspace-tree"))
        XCTAssertFalse(descriptions.contains("legacy folder stacking"))
    }

    func testDetailedHelpAdvertisesTabSyntaxOnly() throws {
        let help = try String(contentsOf: projectRoot.appending(path: "Sources/Common/cmdHelpGenerated.swift"))

        XCTAssertTrue(help.contains("USAGE: tab [-h|--help]"))
        XCTAssertTrue(help.contains("USAGE: list-tabs [-h|--help]"))
        XCTAssertTrue(help.contains("USAGE: project [-h|--help]"))
        XCTAssertTrue(help.contains("USAGE: move-node-to-project [-h|--help]"))
        XCTAssertTrue(help.contains("USAGE: move-node-to-tab [-h|--help]"))
        XCTAssertTrue(help.contains("USAGE: move-tab-to-monitor [-h|--help]"))
        XCTAssertTrue(help.contains("USAGE: reorder-tab [-h|--help]"))
        XCTAssertTrue(help.contains("USAGE: summon-tab [-h|--help]"))
        XCTAssertTrue(help.contains("Projects are numbered top to bottom in project-selector order."))

        XCTAssertFalse(help.contains("workspace [-h|--help]"))
        XCTAssertFalse(help.contains("list-workspaces [-h|--help]"))
        XCTAssertFalse(help.contains("move-node-to-workspace [-h|--help]"))
        XCTAssertFalse(help.contains("move-workspace-to-monitor [-h|--help]"))
        XCTAssertFalse(help.contains("reorder-workspace [-h|--help]"))
        XCTAssertFalse(help.contains("summon-workspace [-h|--help]"))
        XCTAssertFalse(help.contains("workspace-back-and-forth [-h|--help]"))
        XCTAssertFalse(help.contains("flatten-workspace-tree [-h|--help]"))
        XCTAssertFalse(help.contains("folder [-h|--help]"))
        XCTAssertFalse(help.contains("--workspace <tab>"))
        XCTAssertFalse(help.contains("Disabled legacy folder command"))
        XCTAssertFalse(help.contains("with Unfolded after the last folder"))
    }
}
