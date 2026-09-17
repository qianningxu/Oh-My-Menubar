import AppKit
import Common
import Foundation

private let workspaceSidebarPinnedExpandedPreferenceKey = "workspaceSidebar.pinnedExpanded"
private let workspaceSidebarAutoHidePreferenceKey = "workspaceSidebar.autoHide"
private let workspaceSidebarCollapsedFolderIdsPreferenceKey = "workspaceSidebar.collapsedFolderIds"
private let workspaceSidebarLegacyCollapsedTabGroupIdsPreferenceKey = "workspaceSidebar.collapsedTabGroupIds"
private let workspaceSidebarAppearancePreferenceKey = "workspaceSidebar.appearance"
let workspaceSidebarShowsNotePadPreferenceKey = "workspaceSidebar.showsNotePad"
let workspaceSidebarShowsTasksPreferenceKey = "workspaceSidebar.showsTasks"

func workspaceSidebarAppearancePreference(rawValue: String) -> AppearanceTheme? {
    switch rawValue {
        case "light": .light
        case "dark": .dark
        default: nil
    }
}

@MainActor
func restoreWorkspaceSidebarAppearancePreference() {
    WorkspaceSidebarAppearanceObserver.shared.startObserving()
    guard let rawValue = UserDefaults.standard.string(forKey: workspaceSidebarAppearancePreferenceKey),
          let theme = workspaceSidebarAppearancePreference(rawValue: rawValue)
    else { return }
    applyWorkspaceSidebarAppearance(theme, persist: false)
}

@MainActor
final class WorkspaceSidebarAppearanceObserver {
    static let shared = WorkspaceSidebarAppearanceObserver {
        WorkspaceSidebarPanel.refreshAll()
    }

    private var observation: NSKeyValueObservation?
    private let refresh: @MainActor () -> Void

    init(refresh: @escaping @MainActor () -> Void) {
        self.refresh = refresh
    }

    func startObserving() {
        guard observation == nil else { return }
        observation = NSApplication.shared.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            // Refresh after AppKit has propagated the new effective appearance,
            // including when an explicit override is cleared to follow the system.
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }
}

func currentWorkspaceSidebarAppearancePreference() -> AppearanceTheme? {
    workspaceSidebarAppearancePreference(
        rawValue: UserDefaults.standard.string(forKey: workspaceSidebarAppearancePreferenceKey) ?? ""
    )
}

@MainActor
func setWorkspaceSidebarAppearance(_ theme: AppearanceTheme?) {
    applyWorkspaceSidebarAppearance(theme, persist: true)
}

@MainActor
private func applyWorkspaceSidebarAppearance(_ theme: AppearanceTheme?, persist: Bool) {
    NSApplication.shared.appearance = theme.map { NSAppearance(named: $0 == .dark ? .darkAqua : .aqua) } ?? nil
    WorkspaceSidebarPanel.refreshAll()
    guard persist else { return }
    if let theme {
        UserDefaults.standard.setValue(theme == .dark ? "dark" : "light", forKey: workspaceSidebarAppearancePreferenceKey)
    } else {
        UserDefaults.standard.removeObject(forKey: workspaceSidebarAppearancePreferenceKey)
    }
}

func workspaceSidebarPinnedExpandedPreference() -> Bool {
    !workspaceSidebarAutoHidePreference()
}

@MainActor
func setWorkspaceSidebarPinnedExpandedPreference(_ isPinned: Bool) {
    setWorkspaceSidebarAutoHidePreference(!isPinned)
}

func workspaceSidebarAutoHidePreference() -> Bool {
    UserDefaults.standard.bool(forKey: workspaceSidebarAutoHidePreferenceKey)
}

@MainActor
func setWorkspaceSidebarAutoHidePreference(_ isEnabled: Bool) {
    UserDefaults.standard.setValue(isEnabled, forKey: workspaceSidebarAutoHidePreferenceKey)
    UserDefaults.standard.removeObject(forKey: workspaceSidebarPinnedExpandedPreferenceKey)
    TrayMenuModel.shared.isWorkspaceSidebarAutoHideEnabled = isEnabled
    TrayMenuModel.shared.isWorkspaceSidebarPinnedExpanded = !isEnabled
}

func collapsedWorkspaceSidebarFolderIdsPreference() -> Set<String> {
    let ids = UserDefaults.standard.stringArray(forKey: workspaceSidebarCollapsedFolderIdsPreferenceKey)
        ?? UserDefaults.standard.stringArray(forKey: workspaceSidebarLegacyCollapsedTabGroupIdsPreferenceKey)
        ?? []
    return Set(ids)
}

@MainActor
func resetWorkspaceSidebarUIPreferencesForTests() {
    UserDefaults.standard.removeObject(forKey: workspaceSidebarPinnedExpandedPreferenceKey)
    UserDefaults.standard.removeObject(forKey: workspaceSidebarAutoHidePreferenceKey)
    UserDefaults.standard.removeObject(forKey: workspaceSidebarCollapsedFolderIdsPreferenceKey)
    UserDefaults.standard.removeObject(forKey: workspaceSidebarLegacyCollapsedTabGroupIdsPreferenceKey)
    UserDefaults.standard.removeObject(forKey: workspaceSidebarAppearancePreferenceKey)
    UserDefaults.standard.removeObject(forKey: workspaceSidebarShowsNotePadPreferenceKey)
    UserDefaults.standard.removeObject(forKey: workspaceSidebarShowsTasksPreferenceKey)
    UserDefaults.standard.synchronize()
    TrayMenuModel.shared.isWorkspaceSidebarAutoHideEnabled = false
    TrayMenuModel.shared.isWorkspaceSidebarPinnedExpanded = true
}

@MainActor
func workspaceSidebarFolderIsExpanded(_ folderId: WorkspaceFolderId) -> Bool {
    !normalizedWorkspaceSidebarCollapsedFolderIds(
        collapsedIds: collapsedWorkspaceSidebarFolderIdsPreference()
    ).contains(folderId.rawValue)
}

@MainActor
func setWorkspaceSidebarFolderExpanded(_ folderId: WorkspaceFolderId, isExpanded: Bool) {
    var collapsedIds = normalizedWorkspaceSidebarCollapsedFolderIds(
        collapsedIds: collapsedWorkspaceSidebarFolderIdsPreference()
    )
    if isExpanded {
        collapsedIds.remove(folderId.rawValue)
    } else {
        collapsedIds.insert(folderId.rawValue)
    }
    persistWorkspaceSidebarCollapsedFolderIds(collapsedIds, updatesRestartSnapshot: true)
}

@MainActor
func restoreWorkspaceSidebarCollapsedFolderIds(_ folderIds: [WorkspaceFolderId]) {
    let collapsedIds = normalizedWorkspaceSidebarCollapsedFolderIds(
        collapsedIds: Set(folderIds.map(\.rawValue))
    )
    persistWorkspaceSidebarCollapsedFolderIds(collapsedIds, updatesRestartSnapshot: false)
}

@MainActor
@discardableResult
func normalizeWorkspaceSidebarFolderExpansionPreference() -> Bool {
    let collapsedIds = collapsedWorkspaceSidebarFolderIdsPreference()
    let normalizedIds = normalizedWorkspaceSidebarCollapsedFolderIds(
        collapsedIds: collapsedIds
    )
    guard normalizedIds != collapsedIds else { return false }
    persistWorkspaceSidebarCollapsedFolderIds(normalizedIds, updatesRestartSnapshot: true)
    return true
}

@MainActor
func clearWorkspaceSidebarFolderExpansionPreference(_ folderId: WorkspaceFolderId) {
    var collapsedIds = normalizedWorkspaceSidebarCollapsedFolderIds(
        collapsedIds: collapsedWorkspaceSidebarFolderIdsPreference()
    )
    guard collapsedIds.remove(folderId.rawValue) != nil else { return }
    UserDefaults.standard.setValue(collapsedIds.sorted(), forKey: workspaceSidebarCollapsedFolderIdsPreferenceKey)
    UserDefaults.standard.removeObject(forKey: workspaceSidebarLegacyCollapsedTabGroupIdsPreferenceKey)
}

@MainActor
private func normalizedWorkspaceSidebarCollapsedFolderIds(
    collapsedIds: Set<String>
) -> Set<String> {
    let folders = workspaceFolders()
    let knownFolderIds = Set(folders.map(\.id.rawValue))
    let unfoldedFolderIdByProjectId = Dictionary(
        uniqueKeysWithValues: workspaceProjects().map { ($0.id.rawValue, $0.unfoldedFolderId.rawValue) }
    )
    return Set(collapsedIds.compactMap { rawValue in
        if knownFolderIds.contains(rawValue) {
            return rawValue
        }
        return unfoldedFolderIdByProjectId[rawValue]
    })
}

@MainActor
private func persistWorkspaceSidebarCollapsedFolderIds(
    _ collapsedIds: Set<String>,
    updatesRestartSnapshot: Bool
) {
    UserDefaults.standard.setValue(collapsedIds.sorted(), forKey: workspaceSidebarCollapsedFolderIdsPreferenceKey)
    UserDefaults.standard.removeObject(forKey: workspaceSidebarLegacyCollapsedTabGroupIdsPreferenceKey)
    // Keep the durable sidebar snapshot in lockstep with the visible folded
    // state.  A fold change does not alter window placement, so avoid taking
    // the much larger full-world snapshot on this interaction path.
    if updatesRestartSnapshot, !isUnitTest {
        persistSidebarStateForRestartIfPossible()
    }
}
