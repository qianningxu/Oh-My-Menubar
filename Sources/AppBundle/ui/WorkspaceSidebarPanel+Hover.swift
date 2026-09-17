import SwiftUI

extension WorkspaceSidebarPanel {
    func setHovering(_: Bool) {
        // The horizontal tab bar does not expand or collapse on hover.
        updateMousePassthrough()
    }

    func shouldLockExpansionForSidebarDrag() -> Bool {
        shouldLockWorkspaceSidebarExpansion(
            hasDropPreview: TrayMenuModel.shared.workspaceSidebarDropPreview != nil,
            hasPinnedDraggedWindow: hasPinnedDraggedWindow(),
            isSidebarDragInProgress: getCurrentMouseManipulationKind() == .move && getCurrentMouseDragStartedInSidebar(),
            hasActiveEditor: isMenuTrackingOrInGracePeriod() || shouldKeepSidebarOpenForInlineTextEditing(),
        ) || isMouseWindowDragInProgress() || Date() < workspaceActivityRevealUntil
    }

    func shouldKeepSidebarOpenForInlineTextEditing() -> Bool {
        commandExpansionLocksCollapse || optionKeyExpansionLocksCollapse ||
            (inlineTextEditingActive && inlineTextEditingLocksExpansion)
    }
}
