@testable import AppBundle
import AppKit
import XCTest

final class ShortcutSettingsWindowPresentationTest: XCTestCase {
    @MainActor
    func testPresentationRetriesUntilSwiftUICreatesWindow() async {
        let expectedWindow = NSWindow()
        var lookupCount = 0
        var presentedWindow: NSWindow?

        let task = presentShortcutSettingsWindowWhenAvailable(
            policy: .init(maxAttempts: 4, delayNanoseconds: 0),
            lookup: {
                lookupCount += 1
                return lookupCount == 3 ? expectedWindow : nil
            },
            present: { presentedWindow = $0 },
        )
        await task.value

        XCTAssertEqual(lookupCount, 3)
        XCTAssertTrue(presentedWindow === expectedWindow)
    }

    @MainActor
    func testPresentationStopsAfterBoundedAttempts() async {
        var lookupCount = 0
        var didPresent = false

        let task = presentShortcutSettingsWindowWhenAvailable(
            policy: .init(maxAttempts: 3, delayNanoseconds: 0),
            lookup: {
                lookupCount += 1
                return nil
            },
            present: { _ in didPresent = true },
        )
        await task.value

        XCTAssertEqual(lookupCount, 3)
        XCTAssertFalse(didPresent)
    }
}
