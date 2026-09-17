import SwiftUI

extension WorkspaceSidebarPanel {
    func animateVisibleSidebarWidth(_ width: CGFloat, animation: Animation?) {
        let layout = currentSidebarPanelLayout()
        let normalizedWidth = layout?.frame.width ?? frame.width
        debugWorkspaceSidebarHoverLog("animateWidth ignoredInTopBarMode panel=\(monitorScopeId) requested=\(width) normalized=\(normalizedWidth) frame=\(frame)")
        withAnimation(animation) {
            viewModel.workspaceSidebarVisibleWidth = normalizedWidth
            viewModel.isWorkspaceSidebarExpanded = true
        }
        if let layout, frame != layout.frame {
            setFrame(layout.frame, display: true, animate: false)
        }
        updateMousePassthrough()
    }

    func expandSidebar(to expandedWidth: CGFloat, animated: Bool = true) {
        debugWorkspaceSidebarHoverLog("expandSidebar panel=\(monitorScopeId) target=\(expandedWidth) visible=\(viewModel.workspaceSidebarVisibleWidth) frame=\(frame) mouse=\(NSEvent.mouseLocation)")
        viewModel.setIfChanged(\.isWorkspaceSidebarExpanded, to: true)
        if !isVisible {
            refresh()
        }
        animateVisibleSidebarWidth(
            currentSidebarPanelLayout()?.frame.width ?? expandedWidth,
            animation: animated ? .easeInOut(duration: animationDuration) : nil,
        )
    }

}
