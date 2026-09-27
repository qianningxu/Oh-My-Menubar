@testable import AppBundle
import Foundation
import XCTest

final class MenuBarBreakPotWidgetTest: XCTestCase {
    func testMonthlyCalendarSpansRunsBetweenRecordDates() throws {
        let url = FileManager.default.temporaryDirectory.appending(component: UUID().uuidString + ".md")
        defer { try? FileManager.default.removeItem(at: url) }
        let contents = """
        | Date       | Focus   | Type |
        | ---------- | ------- | ---- |
        | 2026-08-31 | 15 h    |      |
        | 2026-09-06 | 21.99 h | half |
        | 2026-09-09 | 23 h    |      |
        | 2026-09-12 |         |      |
        | 2026-10-01 | 18 h    | 宁静夜晚 |
        """
        try contents.write(to: url, atomically: true, encoding: .utf8)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-27T08:00:00Z"))

        let spans = try XCTUnwrap(MenuBarFocusRecord.spansInMonth(at: url, now: now, calendar: calendar))
        XCTAssertEqual(spans.count, 3)
        XCTAssertEqual(spans[0].run.focusHours, 21.99)
        XCTAssertEqual(spans[0].run.displayFocus, "21.99h")
        XCTAssertEqual(spans[0].run.type, "half")
        XCTAssertEqual(calendar.component(.day, from: spans[0].start), 1)
        XCTAssertEqual(calendar.component(.day, from: spans[0].end), 6)
        XCTAssertEqual(calendar.component(.day, from: spans[1].start), 7)
        XCTAssertEqual(calendar.component(.day, from: spans[1].end), 9)
        XCTAssertEqual(spans.map(\.shadeIndex), [0, 1, 2])
        XCTAssertNil(spans[2].run.focusHours)
        XCTAssertEqual(calendar.component(.day, from: spans[2].end), 12)
    }

    func testFirstRecordStartsAtMonthBoundaryWhenNoEarlierRecordExists() throws {
        let url = FileManager.default.temporaryDirectory.appending(component: UUID().uuidString + ".md")
        defer { try? FileManager.default.removeItem(at: url) }
        try (MenuBarFocusRecord.header + "| 2026-09-06 | 21.99 h | half |\n")
            .write(to: url, atomically: true, encoding: .utf8)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-27T08:00:00Z"))

        let spans = try XCTUnwrap(MenuBarFocusRecord.spansInMonth(at: url, now: now, calendar: calendar))
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(calendar.component(.day, from: spans[0].start), 1)
        XCTAssertEqual(calendar.component(.day, from: spans[0].end), 6)
    }

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

    func testAlignedTableAndNonPaddedDateRemainUsable() throws {
        let url = FileManager.default.temporaryDirectory.appending(component: UUID().uuidString + ".md")
        defer { try? FileManager.default.removeItem(at: url) }
        let original = """
        | Date       | Focus   | Type |
        | ---------- | ------- | ---- |
        | 2026-9-26  | 26.55 h | 宁静夜晚 |

        Some later note.
        """
        try original.write(to: url, atomically: true, encoding: .utf8)
        let london = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = london
        let nextStart = try XCTUnwrap(MenuBarFocusRecord.nextStart(at: url, calendar: calendar))
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: nextStart).day, 27)
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-27T08:00:00Z"))
        try MenuBarFocusRecord.append(date: date, focusHours: 1.25, type: "晚起早退", at: url, calendar: calendar)
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("| 2026-09-27 | 1.25 h | 晚起早退 |\n\nSome later note."))
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
