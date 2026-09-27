@testable import AppBundle
import Foundation
import XCTest

final class MenuBarBreakPotWidgetTest: XCTestCase {
    func testNextPeriodStartsOnDayAfterLatestRow() throws {
        let london = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = london
        let contents = """
        | Date | Focus | Type |
        | ---- | ----- | ---- |
        | 2026-09-06 | 21.99 h | half |
        | 2026-09-22 | 22 h |  |
        """
        let lastDate = try XCTUnwrap(MenuBarFocusRecord.lastDate(in: contents, calendar: calendar))
        let nextStart = MenuBarFocusRecord.nextDay(after: lastDate, calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: nextStart).day, 23)
    }

    func testAppendReplacesPlaceholderAndKeepsExistingRows() throws {
        let url = FileManager.default.temporaryDirectory.appending(component: UUID().uuidString + ".md")
        defer { try? FileManager.default.removeItem(at: url) }
        try (MenuBarFocusRecord.header + "|      |       |      |\n").write(to: url, atomically: true, encoding: .utf8)
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-27T08:00:00Z"))
        try MenuBarFocusRecord.append(date: date, focusHours: 14.375, type: "宁静夜晚", at: url)
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("| 2026-09-27 | 14.38 h | 宁静夜晚 |"))
        XCTAssertFalse(contents.contains("|      |       |      |"))
    }

    func testFocusTotalClipsToNewPeriodAndExcludesBreak() throws {
        let formatter = ISO8601DateFormatter()
        let start = try XCTUnwrap(formatter.date(from: "2026-09-23T00:00:00Z"))
        let finish = try XCTUnwrap(formatter.date(from: "2026-09-27T12:00:00Z"))
        let entries = [
            SidebarSelfDataTimeEntry(
                start: try XCTUnwrap(formatter.date(from: "2026-09-22T23:00:00Z")),
                stop: try XCTUnwrap(formatter.date(from: "2026-09-23T01:00:00Z")),
                projectID: nil, projectName: "Study"
            ),
            SidebarSelfDataTimeEntry(
                start: try XCTUnwrap(formatter.date(from: "2026-09-27T11:00:00Z")),
                stop: try XCTUnwrap(formatter.date(from: "2026-09-27T13:00:00Z")),
                projectID: nil, projectName: "Study"
            ),
            SidebarSelfDataTimeEntry(
                start: try XCTUnwrap(formatter.date(from: "2026-09-24T10:00:00Z")),
                stop: try XCTUnwrap(formatter.date(from: "2026-09-24T11:00:00Z")),
                projectID: nil, projectName: "Break"
            ),
        ]
        XCTAssertEqual(menuBarBreakPotFocusHours(entries: entries, from: start, to: finish), 2)
    }
}
