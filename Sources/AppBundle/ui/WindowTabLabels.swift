import Common
import Foundation

@MainActor
private var sessionWindowTabLabels: [UInt32: String] = [:]
@MainActor
private var sessionWindowTabLabelKeys: [UInt32: String] = [:]

@MainActor
func resetWindowTabLabelsForTests() {
    sessionWindowTabLabels = [:]
    sessionWindowTabLabelKeys = [:]
}

@MainActor
func windowTabLabelForRestart(windowId: UInt32) -> String? {
    guard let label = sessionWindowTabLabels[windowId]?.trimmingCharacters(in: .whitespacesAndNewlines),
          !label.isEmpty
    else { return nil }
    return label
}

@MainActor
func restoreWindowTabLabelForRestart(windowId: UInt32, label: String?) {
    guard let label = label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty else { return }
    sessionWindowTabLabels[windowId] = label
}

@MainActor
func windowTabLabelKey(app: any AbstractApp, rawTitle: String) -> String {
    let appIdentity = app.rawAppBundleId?.takeIf { !$0.isEmpty }
        ?? app.bundlePath?.takeIf { !$0.isEmpty }
        ?? app.name?.takeIf { !$0.isEmpty }
        ?? "unknown-app"
    return "\(appIdentity)|\(rawTitle)"
}

/// A tab rename belongs to one native window, independent of its changing title.
/// Include the owning process so a later instance of the same app cannot inherit it.
@MainActor
func windowTabLabelKey(for window: Window) -> String {
    let appKey = windowTabLabelKey(app: window.app, rawTitle: "")
    return "window:\(window.app.pid):\(window.windowId)|\(appKey)"
}

@MainActor
func tabDisplayTitle(for window: Window) async -> String {
    let appName = window.app.name ?? window.app.rawAppBundleId ?? "Window"
    if let sessionLabel = sessionWindowTabLabels[window.windowId]?.trimmingCharacters(in: .whitespacesAndNewlines),
       !sessionLabel.isEmpty
    {
        return sessionLabel
    }
    let rawTitle = await getCachedWindowTitle(window) ?? appName
    let key = windowTabLabelKey(for: window)
    if let label = config.windowTabs.tabLabels[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
       !label.isEmpty
    {
        sessionWindowTabLabelKeys[window.windowId] = key
        return label
    }
    // Older configs keyed aliases by app + title. Only use those when the
    // title identifies one window; never apply an ambiguous alias to siblings.
    if let legacyKey = await unambiguousLegacyWindowTabLabelKey(for: window, rawTitle: rawTitle),
       let label = config.windowTabs.tabLabels[legacyKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
       !label.isEmpty
    {
        return label
    }
    return rawTitle
}

@MainActor
func renameWindowTab(windowId: UInt32, displayName: String) async throws {
    guard let window = Window.get(byId: windowId) else { return }
    let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
        try await resetWindowTabLabel(windowId: windowId)
        return
    }
    let key = windowTabLabelKey(for: window)
    config.windowTabs.tabLabels[key] = trimmedName
    sessionWindowTabLabelKeys[windowId] = key
    sessionWindowTabLabels[windowId] = trimmedName
    if !isUnitTest {
        try persistWindowTabLabel(key: key, label: trimmedName)
    }
}

@MainActor
func resetWindowTabLabel(windowId: UInt32) async throws {
    guard let window = Window.get(byId: windowId) else { return }
    let key: String
    if let sessionKey = sessionWindowTabLabelKeys[windowId] {
        key = sessionKey
    } else {
        key = windowTabLabelKey(for: window)
    }
    if let legacyKey = await unambiguousLegacyWindowTabLabelKey(for: window) {
        config.windowTabs.tabLabels.removeValue(forKey: legacyKey)
        if !isUnitTest { try persistWindowTabLabel(key: legacyKey, label: nil) }
    }
    config.windowTabs.tabLabels.removeValue(forKey: key)
    sessionWindowTabLabelKeys.removeValue(forKey: windowId)
    sessionWindowTabLabels.removeValue(forKey: windowId)
    if !isUnitTest {
        try persistWindowTabLabel(key: key, label: nil)
    }
}

@MainActor
private func unambiguousLegacyWindowTabLabelKey(for window: Window, rawTitle: String? = nil) async -> String? {
    let appName = window.app.name ?? window.app.rawAppBundleId ?? "Window"
    let title: String
    if let rawTitle { title = rawTitle } else { title = await getCachedWindowTitle(window) ?? appName }
    let key = windowTabLabelKey(app: window.app, rawTitle: title)
    guard config.windowTabs.tabLabels[key] != nil else { return nil }
    let windows: [Window] = isUnitTest
        ? Workspace.all.flatMap { $0.allLeafWindowsRecursive }
        : MacWindow.allWindowsMap.values.map { $0 as Window }
    for other in windows where other.windowId != window.windowId {
        let otherAppName = other.app.name ?? other.app.rawAppBundleId ?? "Window"
        let otherTitle = await getCachedWindowTitle(other) ?? otherAppName
        if windowTabLabelKey(app: other.app, rawTitle: otherTitle) == key { return nil }
    }
    return key
}
