@testable import AppBundle
import Common
import XCTest

@MainActor
final class FocusPaneAndStackTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    private func cycle(_ direction: TabNextPrev) async throws {
        var args = FocusCmdArgs(rawArgs: [], targetArg: .tabRelative(direction))
        args.rawBoundariesAction = .wrapAroundTheWorkspace
        let result = try await FocusCommand(args: args).run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 0)
    }

    func testPaneCycleSkipsOtherStackWindowsAndRestoresSelectedWindow() async throws {
        let root = focus.workspace.rootTilingContainer
        let left = TestWindow.new(id: 9201, parent: root)
        let stack = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        _ = TestWindow.new(id: 9202, parent: stack)
        let selected = TestWindow.new(id: 9203, parent: stack)
        let right = TestWindow.new(id: 9204, parent: root)
        XCTAssertTrue(selected.focusWindow())
        try await cycle(.paneNext)
        XCTAssertTrue(focus.windowOrNil === right)
        try await cycle(.paneNext)
        XCTAssertTrue(focus.windowOrNil === left)
        try await cycle(.paneNext)
        XCTAssertTrue(focus.windowOrNil === selected)
        try await cycle(.panePrev)
        XCTAssertTrue(focus.windowOrNil === left)
    }

    func testStackCycleWrapsWithoutEnteringAnotherPaneOrStack() async throws {
        let root = focus.workspace.rootTilingContainer
        let outside = TestWindow.new(id: 9210, parent: root)
        let stack = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let first = TestWindow.new(id: 9211, parent: stack)
        let second = TestWindow.new(id: 9212, parent: stack)
        let otherStack = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        _ = TestWindow.new(id: 9213, parent: otherStack)
        _ = TestWindow.new(id: 9214, parent: otherStack)
        XCTAssertTrue(first.focusWindow())
        try await cycle(.stackNext)
        XCTAssertTrue(focus.windowOrNil === second)
        try await cycle(.stackNext)
        XCTAssertTrue(focus.windowOrNil === first)
        try await cycle(.stackPrev)
        XCTAssertTrue(focus.windowOrNil === second)
        XCTAssertTrue(outside.focusWindow())
        try await cycle(.stackNext)
        XCTAssertTrue(focus.windowOrNil === outside)
    }

    func testSingleStackIsOnePane() async throws {
        let stack = focus.workspace.rootTilingContainer
        stack.layout = .tabGroup
        let first = TestWindow.new(id: 9221, parent: stack)
        _ = TestWindow.new(id: 9222, parent: stack)
        XCTAssertTrue(first.focusWindow())
        try await cycle(.paneNext)
        XCTAssertTrue(focus.windowOrNil === first)
    }

    func testParsesPaneAndStackTargets() {
        for direction in [TabNextPrev.paneNext, .panePrev, .stackNext, .stackPrev] {
            var expected = FocusCmdArgs(rawArgs: [], targetArg: .tabRelative(direction))
            expected.rawBoundariesAction = .wrapAroundTheWorkspace
            testParseCommandSucc("focus --boundaries-action wrap-around-the-workspace \(direction.rawValue)", expected)
        }
    }
}
