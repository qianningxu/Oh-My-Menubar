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
    let lastBreak: Date?
    let entries: [MenuBarBreakEntry]?
    var daily: [(day: Date, seconds: Int)] = []
    var today: Int? = nil
    var total: String { entries.map { durationText($0.reduce(0) { $0 + $1.seconds }) } ?? "—" }
}

@MainActor
private final class SinceBreakModel: ObservableObject {
    static let shared = SinceBreakModel()
    @Published var snapshot = BreakSnapshot(lastBreak: nil, entries: nil)

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
            else { return BreakSnapshot(lastBreak: day, entries: nil) }
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
            return BreakSnapshot(lastBreak: day, entries: firstDay.map { start in entries.filter { $0.start >= start } },
                                 daily: days, today: seconds(on: today))
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
            ForEach(model.snapshot.daily, id: \.day) { day in
                Circle()
                    .fill(workspaceSidebarWidgetSemanticColor(MenuBarFocusCalendarBand.forHours(Double(day.seconds) / 3600).family, .color9))
                    .frame(width: WinMuxSpacing.regular, height: WinMuxSpacing.regular)
                    .help("\(day.day.formatted(date: .abbreviated, time: .omitted)): \(durationText(day.seconds))")
            }
            Text("Today - \(model.snapshot.today.map(durationText) ?? "—")")
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

struct MenuBarSinceBreakPopover: View {
    @ObservedObject private var model = SinceBreakModel.shared
    @State private var calendarVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: WinMuxSpacing.regular) {
            Picker("Focus view", selection: $calendarVisible) {
                Text("Entries").tag(false)
                Text("Calendar").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if calendarVisible {
                ScrollView { MenuBarFocusCalendar() }
            } else if let day = model.snapshot.lastBreak, let entries = model.snapshot.entries {
                HStack {
                    Text("After \(day.formatted(date: .abbreviated, time: .omitted))")
                    Spacer()
                    Text(model.snapshot.total).bold()
                }
                if entries.isEmpty { Text("No entries since this break.") }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: WinMuxSpacing.regular) {
                        ForEach(entries) { entry in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading) {
                                    Text(entry.title.flatMap { $0.isEmpty ? nil : $0 } ?? entry.project ?? "Untitled entry")
                                    let when = entry.start.formatted(.dateTime.day().month(.abbreviated).hour().minute())
                                    Text([when, entry.title?.isEmpty == false ? entry.project : nil].compactMap { $0 }.joined(separator: " · "))
                                        .foregroundStyle(workspaceSidebarWidgetContent(.secondary))
                                }
                                Spacer()
                                Text(durationText(entry.seconds)).monospacedDigit()
                            }
                        }
                    }
                }
            } else {
                Text(model.snapshot.lastBreak == nil ? "No break day recorded." : "Time entries unavailable.")
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: menuBarWidgetFontSize))
    }
}
