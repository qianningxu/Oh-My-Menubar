@testable import AppBundle
import Foundation
import XCTest

final class MenuBarAcademicPeriodTest: XCTestCase {
    func testSemesterWeeksAndLondonMondayBoundaries() {
        let cases: [(String, String)] = [
            ("2026-09-10T12:00:00Z", "Y4S1 - Thu - 0/12W - 3/90d"),
            ("2026-09-13T22:59:59Z", "Y4S1 - Sun - 0/12W - 6/90d"),
            ("2026-09-13T23:00:00Z", "Y4S1 - Mon - 1/12W - 7/90d"),
            ("2026-10-18T23:00:00Z", "Y4S1 - Mon - 6/12W - 42/90d - Reading Week"),
            ("2026-10-25T23:59:59Z", "Y4S1 - Sun - 6/12W - 48/90d - Reading Week"),
            ("2026-10-26T00:00:00Z", "Y4S1 - Mon - 7/12W - 49/90d"),
            ("2026-11-23T00:00:00Z", "Y4S1 - Mon - 11/12W - 77/90d - Revision Week"),
            ("2026-11-30T00:00:00Z", "Y4S1 - Mon - 12/12W - 84/90d"),
            ("2026-12-21T00:00:00Z", "Y4S1 - Mon - 12/12W - 90/90d"),
            ("2026-09-01T00:00:00Z", "Y4S1 - Tue - 0/12W - 0/90d")
        ]
        for (date, expected) in cases {
            let period = MenuBarAcademicPeriod(now: ISO8601DateFormatter().date(from: date)!)
            XCTAssertEqual(period.title, expected, date)
        }
    }
}
