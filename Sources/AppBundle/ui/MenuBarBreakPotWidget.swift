import AppKit
import Foundation
import SwiftUI

private let menuBarBreakPotRefreshInterval: TimeInterval = 15 * 60
private let menuBarBreakPotTimelineStart = Date(timeIntervalSinceReferenceDate: 0)
private let menuBarFocusRecordURL = URL(filePath: "/Users/side/Documents/now/my_app/self/self_ob/Others/Focus record.md")

private enum MenuBarFocusType: String, CaseIterable {
    case quietNight = "宁静夜晚"
    case lateStartEarlyFinish = "晚起早退"
    case carefree = "不管不顾"
}

@MainActor
private final class MenuBarBreakPotModel: ObservableObject {
    static let shared = MenuBarBreakPotModel()

    @Published private(set) var anchorAt: Date
    private var nextRefreshAt = Date.distantPast

    private init() {
        anchorAt = MenuBarFocusRecord.nextStart() ?? Calendar.current.startOfDay(for: .now)
    }

    func refresh() {
        let now = Date()
        guard now >= nextRefreshAt else { return }
        nextRefreshAt = now.addingTimeInterval(menuBarBreakPotRefreshInterval)
        anchorAt = MenuBarFocusRecord.nextStart() ?? Calendar.current.startOfDay(for: now)
    }

    func record(_ type: MenuBarFocusType) throws {
        let now = Date()
        let start = MenuBarFocusRecord.nextStart() ?? Calendar.current.startOfDay(for: now)
        guard start <= now else { throw MenuBarFocusRecordError.alreadyRecordedToday }
        guard let focusHours = menuBarBreakPotLocalBalance(from: start, to: now) else {
            throw MenuBarFocusRecordError.focusHoursUnavailable
        }
        try MenuBarFocusRecord.append(date: now, focusHours: focusHours, type: type.rawValue)
        anchorAt = MenuBarFocusRecord.nextDay(after: now)
        nextRefreshAt = now.addingTimeInterval(menuBarBreakPotRefreshInterval)
    }
}

struct MenuBarBreakPotWidget: View {
    let height: CGFloat

    @StateObject private var model = MenuBarBreakPotModel.shared

    init(height: CGFloat = 24) {
        self.height = height
    }

    var body: some View {
        TimelineView(.periodic(from: menuBarBreakPotTimelineStart, by: menuBarBreakPotRefreshInterval)) { context in
            HStack(spacing: menuBarWidgetSpacing) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: menuBarWidgetIconSize, weight: menuBarWidgetFontWeight))
                    .frame(width: menuBarWidgetIconFrame, height: menuBarWidgetIconFrame)
                    .foregroundStyle(menuBarWidgetIcon)
                Text(displayText(at: context.date))
                    .font(.system(size: menuBarWidgetFontSize, weight: menuBarWidgetFontWeight))
                    .monospacedDigit()
            }
            .menuBarWidgetItem(height: height, chartKind: .breakPot)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibilityText(at: context.date)))
            .background(MenuBarChartHitRegion(kind: .breakPot))
            .task(id: context.date) { model.refresh() }
        }
    }

    private func displayText(at now: Date) -> String {
        let balance = menuBarBreakPotLocalBalance(from: model.anchorAt, to: now)
        return "\(roundedBalance(balance))h \(menuBarBreakPotElapsedText(anchorAt: model.anchorAt, now: now))"
    }

    private func accessibilityText(at now: Date) -> String {
        let balance = menuBarBreakPotLocalBalance(from: model.anchorAt, to: now)
        return "Focus since last record, \(roundedBalance(balance)) hours, \(menuBarBreakPotElapsedText(anchorAt: model.anchorAt, now: now))"
    }

    private func roundedBalance(_ balance: Double?) -> Int {
        max(0, Int((balance ?? 0).rounded()))
    }
}

@MainActor
final class MenuBarBreakPotMenu: NSObject {
    static let shared = MenuBarBreakPotMenu()

    func show(at frame: NSRect) {
        let anchor = NSPanelHud()
        anchor.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        anchor.setFrame(NSRect(x: frame.minX, y: frame.minY, width: 1, height: 1), display: false)
        anchor.level = .popUpMenu
        anchor.hasShadow = false
        anchor.ignoresMouseEvents = true
        anchor.orderFrontRegardless()
        defer { anchor.orderOut(nil) }

        let menu = NSMenu()
        for type in MenuBarFocusType.allCases {
            let item = NSMenuItem(title: type.rawValue, action: #selector(record(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = type.rawValue
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: .zero, in: anchor.contentView)
    }

    @objc private func record(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let type = MenuBarFocusType(rawValue: rawValue) else { return }
        do {
            try MenuBarBreakPotModel.shared.record(type)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not record focus"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}

enum MenuBarFocusRecord {
    static let header = "| Date | Focus | Type |\n| ---- | ----- | ---- |\n"

    static func nextStart(at url: URL = menuBarFocusRecordURL, calendar: Calendar = .current) -> Date? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8),
              let lastDate = lastDate(in: contents, calendar: calendar) else { return nil }
        return nextDay(after: lastDate, calendar: calendar)
    }

    static func nextDay(after date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: day) ?? day
    }

    static func lastDate(in contents: String, calendar: Calendar = .current) -> Date? {
        let formatter = dateFormatter(calendar: calendar)
        return contents.split(whereSeparator: \.isNewline).compactMap { line -> Date? in
            let cells = line.split(separator: "|", omittingEmptySubsequences: false)
            guard cells.count == 5 else { return nil }
            return formatter.date(from: cells[1].trimmingCharacters(in: .whitespaces))
        }.max()
    }

    static func append(
        date: Date,
        focusHours: Double,
        type: String,
        at url: URL = menuBarFocusRecordURL,
        calendar: Calendar = .current
    ) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var contents = fileManager.fileExists(atPath: url.path)
            ? try String(contentsOf: url, encoding: .utf8)
            : header
        guard contents.contains("| Date | Focus | Type |"),
              contents.contains("| ---- | ----- | ---- |") else {
            throw MenuBarFocusRecordError.invalidTable
        }
        contents = contents.replacingOccurrences(of: "|      |       |      |\n", with: "")
        if !contents.hasSuffix("\n") { contents += "\n" }
        let dateText = dateFormatter(calendar: calendar).string(from: date)
        let hoursText = String(format: "%.2f h", locale: Locale(identifier: "en_US_POSIX"), focusHours)
        contents += "| \(dateText) | \(hoursText) | \(type) |\n"
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func dateFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.isLenient = false
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

private func menuBarBreakPotLocalBalance(from start: Date, to now: Date) -> Double? {
    guard let sqliteURL = SidebarSelfDataStore.sqliteURL(
        for: URL(filePath: defaultWorkspaceSidebarDataPath, directoryHint: .isDirectory)
    ), let entries = SidebarSelfDataStore.loadTimeEntries(from: sqliteURL, now: now)
    else { return nil }

    return menuBarBreakPotFocusHours(entries: entries, from: start, to: now)
}

func menuBarBreakPotFocusHours(entries: [SidebarSelfDataTimeEntry], from start: Date, to now: Date) -> Double {
    let focusSeconds = entries.reduce(0.0) { total, entry in
        guard entry.projectName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "break" else {
            return total
        }
        let overlapStart = max(entry.start, start)
        let overlapEnd = min(entry.stop, now)
        return total + max(0, overlapEnd.timeIntervalSince(overlapStart))
    }
    return max(0, focusSeconds / 3600)
}

private func menuBarBreakPotElapsedText(anchorAt: Date, now: Date) -> String {
    let calendar = Calendar.current
    let anchorDay = calendar.startOfDay(for: anchorAt)
    let today = calendar.startOfDay(for: now)
    let days = max(0, calendar.dateComponents([.day], from: anchorDay, to: today).day ?? 0)
    return days == 0 ? "since today" : "since \(days)d ago"
}

private enum MenuBarFocusRecordError: LocalizedError {
    case focusHoursUnavailable
    case invalidTable
    case alreadyRecordedToday

    var errorDescription: String? {
        switch self {
            case .focusHoursUnavailable: "Could not calculate focus hours from local Toggl data."
            case .invalidTable: "Focus record.md does not contain the Date, Focus, Type table."
            case .alreadyRecordedToday: "Focus has already been recorded for today."
        }
    }
}
