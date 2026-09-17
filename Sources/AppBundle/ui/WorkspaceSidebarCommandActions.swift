import Foundation
import AppKit

let workspaceSidebarOptionKeyRevealDelay: TimeInterval = 0.15

@MainActor
func openWorkspaceSidebarFromCommand() {
    guard TrayMenuModel.shared.isEnabled, config.workspaceSidebar.enabled else { return }
    WorkspaceSidebarPanel.refreshAll()
    let focusedScopeId = TrayMenuModel.shared.workspaceSidebarFocusedMonitorScopeId
    let panel = WorkspaceSidebarPanel.panel(for: focusedScopeId)
        ?? WorkspaceSidebarPanel.visiblePanels.first
        ?? WorkspaceSidebarPanel.allPanels.first
        ?? WorkspaceSidebarPanel.shared
    if panel.viewModel.isWorkspaceSidebarAutoHideEnabled {
        panel.revealProjectBarFromCommand()
        installWorkspaceSidebarCommandMouseUnlockMonitor(panel)
    } else {
        panel.expandSidebar(to: panel.frame.width, animated: false)
    }
}

@MainActor
func closeWorkspaceSidebarFromCommand(_ panel: WorkspaceSidebarPanel) {
    panel.releaseCommandProjectBarReveal()
}

@MainActor
func revealWorkspaceSidebarForWorkspaceActivity(on monitor: Monitor) {
    guard TrayMenuModel.shared.isEnabled,
          config.workspaceSidebar.enabled,
          workspaceSidebarAutoHidePreference()
    else { return }
    WorkspaceSidebarPanel.refreshAll()
    WorkspaceSidebarPanel
        .panel(for: workspaceSidebarMonitorScopeId(for: monitor))?
        .revealProjectBarForWorkspaceActivity()
}

@MainActor
func revealWorkspaceSidebarFromOptionKey() {
    guard TrayMenuModel.shared.isEnabled,
          config.workspaceSidebar.enabled,
          workspaceSidebarAutoHidePreference()
    else { return }
    WorkspaceSidebarPanel.refreshAll()
    let focusedScopeId = TrayMenuModel.shared.workspaceSidebarFocusedMonitorScopeId
    let panel = WorkspaceSidebarPanel.panel(for: focusedScopeId)
        ?? WorkspaceSidebarPanel.visiblePanels.first
        ?? WorkspaceSidebarPanel.allPanels.first
        ?? WorkspaceSidebarPanel.shared
    panel.revealProjectBarFromOptionKey()
}

@MainActor
func releaseWorkspaceSidebarOptionKeyReveal() {
    for panel in WorkspaceSidebarPanel.allPanels {
        panel.releaseOptionKeyProjectBarReveal()
    }
}

@MainActor
private func installWorkspaceSidebarCommandMouseUnlockMonitor(_ panel: WorkspaceSidebarPanel) {
    removeWorkspaceSidebarCommandMouseUnlockMonitor(panel)
    panel.commandMouseUnlockPoint = mouseLocation
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak panel] in
        guard let panel, panel.commandExpansionLocksCollapse else { return }
        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak panel] event in
            Task { @MainActor in
                panel?.unlockCommandSidebarExpansionIfMouseMoved()
            }
            return event
        }
        let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak panel] _ in
            Task { @MainActor in
                panel?.unlockCommandSidebarExpansionIfMouseMoved()
            }
        }
        panel.commandMouseUnlockMonitors = [localMonitor, globalMonitor].compactMap { $0 }
    }
}

@MainActor
private func removeWorkspaceSidebarCommandMouseUnlockMonitor(_ panel: WorkspaceSidebarPanel) {
    panel.removeCommandMouseUnlockMonitors()
}

private let workspaceSidebarCommandMouseUnlockDistance: CGFloat = 1

extension WorkspaceSidebarPanel {
    @MainActor
    func unlockCommandSidebarExpansionIfMouseMoved() {
        guard commandExpansionLocksCollapse,
              let origin = commandMouseUnlockPoint
        else { return }
        let current = mouseLocation
        guard hypot(current.x - origin.x, current.y - origin.y) > workspaceSidebarCommandMouseUnlockDistance else { return }
        commandExpansionLocksCollapse = false
        shouldLockNextSidebarSearchExpansion = false
        inlineTextEditingLocksExpansion = false
        removeWorkspaceSidebarCommandMouseUnlockMonitor(self)
        updateHoverStateFromMousePosition()
    }
}
