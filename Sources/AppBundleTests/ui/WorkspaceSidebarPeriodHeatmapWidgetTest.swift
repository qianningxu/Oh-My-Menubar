@testable import AppBundle
import Foundation
import XCTest

final class WorkspaceSidebarPeriodHeatmapWidgetTest: XCTestCase {
    func testSnapshotBuildsPeriodProgressValues() {
        let formatter = Self.localDateFormatter()
        let snapshot = PeriodHeatmapAggregator.snapshot(
            name: "Y3 summer",
            from: formatter.date(from: "2026-06-15")!,
            to: formatter.date(from: "2026-09-12")!,
            now: formatter.date(from: "2026-06-26")!,
        )

        assertEquals(snapshot.name, "Y3 summer")
        assertEquals(snapshot.totalDays, 90)
        assertEquals(snapshot.currentDay, 12)
        assertEquals(snapshot.totalWeeks, 13)
        assertEquals(snapshot.currentWeek, 2)
        assertEquals(snapshot.dayOfWeekInPeriod, 5)
        XCTAssertEqual(snapshot.weekProgress, 2.0 / 13.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.dayProgress, 5.0 / 7.0, accuracy: 0.001)
    }

    func testAggregatorCountsTodaysTogglSessionsAndRunningTime() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(component: "winmux-period-progress-\(UUID().uuidString)", directoryHint: .isDirectory)
        let periodDirectory = root.appending(component: "period", directoryHint: .isDirectory)
        let togglDirectory = root.appending(component: "toggl", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: periodDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: togglDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try writeToggl(
            togglDirectory.appending(component: "2026-06-26 08.00.md"),
            start: "2026-06-26T07:00:00Z",
        )
        try writeToggl(
            togglDirectory.appending(component: "2026-06-26 12.00.md"),
            start: "2026-06-26T11:37:00Z",
        )
        try writeToggl(
            togglDirectory.appending(component: "2026-06-25 12.00.md"),
            start: "2026-06-25T11:00:00Z",
        )

        let formatter = Self.utcFormatter()
        let snapshot = PeriodHeatmapAggregator(
            entriesDirectory: periodDirectory,
            togglDirectory: togglDirectory,
        ).load(now: formatter.date(from: "2026-06-26T12:00:00Z")!)

        assertEquals(snapshot.sessionCount, 2)
        XCTAssertEqual(snapshot.runningSeconds, 23 * 60, accuracy: 1)
        assertEquals(snapshot.runningHoursText, "0.4")
        assertEquals(snapshot.runningMinute, 23)
        assertEquals(snapshot.sessionProgress, 2.0 / 3.0)
        XCTAssertEqual(snapshot.timeProgress, (23.0 * 60.0) / (4.0 * 60.0 * 60.0), accuracy: 0.001)
        XCTAssertEqual(snapshot.minuteProgress, 23.0 / 60.0, accuracy: 0.001)
    }

    func testRingColorStepUsesFilledUnitEndpoints() {
        XCTAssertEqual(periodProgressColorStep(filledUnits: 0, totalUnits: 13), 0)
        XCTAssertEqual(periodProgressColorStep(filledUnits: 1, totalUnits: 13), 0)
        XCTAssertEqual(periodProgressColorStep(filledUnits: 7, totalUnits: 13), 0.5)
        XCTAssertEqual(periodProgressColorStep(filledUnits: 13, totalUnits: 13), 1)
    }

    private func writeToggl(_ url: URL, start: String) throws {
        try """
        ---
        start_at_utc: "\(start)"
        ---
        Focus
        """.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func localDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func utcFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}
