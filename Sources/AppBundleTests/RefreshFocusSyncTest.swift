@testable import AppBundle
import AppKit
import XCTest

final class RefreshFocusSyncTest: XCTestCase {
    @MainActor
    func testGlobalFloatingWindowKeepsNativeFocus() {
        setUpWorkspacesForTests()
        let window = TestWindow.new(id: 912, parent: globalFloatingWindowsContainer)
        updateFocusCache(window)
        XCTAssertEqual(focus.windowOrNil?.windowId, window.windowId)
    }

    @MainActor
    func testShouldNotSyncFocusBackToPopupWindow() {
        setUpWorkspacesForTests()

        let popup = TestWindow.new(id: 1, parent: macosPopupWindowsContainer)

        XCTAssertFalse(shouldSyncFocusBackToMacOs(nativeFocused: popup, frontmostActivationPolicy: .accessory))
    }

    @MainActor
    func testShouldNotSyncFocusBackToAccessoryAppWithoutFocusedWindow() {
        XCTAssertFalse(shouldSyncFocusBackToMacOs(nativeFocused: nil, frontmostActivationPolicy: .accessory))
    }

    @MainActor
    func testLaunchingRegularAppWithoutFocusedWindowKeepsActivation() {
        XCTAssertFalse(shouldSyncFocusBackToMacOs(nativeFocused: nil, frontmostActivationPolicy: .regular))
    }

    @MainActor
    func testMissingFrontmostAppStillAllowsFocusRecovery() {
        XCTAssertTrue(shouldSyncFocusBackToMacOs(nativeFocused: nil, frontmostActivationPolicy: nil))
    }

    @MainActor
    func testShouldSyncFocusBackToRegularWorkspaceWindow() {
        setUpWorkspacesForTests()

        let window = TestWindow.new(id: 1, parent: focus.workspace)

        XCTAssertTrue(shouldSyncFocusBackToMacOs(nativeFocused: window, frontmostActivationPolicy: .regular))
    }
}
