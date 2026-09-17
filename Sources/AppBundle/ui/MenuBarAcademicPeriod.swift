import Foundation

/// Y4S1 starts with orientation week 0 on 7 September 2026.
struct MenuBarAcademicPeriod {
    let currentWeek: Int
    let weekday: String
    let totalWeeks = 12
    let elapsedDays: Int
    let totalDays: Int

    init(now: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7))!
        let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: now)).day ?? 0
        let end = calendar.date(from: DateComponents(year: 2026, month: 12, day: 6))!
        totalDays = calendar.dateComponents([.day], from: start, to: end).day ?? 90
        elapsedDays = min(max(days, 0), totalDays)
        currentWeek = min(max(days / 7, 0), 12)
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.calendar = calendar
        weekdayFormatter.locale = Locale(identifier: "en_GB")
        weekdayFormatter.timeZone = calendar.timeZone
        weekdayFormatter.dateFormat = "EEE"
        weekday = weekdayFormatter.string(from: now)
    }

    var specialWeek: String? {
        switch currentWeek {
            case 6: "Reading Week"
            case 11: "Revision Week"
            default: nil
        }
    }

    var title: String {
        let progress = "Y4S1 - \(weekday) - \(currentWeek)/\(totalWeeks)W - \(elapsedDays)/\(totalDays)d"
        return specialWeek.map { "\(progress) - \($0)" } ?? progress
    }

    var accessibilityLabel: String {
        let progress = "Y4S1, \(weekday), week \(currentWeek) of \(totalWeeks), \(elapsedDays) of \(totalDays) days elapsed"
        return specialWeek.map { "\(progress), \($0)" } ?? progress
    }
}
