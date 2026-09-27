import Foundation
import SwiftUI

enum MenuBarFocusPeriod: String, CaseIterable, Identifiable {
    case day
    case week
    case month

    var id: Self { self }

    var displayLabel: String {
        switch self {
            case .day: "Daily"
            case .week: "Weekly"
            case .month: "Monthly"
        }
    }

    var title: String {
        switch self {
            case .day: "Today"
            case .week: "This week"
            case .month: "This month"
        }
    }

    var targetHours: Double {
        switch self {
            case .day: 10
            case .week: 60
            case .month: 240
        }
    }

    var timeDescription: String {
        switch self {
            case .day: "7:30 AM to 9 PM"
            case .week: "Monday to Friday"
            case .month: "first to last day of the month"
        }
    }

    func focusedSeconds(in snapshot: TodayFocusSnapshot) -> TimeInterval {
        switch self {
            case .day: snapshot.focusedSeconds
            case .week: snapshot.weekFocusedSeconds
            case .month: snapshot.monthFocusedSeconds
        }
    }
}

func menuBarFocusTimeProgress(
    for period: MenuBarFocusPeriod,
    now: Date,
    calendar: Calendar
) -> Double {
    let interval: DateInterval?
    switch period {
        case .day:
            guard let start = calendar.date(bySettingHour: 7, minute: 30, second: 0, of: now),
                  let end = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: now)
            else { return 0 }
            interval = DateInterval(start: start, end: end)
        case .week:
            guard let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
                  let end = calendar.date(byAdding: .day, value: 5, to: start)
            else { return 0 }
            interval = DateInterval(start: start, end: end)
        case .month:
            interval = calendar.dateInterval(of: .month, for: now)
    }
    guard let interval, interval.duration > 0 else { return 0 }
    return min(1, max(0, now.timeIntervalSince(interval.start) / interval.duration))
}

struct MenuBarFocusProgressContent: View {
    let snapshot: TodayFocusSnapshot?
    let now: Date
    let height: CGFloat

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }

    var body: some View {
        HStack(spacing: menuBarWidgetSpacing) {
            Image(systemName: "dot.scope")
                .font(.system(size: menuBarWidgetIconSize, weight: .medium))
                .frame(width: menuBarWidgetIconFrame, height: menuBarWidgetIconFrame)
                .foregroundStyle(menuBarWidgetIcon)

            HStack(spacing: WinMuxSpacing.section) {
                ForEach(MenuBarFocusPeriod.allCases) { period in
                    MenuBarFocusPeriodProgress(
                        period: period,
                        focusedSeconds: snapshot?.errorMessage == nil ? snapshot.map { period.focusedSeconds(in: $0) } : nil,
                        timeProgress: menuBarFocusTimeProgress(for: period, now: now, calendar: calendar)
                    )
                }
            }
        }
        .menuBarWidgetItem(height: height)
        .accessibilityElement(children: .contain)
    }
}

private struct MenuBarFocusPeriodProgress: View {
    let period: MenuBarFocusPeriod
    let focusedSeconds: TimeInterval?
    let timeProgress: Double

    private var focusProgress: Double {
        guard let focusedSeconds else { return 0 }
        return min(1, max(0, focusedSeconds / (period.targetHours * 3600)))
    }

    private var focusHoursText: String {
        guard let focusedSeconds else { return "—" }
        return "\(max(0, Int(focusedSeconds / 3600)))h"
    }

    private var detail: String {
        "\(period.title): \(focusHoursText) of \(Int(period.targetHours))h focus; "
            + "\(Int((timeProgress * 100).rounded()))% of \(period.timeDescription) elapsed"
    }

    var body: some View {
        HStack(spacing: WinMuxSpacing.compact) {
            Text(period.displayLabel)
                .font(.system(size: menuBarWidgetFontSize, weight: menuBarWidgetFontWeight))
                .lineLimit(1)

            VStack(spacing: standardGap * 0.5) {
                MenuBarFocusProgressBar(progress: focusProgress, opacity: 1)
                MenuBarFocusProgressBar(progress: timeProgress, opacity: 0.55)
            }

            Text(focusHoursText)
                .font(.system(size: menuBarWidgetFontSize, weight: menuBarWidgetFontWeight))
                .monospacedDigit()
                .lineLimit(1)
        }
        .help(detail)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(detail))
    }
}

private struct MenuBarFocusProgressBar: View {
    let progress: Double
    let opacity: Double

    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(menuBarWidgetText.opacity(0.18))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(menuBarWidgetText.opacity(opacity))
                        .frame(width: geometry.size.width * min(1, max(0, progress)))
                }
        }
        .frame(width: standardGap * 8, height: standardGap)
        .accessibilityHidden(true)
    }
}
