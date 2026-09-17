@testable import AppBundle
import XCTest

final class MenuBarBreakPotWidgetTest: XCTestCase {
    func testResetDateFormats() throws {
        let london = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-09T06:35:00Z"))
        for value in ["2026-09-09T07:35:00", "2026-09-09T07:35", "2026-09-09T07:35:00+01:00", "2026-09-09T06:35:00.000Z"] {
            XCTAssertEqual(menuBarBreakPotFinishDate(from: "---\nfinish: \(value)\n---", timeZone: london), expected, value)
        }
    }

    func testBlankFinishDoesNotReadNextProperty() {
        XCTAssertNil(menuBarBreakPotFinishDate(from: "---\nfinish: \n2026-09-09T07:35:00Z\n---"))
    }

    func testInvalidLocalDateIsRejected() {
        XCTAssertNil(menuBarBreakPotFinishDate(from: "finish: 2026-02-30T07:35:00"))
    }
}
