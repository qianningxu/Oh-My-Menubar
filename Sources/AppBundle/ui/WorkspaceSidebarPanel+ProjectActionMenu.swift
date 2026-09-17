import AppKit

extension WorkspaceSidebarPanel {
    func setProjectActionMenuPresentation(isPresented: Bool) {
        let extraWidth = isPresented ? workspaceSidebarProjectActionMenuWidth + workspaceSidebarStandardGap : 0
        guard projectActionMenuPresentationExtraWidth != extraWidth else {
            updateProjectPresentationLayout()
            return
        }
        projectActionMenuPresentationExtraWidth = extraWidth
        updateProjectPresentationLayout()
    }

    func setProjectMenuPresentation(isPresented: Bool, extraHeight: CGFloat) {
        let resolvedHeight = isPresented ? max(extraHeight, 0) : 0
        guard projectMenuPresentationExtraHeight != resolvedHeight else {
            updateProjectPresentationLayout()
            return
        }
        projectMenuPresentationExtraHeight = resolvedHeight
        updateProjectPresentationLayout()
    }

    func updateProjectPresentationLayout() {
        let hasPresentation = projectActionMenuPresentationExtraWidth > 0 || projectMenuPresentationExtraHeight > 0
        updateProjectPresentationLayer()
        if let layout = currentSidebarPanelLayout(), frame != layout.frame {
            setFrame(layout.frame, display: true, animate: false)
        }
        if hasPresentation {
            orderFrontRegardless()
        }
        updateMousePassthrough()
    }
}
