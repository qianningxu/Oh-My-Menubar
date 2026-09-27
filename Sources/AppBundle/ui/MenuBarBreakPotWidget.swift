import AppKit
import Foundation
import SwiftUI

private let menuBarBreakPotRefreshInterval: TimeInterval = 15 * 60
private let menuBarBreakPotTimelineStart = Date(timeIntervalSinceReferenceDate: 0)
private let menuBarFocusRecordURL = URL(filePath: "/Users/side/Documents/now/my_app/self/self_ob/Others/Focus record.md")
private let menuBarTogglConfigURL = URL(filePath: "/Users/side/Documents/now/my_app/self/self_data/service/src/toggl/import-entries/data.json")

private enum MenuBarFocusType: String, CaseIterable {
    case quietNight = "宁静夜晚"
    case lateStartEarlyFinish = "晚起早退"
    case carefree = "不管不顾"
}

private struct MenuBarLotusIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 8, y: 10))
        path.addCurve(to: CGPoint(x: 8, y: 2), control1: CGPoint(x: 5.5, y: 8), control2: CGPoint(x: 6, y: 4.5))
        path.addCurve(to: CGPoint(x: 8, y: 10), control1: CGPoint(x: 10, y: 4.5), control2: CGPoint(x: 10.5, y: 8))

        path.move(to: CGPoint(x: 6.6, y: 10.6))
        path.addCurve(to: CGPoint(x: 1.8, y: 5.7), control1: CGPoint(x: 3.3, y: 10.3), control2: CGPoint(x: 2.3, y: 8.4))
        path.addCurve(to: CGPoint(x: 5.8, y: 8), control1: CGPoint(x: 3.7, y: 6), control2: CGPoint(x: 5, y: 6.8))

        path.move(to: CGPoint(x: 9.4, y: 10.6))
        path.addCurve(to: CGPoint(x: 14.2, y: 5.7), control1: CGPoint(x: 12.7, y: 10.3), control2: CGPoint(x: 13.7, y: 8.4))
        path.addCurve(to: CGPoint(x: 10.2, y: 8), control1: CGPoint(x: 12.3, y: 6), control2: CGPoint(x: 11, y: 6.8))

        path.move(to: CGPoint(x: 2, y: 12))
        path.addCurve(to: CGPoint(x: 14, y: 12), control1: CGPoint(x: 5, y: 14.7), control2: CGPoint(x: 11, y: 14.7))
        return path.applying(CGAffineTransform(scaleX: rect.width / 16, y: rect.height / 16)
            .translatedBy(x: rect.minX, y: rect.minY))
    }
}

@MainActor
private final class MenuBarBreakPotModel: ObservableObject {
    static let shared = MenuBarBreakPotModel()

    @Published private(set) var anchorAt: Date
    private var nextRefreshAt = Date.distantPast
    private var isRecording = false

    private init() {
        anchorAt = MenuBarFocusRecord.nextStart() ?? Calendar.current.startOfDay(for: .now)
    }

    func refresh() {
        let now = Date()
        guard now >= nextRefreshAt else { return }
        nextRefreshAt = now.addingTimeInterval(menuBarBreakPotRefreshInterval)
        anchorAt = MenuBarFocusRecord.nextStart() ?? Calendar.current.startOfDay(for: now)
    }

    func record(_ type: MenuBarFocusType) async throws {
        guard !isRecording else { return }
        isRecording = true
        defer { isRecording = false }
        let now = Date()
        let start = MenuBarFocusRecord.nextStart() ?? Calendar.current.startOfDay(for: now)
        guard start <= now else { throw MenuBarFocusRecordError.alreadyRecordedToday }
        let focusHours = try await MenuBarTogglFocusSource.hours(from: start, to: now)
        let currentStart = MenuBarFocusRecord.nextStart() ?? Calendar.current.startOfDay(for: now)
        guard currentStart == start else { throw MenuBarFocusRecordError.recordChanged }
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
                MenuBarLotusIcon()
                    .stroke(menuBarWidgetIcon, style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round))
                    .frame(width: menuBarWidgetIconFrame, height: menuBarWidgetIconFrame)
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
        Task { @MainActor in
            do {
                try await MenuBarBreakPotModel.shared.record(type)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Could not record focus"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
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
        let lines = contents.components(separatedBy: .newlines)
        guard let headerIndex = tableHeaderIndex(in: lines) else { return nil }
        return tableRows(in: lines, after: headerIndex).compactMap { row in
            date(from: row[0], calendar: calendar)
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
        var lines = contents.components(separatedBy: .newlines)
        guard let headerIndex = tableHeaderIndex(in: lines) else {
            throw MenuBarFocusRecordError.invalidTable
        }
        let dateText = dateFormatter(calendar: calendar).string(from: date)
        let hoursText = String(format: "%.2f h", locale: Locale(identifier: "en_US_POSIX"), focusHours)
        let firstRow = headerIndex + 2
        var endRow = firstRow
        while endRow < lines.count, tableCells(in: lines[endRow])?.count == 3 {
            endRow += 1
        }
        let existingRows = lines[firstRow..<endRow].filter {
            tableCells(in: $0) != ["", "", ""]
        }
        lines.replaceSubrange(firstRow..<endRow, with: existingRows + ["| \(dateText) | \(hoursText) | \(type) |"])
        contents = lines.joined(separator: "\n")
        if !contents.hasSuffix("\n") { contents += "\n" }
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func tableHeaderIndex(in lines: [String]) -> Int? {
        lines.indices.first { index in
            guard index + 1 < lines.count,
                  tableCells(in: lines[index]) == ["Date", "Focus", "Type"],
                  let separator = tableCells(in: lines[index + 1]),
                  separator.count == 3 else { return false }
            return separator.allSatisfy { cell in
                cell.count >= 3 && cell.allSatisfy { $0 == "-" || $0 == ":" }
            }
        }
    }

    private static func tableRows(in lines: [String], after headerIndex: Int) -> [[String]] {
        var rows: [[String]] = []
        for line in lines.dropFirst(headerIndex + 2) {
            guard let cells = tableCells(in: line), cells.count == 3 else { break }
            rows.append(cells)
        }
        return rows
    }

    private static func tableCells(in line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.first == "|", trimmed.last == "|" else { return nil }
        return trimmed.dropFirst().dropLast().split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func date(from text: String, calendar: Calendar) -> Date? {
        let parts = text.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
        else { return nil }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        return actual.year == year && actual.month == month && actual.day == day ? date : nil
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

@MainActor
private enum MenuBarTogglFocusSource {
    static func hours(from start: Date, to finish: Date) async throws -> Double {
        guard let configData = try? Data(contentsOf: menuBarTogglConfigURL),
              let config = try? JSONSerialization.jsonObject(with: configData) as? [String: Any],
              let token = config["apiToken"] as? String,
              !token.isEmpty else { throw MenuBarFocusRecordError.togglCredentialsUnavailable }

        var components = URLComponents(string: "https://api.track.toggl.com/api/v9/me/time_entries")!
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        components.queryItems = [
            URLQueryItem(name: "start_date", value: formatter.string(from: start.addingTimeInterval(-86_400))),
            URLQueryItem(name: "end_date", value: formatter.string(from: finish)),
        ]
        guard let url = components.url,
              let entries = try await fetchJSON(url, token: token) as? [[String: Any]]
        else { throw MenuBarFocusRecordError.togglUnavailable }

        let projectIDs = Set(entries.compactMap { ($0["pid"] ?? $0["project_id"]) as? Int })
        var projectNames: [Int: String] = [:]
        if !projectIDs.isEmpty {
            let workspacesURL = URL(string: "https://api.track.toggl.com/api/v9/me/workspaces")!
            guard let workspaces = try await fetchJSON(workspacesURL, token: token) as? [[String: Any]]
            else { throw MenuBarFocusRecordError.togglUnavailable }
            for workspace in workspaces {
                guard let workspaceID = workspace["id"] as? Int,
                      let projectsURL = URL(string: "https://api.track.toggl.com/api/v9/workspaces/\(workspaceID)/projects?active=both"),
                      let projects = try await fetchJSON(projectsURL, token: token) as? [[String: Any]]
                else { throw MenuBarFocusRecordError.togglUnavailable }
                for project in projects {
                    if let id = project["id"] as? Int, let name = project["name"] as? String {
                        projectNames[id] = name
                    }
                }
            }
        }
        guard projectIDs.allSatisfy({ projectNames[$0] != nil }) else {
            throw MenuBarFocusRecordError.unknownTogglProject
        }

        let timeEntries = try entries.compactMap { entry -> SidebarSelfDataTimeEntry? in
            guard let rawStart = entry["start"] as? String,
                  let entryStart = parseDate(rawStart) else { throw MenuBarFocusRecordError.togglUnavailable }
            let entryStop: Date
            if let rawStop = entry["stop"] as? String {
                guard let parsedStop = parseDate(rawStop) else { throw MenuBarFocusRecordError.togglUnavailable }
                entryStop = parsedStop
            } else {
                entryStop = finish
            }
            guard entryStop > entryStart else { return nil }
            let projectID = (entry["pid"] ?? entry["project_id"]) as? Int
            return SidebarSelfDataTimeEntry(
                start: entryStart,
                stop: entryStop,
                projectID: projectID.map(Int64.init),
                projectName: projectID.flatMap { projectNames[$0] }
            )
        }
        return menuBarBreakPotFocusHours(entries: timeEntries, from: start, to: finish)
    }

    private static func fetchJSON(_ url: URL, token: String) async throws -> Any {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let authorization = Data("\(token):api_token".utf8).base64EncodedString()
        request.setValue("Basic \(authorization)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MenuBarFocusRecordError.togglUnavailable
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    private static func parseDate(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
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
    case invalidTable
    case alreadyRecordedToday
    case recordChanged
    case togglCredentialsUnavailable
    case togglUnavailable
    case unknownTogglProject

    var errorDescription: String? {
        switch self {
            case .invalidTable: "Focus record.md does not contain the Date, Focus, Type table."
            case .alreadyRecordedToday: "Focus has already been recorded for today."
            case .recordChanged: "Focus record.md changed while loading Toggl data. Try again."
            case .togglCredentialsUnavailable: "Could not read the local Toggl API token."
            case .togglUnavailable: "Could not load current focus entries from Toggl. Try again when Toggl is available."
            case .unknownTogglProject: "A Toggl project could not be identified, so focus was not recorded."
        }
    }
}
