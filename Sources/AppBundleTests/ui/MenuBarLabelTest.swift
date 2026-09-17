@testable import AppBundle
import AppKit
import XCTest

final class MenuBarLabelTest: XCTestCase {
    func testEmptyTrayStateUsesAppIndicator() {
        XCTAssertTrue(menuBarLabelShouldUseAppIndicator(trayText: "", trayItems: []))
    }

    func testNonEmptyTrayTextKeepsTextLabel() {
        XCTAssertFalse(menuBarLabelShouldUseAppIndicator(trayText: "A", trayItems: []))
    }

    func testTrayItemsKeepConfiguredItemStyle() {
        XCTAssertFalse(menuBarLabelShouldUseAppIndicator(
            trayText: "",
            trayItems: [
                TrayItem(type: .mode, name: "A", isActive: true, hasFullscreenWindows: false),
            ]
        ))
    }

    @MainActor
    func testImageCacheReusesRenderedImage() {
        var renderCount = 0

        let images = exerciseMenuBarLabelImageCacheForTests(
            capacity: 2,
            keys: ["A", "A"]
        ) { _ in
            renderCount += 1
            return NSImage(size: NSSize(width: 1, height: 1))
        }

        XCTAssertEqual(renderCount, 1)
        XCTAssertTrue(images[0] === images[1])
    }

    @MainActor
    func testImageCacheEvictsLeastRecentlyUsedImage() {
        var renderCounts: [String: Int] = [:]

        let images = exerciseMenuBarLabelImageCacheForTests(
            capacity: 2,
            keys: ["A", "B", "A", "C", "A", "B"]
        ) { key in
            renderCounts[key, default: 0] += 1
            return NSImage(size: NSSize(width: 1, height: 1))
        }

        XCTAssertEqual(renderCounts, ["A": 1, "B": 2, "C": 1])
        XCTAssertTrue(images[0] === images[2])
        XCTAssertTrue(images[2] === images[4])
        XCTAssertFalse(images[1] === images[5])
    }
}
