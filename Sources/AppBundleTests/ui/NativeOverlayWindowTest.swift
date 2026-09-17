@testable import AppBundle
import XCTest

final class NativeOverlayWindowTest: XCTestCase {
    func testChatGPTCompanionsStayUnmanagedWithoutExcludingMainWindows() {
        for id in [KnownBundleId.chatgpt, .codex] {
            XCTAssertTrue(isNativeOverlayWindow(level: .alwaysOnTopWindow, appId: id))
            XCTAssertFalse(isNativeOverlayWindow(level: .normalWindow, appId: id))
            XCTAssertFalse(isNativeOverlayWindow(level: nil, appId: id))
        }
        XCTAssertFalse(isNativeOverlayWindow(level: .alwaysOnTopWindow, appId: .vscode))
        XCTAssertFalse(isNativeOverlayWindow(level: .alwaysOnTopWindow, appId: nil))
        XCTAssertTrue(isNativeOverlayWindow(level: .unknown(windowLevel: 1001), appId: nil))
    }

    @MainActor
    func testRestoredTiledCompanionIsRemovedFromWorkspace() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "companion")
        let window = Window(id: 9123, CompanionApp(), lastFloatingSize: nil,
                            parent: workspace.rootTilingContainer, adaptiveWeight: 1, index: 0)
        XCTAssertTrue(normalizeSystemOverlayWindow(window, level: .alwaysOnTopWindow))
        XCTAssertTrue(window.parent === macosPopupWindowsContainer)
        XCTAssertFalse(window.participatesInWorkspaceFocus)
        XCTAssertFalse(workspace.allLeafWindowsRecursive.contains(window))
        window.unbindFromParent()
    }
}

private final class CompanionApp: AbstractApp {
    let pid: Int32 = 0
    let rawAppBundleId: String? = "com.openai.codex"
    let name: String? = "ChatGPT"
    let execPath: String? = nil
    let bundlePath: String? = nil
    var windows: [Window] = []
    @MainActor func getFocusedWindow() -> Window? { nil }
}
