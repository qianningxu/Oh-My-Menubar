@testable import AppBundle
import Foundation
import XCTest

final class MenuBarFocusProgressTest: XCTestCase {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    func testDailyTimeRunsFromSevenThirtyToTwentyOneHundred() {
        let calendar = utcCalendar
        XCTAssertEqual(menuBarFocusTimeProgress(for: .day, now: date("2026-09-27T07:29:00Z"), calendar: calendar), 0)
        XCTAssertEqual(menuBarFocusTimeProgress(for: .day, now: date("2026-09-27T14:15:00Z"), calendar: calendar), 0.5, accuracy: 0.0001)
        XCTAssertEqual(menuBarFocusTimeProgress(for: .day, now: date("2026-09-27T21:00:00Z"), calendar: calendar), 1)
    }

    func testWeeklyTimeEndsBeforeSaturday() {
        let calendar = utcCalendar
        XCTAssertEqual(menuBarFocusTimeProgress(for: .week, now: date("2026-09-28T00:00:00Z"), calendar: calendar), 0)
        XCTAssertEqual(menuBarFocusTimeProgress(for: .week, now: date("2026-09-30T12:00:00Z"), calendar: calendar), 0.5, accuracy: 0.0001)
        XCTAssertEqual(menuBarFocusTimeProgress(for: .week, now: date("2026-10-03T00:00:00Z"), calendar: calendar), 1)
    }

    func testMonthlyTimeSpansFullCalendarMonth() {
        let calendar = utcCalendar
        XCTAssertEqual(menuBarFocusTimeProgress(for: .month, now: date("2026-09-01T00:00:00Z"), calendar: calendar), 0)
        XCTAssertEqual(menuBarFocusTimeProgress(for: .month, now: date("2026-09-16T00:00:00Z"), calendar: calendar), 0.5, accuracy: 0.0001)
        XCTAssertEqual(menuBarFocusTimeProgress(for: .month, now: date("2026-09-30T12:00:00Z"), calendar: calendar), 29.5 / 30, accuracy: 0.0001)
    }
}
