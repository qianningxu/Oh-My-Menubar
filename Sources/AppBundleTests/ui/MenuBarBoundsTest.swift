import AppKit
@testable import AppBundle
import XCTest

final class MenuBarBoundsTest: XCTestCase {
    @MainActor
    func testWorkspaceBarStaysAtMenuBarSurfaceLayer() {
        let panel = WorkspaceSidebarPanel.shared
        XCTAssertFalse(panel.hasShadow)
        panel.setProjectMenuPresentation(isPresented: false, extraHeight: 0)
        XCTAssertFalse(panel.isFloatingPanel)
        XCTAssertEqual(panel.level, WinMuxPanelLayer.menuBarSurface.level)
        XCTAssertGreaterThan(panel.level.rawValue, WinMuxPanelLayer.workspaceBackground.level.rawValue)

        panel.setProjectMenuPresentation(isPresented: true, extraHeight: 100)
        XCTAssertEqual(panel.level, WinMuxPanelLayer.menuBarSurface.level)
        panel.setProjectMenuPresentation(isPresented: false, extraHeight: 0)
        XCTAssertEqual(panel.level, WinMuxPanelLayer.menuBarSurface.level)
    }

    func testWidgetAndWorkspaceBarsOccupyMenuStrip() {
        for height: CGFloat in [24, 32] {
            let screen = NSRect(x: -1920, y: 120, width: 1920, height: 1080)
            let visible = NSRect(x: -1920, y: 145, width: 1920, height: 1055 - height)
            let left = workspaceSidebarFloatingProjectBarPanelFrame(
                screenFrame: screen,
                visibleFrame: visible,
                barSize: CGSize(width: 420, height: 32)
            )
            let right = menuBarStatusWidgetRegionFrame(
                screenFrame: screen,
                auxiliaryTopRightArea: nil,
                barHeight: height
            )
            XCTAssertEqual(left.midY, (visible.maxY + screen.maxY) / 2)
            XCTAssertEqual(left.height, 32)
            XCTAssertEqual(right.maxY, screen.maxY)
            XCTAssertEqual(right.minX, screen.minX)
            XCTAssertEqual(right.width, screen.width)
            XCTAssertEqual(left.midX, screen.midX)
            XCTAssertEqual(left.width, 420)
        }
    }

    func testBarLayerIsBelowSystemMenuBar() {
        XCTAssertEqual(WinMuxPanelLayer.menuBarSurface.level.rawValue, Int(CGWindowLevelForKey(.dockWindow)))
        XCTAssertLessThan(WinMuxPanelLayer.menuBarSurface.level.rawValue, 21)
        XCTAssertLessThan(WinMuxPanelLayer.menuBarSurface.level.rawValue, NSWindow.Level.mainMenu.rawValue)
        XCTAssertGreaterThan(WinMuxPanelLayer.menuBarSurface.level.rawValue, WinMuxPanelLayer.workspaceBackground.level.rawValue)
        XCTAssertEqual(menuBarFloatingSurfaceOutset, 0)
    }
}
