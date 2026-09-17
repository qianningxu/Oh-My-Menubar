import Foundation
import SwiftUI

private let menuBarBreakPotRefreshInterval: TimeInterval = 15 * 60
private let menuBarBreakPotTimelineStart = Date(timeIntervalSinceReferenceDate: 0)
private let menuBarBreakPotResetDirectory = URL(
    filePath: "/Users/side/Documents/now/my_app/self/self_ob/Reset/Break",
    directoryHint: .isDirectory,
)
private let menuBarBreakPotResetTemplate = URL(
    filePath: "/Users/side/Documents/now/my_app/self/self_ob/Others/Templates/break reset.md",
)

private enum MenuBarBreakPotSpendKind {
    case halfDay
    case fullDay

    var title: String {
        switch self {
            case .halfDay: "Half day · 25h"
            case .fullDay: "Full day · 50h"
        }
    }

    var recordValue: String {
        switch self {
            case .halfDay: "half"
            case .fullDay: "full"
        }
    }

}

@MainActor
private final class MenuBarBreakPotModel: ObservableObject {
    static let shared = MenuBarBreakPotModel()

    @Published private(set) var snapshot: MenuBarBreakPotState
    @Published private(set) var activeKind: MenuBarBreakPotSpendKind?
    @Published private(set) var statusText: String?
    private var nextRefreshAt = Date.distantPast
    private var isRefreshing = false

    private init() {
        snapshot = MenuBarBreakPotState.loadLatestReset() ?? .localFallback()
    }

    func refresh() async {
        let now = Date()
        guard activeKind == nil, !isRefreshing, now >= nextRefreshAt else { return }

        isRefreshing = true
        nextRefreshAt = now.addingTimeInterval(menuBarBreakPotRefreshInterval)
        defer { isRefreshing = false }
        snapshot = MenuBarBreakPotState.loadLatestReset() ?? .localFallback(now: now)
    }

    func spend(_ kind: MenuBarBreakPotSpendKind) async {
        guard activeKind == nil else { return }
        activeKind = kind
        statusText = nil
        do {
            let now = Date()
            guard let focusHours = menuBarBreakPotLocalBalance(snapshot: snapshot, now: now) else {
                throw MenuBarBreakPotResetError.focusHoursUnavailable
            }
            try MenuBarBreakPotResetRecord.create(
                kind: kind,
                periodStart: snapshot.anchorAt,
                finish: now,
                focusHours: focusHours,
            )
            snapshot = MenuBarBreakPotState(anchorAt: MenuBarBreakPotState.resetAnchor(after: now))
            statusText = "Recorded locally"
        } catch {
            statusText = error.localizedDescription
        }
        activeKind = nil
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
            .task(id: context.date) {
                await model.refresh()
            }
        }
    }

    private func displayText(at now: Date) -> String {
        let snapshot = model.snapshot
        let balance = menuBarBreakPotLocalBalance(snapshot: snapshot, now: now)
        return "\(roundedBalance(balance))h \(menuBarBreakPotElapsedText(anchorAt: snapshot.anchorAt, now: now))"
    }

    private func accessibilityText(at now: Date) -> String {
        let snapshot = model.snapshot
        let balance = menuBarBreakPotLocalBalance(snapshot: snapshot, now: now)
        return "Break Pot balance, \(roundedBalance(balance)) focused hours, \(menuBarBreakPotElapsedText(anchorAt: snapshot.anchorAt, now: now)), using local data"
    }

    private func roundedBalance(_ balance: Double?) -> Int {
        max(0, Int((balance ?? 0).rounded()))
    }
}

struct MenuBarBreakPotActionsView: View {
    @StateObject private var model = MenuBarBreakPotModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: standardGap * 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Break Pot")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(workspaceSidebarWidgetContent(.secondary))
                Spacer()
                Text(balanceText)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(workspaceSidebarWidgetContent(.primary))
            }

            HStack(spacing: standardGap * 4) {
                spendButton(.halfDay)
                spendButton(.fullDay)
            }

            if let statusText = model.statusText {
                Text(statusText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(workspaceSidebarWidgetContent(.secondary))
            } else {
                Text("Stored locally")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(workspaceSidebarWidgetContent(.secondary))
            }
        }
        .task { await model.refresh() }
    }

    private var balanceText: String {
        let balance = menuBarBreakPotLocalBalance(snapshot: model.snapshot, now: .now) ?? 0
        return "\(max(0, Int(balance.rounded())))h"
    }

    private func spendButton(_ kind: MenuBarBreakPotSpendKind) -> some View {
        Button {
            Task { await model.spend(kind) }
        } label: {
            HStack(spacing: standardGap * 3) {
                if model.activeKind == kind {
                    ProgressView().controlSize(.small)
                }
                Text(kind.title)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(MenuBarBreakPotButtonStyle())
        .disabled(model.activeKind != nil)
        .accessibilityLabel("Use Break Pot for a \(kind.title.lowercased())")
    }
}

private struct MenuBarBreakPotButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(workspaceSidebarWidgetContent(.primary))
            .padding(.horizontal, standardGap * 5)
            .frame(height: 34)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(workspaceSidebarWidgetComponentBackground(configuration.isPressed ? .active : .normal))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(workspaceSidebarWidgetBorder(configuration.isPressed ? .active : .normal), lineWidth: 0.75)
            }
    }
}

private struct MenuBarBreakPotState {
    let anchorAt: Date

    static func localFallback(now: Date = Date()) -> MenuBarBreakPotState {
        MenuBarBreakPotState(anchorAt: Calendar.current.startOfDay(for: now))
    }

    static func loadLatestReset() -> MenuBarBreakPotState? {
        guard let noteURLs = try? FileManager.default.contentsOfDirectory(
            at: menuBarBreakPotResetDirectory,
            includingPropertiesForKeys: nil,
        ) else {
            return nil
        }

        return noteURLs.compactMap { noteURL in
            guard noteURL.pathExtension == "md",
                  let contents = try? String(contentsOf: noteURL, encoding: .utf8),
                  let finishAt = menuBarBreakPotFinishDate(from: contents)
            else {
                return nil
            }
            return MenuBarBreakPotState(anchorAt: resetAnchor(after: finishAt))
        }.max { $0.anchorAt < $1.anchorAt }
    }

    static func resetAnchor(after finish: Date) -> Date {
        let calendar = Calendar.current
        let finishDay = calendar.startOfDay(for: finish)
        return calendar.date(byAdding: .day, value: 1, to: finishDay) ?? finishDay
    }
}

private enum MenuBarBreakPotResetRecord {
    static func create(
        kind: MenuBarBreakPotSpendKind,
        periodStart: Date,
        finish: Date,
        focusHours: Double,
    ) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: menuBarBreakPotResetDirectory, withIntermediateDirectories: true)

        let baseFileName = menuBarBreakPotNoteFileName(for: finish)
        var noteURL = menuBarBreakPotResetDirectory.appending(component: "\(baseFileName).md")
        var sequence = 2
        while fileManager.fileExists(atPath: noteURL.path) {
            noteURL = menuBarBreakPotResetDirectory.appending(
                component: "\(baseFileName)-\(sequence).md",
            )
            sequence += 1
        }

        let template = try String(contentsOf: menuBarBreakPotResetTemplate, encoding: .utf8)
        let frontmatter = """
        ---
        start: \(menuBarBreakPotDateString(periodStart))
        finish: \(menuBarBreakPotDateString(finish))
        focus_hour: \(String(format: "%.2f", focusHours))
        Break: \(kind.recordValue)
        ---
        """
        let contents = template
            .replacingOccurrences(
                of: "---\nstart:\nfinish:\nfocus_hour:\nBreak:\n---",
                with: frontmatter,
            )
            .replacingOccurrences(of: "\n<% tp.file.rename(tp.date.now(\"YYYY-MM-DD\")) %>\n", with: "\n")
        try contents.write(to: noteURL, atomically: true, encoding: .utf8)
    }
}

private func menuBarBreakPotLocalBalance(snapshot: MenuBarBreakPotState, now: Date) -> Double? {
    guard let sqliteURL = SidebarSelfDataStore.sqliteURL(
        for: URL(filePath: defaultWorkspaceSidebarDataPath, directoryHint: .isDirectory)
    ), let entries = SidebarSelfDataStore.loadTimeEntries(from: sqliteURL, now: now)
    else { return nil }

    let focusSeconds = entries.reduce(0.0) { total, entry in
        guard entry.projectName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "break" else {
            return total
        }
        let overlapStart = max(entry.start, snapshot.anchorAt)
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

private enum MenuBarBreakPotResetError: LocalizedError {
    case focusHoursUnavailable

    var errorDescription: String? {
        switch self {
            case .focusHoursUnavailable: "Could not calculate focus hours from local Toggl data."
        }
    }
}

func menuBarBreakPotFinishDate(from noteContents: String, timeZone: TimeZone = .current) -> Date? {
    let pattern = #"(?m)^finish:[ \t]*([^\r\n]+?)[ \t]*$"#
    guard let expression = try? NSRegularExpression(pattern: pattern),
          let match = expression.firstMatch(
              in: noteContents,
              range: NSRange(noteContents.startIndex..., in: noteContents),
          ),
          let range = Range(match.range(at: 1), in: noteContents)
    else {
        return nil
    }
    let value = String(noteContents[range])
    let fractionalSecondsFormatter = ISO8601DateFormatter()
    fractionalSecondsFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractionalSecondsFormatter.date(from: value) {
        return date
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: value) {
        return date
    }

    // Obsidian datetime properties may omit an offset; these are local wall times.
    let localFormatter = DateFormatter()
    localFormatter.locale = Locale(identifier: "en_US_POSIX")
    localFormatter.calendar = Calendar(identifier: .gregorian)
    localFormatter.timeZone = timeZone
    localFormatter.isLenient = false
    for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
        localFormatter.dateFormat = format
        if let date = localFormatter.date(from: value), localFormatter.string(from: date) == value {
            return date
        }
    }
    return nil
}

private func menuBarBreakPotDateString(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private func menuBarBreakPotNoteFileName(for date: Date) -> String {
    let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
}
