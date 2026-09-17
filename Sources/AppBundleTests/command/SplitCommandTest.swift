@testable import AppBundle
import Common
import XCTest

@MainActor
final class SplitCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testRatiosUseLeftRightOrderWithRightPaneFocused() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer
        let left = TestWindow.new(id: 1, parent: root, adaptiveWeight: 300)
        let right = TestWindow.new(id: 2, parent: root, adaptiveWeight: 300)
        _ = right.focusWindow()
        config.enableNormalizationFlattenContainers = true
        for (ratio, expectedLeft) in [("1:2", 200.0), ("1:1", 300.0), ("2:1", 400.0)] {
            let result = try await parseCommand("split \(ratio)").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(result.exitCode, 0)
            XCTAssertEqual(left.hWeight, CGFloat(expectedLeft), accuracy: 0.001)
            XCTAssertEqual(right.hWeight, CGFloat(600 - expectedLeft), accuracy: 0.001)
        }
    }

    func testRatioLeavesOtherLayoutsUnchanged() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer
        let left = TestWindow.new(id: 1, parent: root, adaptiveWeight: 300)
        let right = TestWindow.new(id: 2, parent: root, adaptiveWeight: 300)
        _ = left.focusWindow()
        root.changeOrientation(.v)
        _ = try await parseCommand("split 1:2").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(left.getWeight(.v), right.getWeight(.v))
        root.changeOrientation(.h)
        TestWindow.new(id: 3, parent: root, adaptiveWeight: 300)
        let before = root.children.map { $0.getWeight(.h) }
        _ = try await parseCommand("split 2:1").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(root.children.map { $0.getWeight(.h) }, before)
    }

    func testSplit() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        try await SplitCommand(args: SplitCmdArgs(rawArgs: [], .vertical)).run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([
            .v_tiles([
                .window(1),
            ]),
            .window(2),
        ]))
    }

    func testSplitOppositeOrientation() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        try await SplitCommand(args: SplitCmdArgs(rawArgs: [], .opposite)).run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([
            .v_tiles([
                .window(1),
            ]),
            .window(2),
        ]))
    }

    func testChangeOrientation() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            }
            TestWindow.new(id: 2, parent: $0)
        }

        try await SplitCommand(args: SplitCmdArgs(rawArgs: [], .horizontal)).run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([
            .h_tiles([
                .window(1),
            ]),
            .window(2),
        ]))
    }

    func testToggleOrientation() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            }
            TestWindow.new(id: 2, parent: $0)
        }

        try await SplitCommand(args: SplitCmdArgs(rawArgs: [], .opposite)).run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([
            .h_tiles([
                .window(1),
            ]),
            .window(2),
        ]))
    }
}
