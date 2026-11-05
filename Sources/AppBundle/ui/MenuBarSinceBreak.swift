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

    var body: some View {
        HStack(spacing: WinMuxSpacing.compact) {
            Text("Today  \(model.snapshot.today.map(durationText) ?? "—")")
            HStack(alignment: .bottom, spacing: WinMuxSpacing.hairline) {
                ForEach(model.snapshot.daily, id: \.day) { day in
                Capsule()
                    .fill(workspaceSidebarWidgetSemanticColor(MenuBarFocusCalendarBand.forHours(Double(day.seconds) / 3600).family, .color7))
                    .frame(width: WinMuxSpacing.compact, height: max(WinMuxSpacing.hairline, min(1, CGFloat(day.seconds) / 36000) * WinMuxSpacing.panel))
                    .help("\(day.day.formatted(date: .abbreviated, time: .omitted)): \(durationText(day.seconds))")
            }
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
