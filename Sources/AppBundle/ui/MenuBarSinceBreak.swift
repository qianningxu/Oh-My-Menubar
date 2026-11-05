import Foundation
import SwiftUI

struct MenuBarBreakEntry: Identifiable {
    let id: Int64
    let project: String?
    let title: String?
    let start: Date
    let seconds: Int
}

private func durationText(_ seconds: Int) -> String {
    let minutes = seconds / 60
    if seconds > 0 && minutes == 0 { return "\(seconds)s" }
    if minutes < 60 { return "\(minutes)m" }
    return "\(minutes / 60)h \(minutes % 60)m"
}

private struct BreakSnapshot {
    var daily: [(day: Date, seconds: Int)] = []
    var today: Int? = nil
}

@MainActor
private final class SinceBreakModel: ObservableObject {
    static let shared = SinceBreakModel()
    @Published var snapshot = BreakSnapshot()

    func refresh(overrides: String) async {
        let updated = await Task.detached(priority: .utility) {
            let now = Date.now
            let day = MenuBarFocusRecord.latestBreak(overridesJSON: overrides, now: now)
            let root = URL(filePath: defaultWorkspaceSidebarDataPath)
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: now)
            let firstDay = day.map { MenuBarFocusRecord.nextDay(after: $0, calendar: calendar) }
            guard let database = SidebarSelfDataStore.sqliteURL(for: root),
                  let entries = SidebarSelfDataStore.focusEntries(since: min(firstDay ?? today, today), through: now, from: database)
            else { return BreakSnapshot() }
            func seconds(on day: Date) -> Int {
                let end = MenuBarFocusRecord.nextDay(after: day, calendar: calendar)
                return entries.reduce(0) { sum, entry in
                    let stop = entry.start.addingTimeInterval(Double(entry.seconds))
                    return sum + max(0, Int(min(end, stop).timeIntervalSince(max(day, entry.start))))
                }
            }
            var days: [(day: Date, seconds: Int)] = []
            if var cursor = firstDay {
                while cursor <= today {
                    days.append((cursor, seconds(on: cursor)))
                    cursor = MenuBarFocusRecord.nextDay(after: cursor, calendar: calendar)
                }
            }
            return BreakSnapshot(daily: days, today: seconds(on: today))
        }.value
        if !Task.isCancelled { snapshot = updated }
    }
}

struct MenuBarSinceBreakView: View {
    let height: CGFloat
    @ObservedObject private var model = SinceBreakModel.shared
    @AppStorage("menuBarFocusCalendarRestDayOverrides") private var overrides = "{}"

    private func wholeHours(_ seconds: Int) -> String {
        "\(Int((Double(seconds) / 3600).rounded()))h"
    }

    private var dailyStrip: some View {
        HStack(spacing: WinMuxSpacing.section) {
            ForEach(model.snapshot.daily, id: \.day) { day in
                let hours = Double(day.seconds) / 3600
                let color = workspaceSidebarWidgetSemanticColor(MenuBarFocusCalendarBand.forHours(hours).family, .color7)
                VStack(spacing: WinMuxSpacing.hairline) {
                    HStack(spacing: WinMuxSpacing.compact) {
                        Text(day.day.formatted(.dateTime.weekday(.abbreviated)))
                            .foregroundStyle(workspaceSidebarWidgetContent(.secondary))
                        Text(wholeHours(day.seconds)).fontWeight(.semibold)
                    }
                    .font(.system(size: menuBarWidgetFontSize * 0.86))
                    Capsule()
                        .fill(workspaceSidebarWidgetSemanticColor(.gray, .color4))
                        .overlay(alignment: .leading) {
                            GeometryReader { geometry in
                                Capsule().fill(color)
                                    .frame(width: max(WinMuxSpacing.hairline, geometry.size.width * min(1, hours / 10)))
                            }
                        }
                        .frame(height: WinMuxSpacing.compact)
                }
                .frame(width: WinMuxSpacing.page * 2.5)
                .id(day.day)
                .help("\(day.day.formatted(date: .abbreviated, time: .omitted)): \(durationText(day.seconds))")
            }
        }
    }

    var body: some View {
        HStack(spacing: WinMuxSpacing.panel) {
            HStack(spacing: WinMuxSpacing.comfortable) {
                Text("Today")
                Text(model.snapshot.today.map(wholeHours) ?? "—").bold()
            }
            if model.snapshot.daily.count > 7 {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) { dailyStrip }
                        .frame(width: WinMuxSpacing.page * 2.5 * 7 + WinMuxSpacing.section * 6)
                        .task(id: model.snapshot.daily.last?.day) {
                            if let last = model.snapshot.daily.last { proxy.scrollTo(last.day, anchor: .trailing) }
                        }
                }
            } else {
                dailyStrip
            }
        }
            .font(.system(size: menuBarWidgetFontSize, weight: menuBarWidgetFontWeight))
            .monospacedDigit()
            .menuBarWidgetItem(height: height, chartKind: .focusRuns)
            .background(MenuBarChartHitRegion(kind: .focusRuns))
            .task(id: overrides) {
                while !Task.isCancelled {
                    await model.refresh(overrides: overrides)
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                }
            }
    }
}
