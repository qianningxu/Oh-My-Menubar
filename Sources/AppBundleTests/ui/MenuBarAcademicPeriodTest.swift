@testable import AppBundle
import Foundation
import XCTest

final class MenuBarAcademicPeriodTest: XCTestCase {
    func testSemesterWeeksAndLondonMondayBoundaries() {
        let cases: [(String, String)] = [
            ("2026-09-10T12:00:00Z", "Week 0, Day 3/90"),
            ("2026-09-13T22:59:59Z", "Week 0, Day 6/90"),
            ("2026-09-13T23:00:00Z", "Week 1, Day 7/90"),
            ("2026-10-17T07:00:00Z", "Week 5, Day 40/90"),
            ("2026-10-18T23:00:00Z", "Week 6, Day 42/90 - Reading Week"),
            ("2026-10-25T23:59:59Z", "Week 6, Day 48/90 - Reading Week"),
            ("2026-10-26T00:00:00Z", "Week 7, Day 49/90"),
            ("2026-11-23T00:00:00Z", "Week 11, Day 77/90 - Revision Week"),
            ("2026-11-30T00:00:00Z", "Week 12, Day 84/90"),
            ("2026-12-21T00:00:00Z", "Week 12, Day 90/90"),
            ("2026-09-01T00:00:00Z", "Week 0, Day 0/90")
        ]
        for (date, expected) in cases {
            let period = MenuBarAcademicPeriod(now: ISO8601DateFormatter().date(from: date)!)
            XCTAssertEqual(period.title, expected, date)
        }
    }
}
