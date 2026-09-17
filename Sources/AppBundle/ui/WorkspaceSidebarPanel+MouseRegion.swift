import AppKit

extension WorkspaceSidebarPanel {
    func updateMousePassthrough() {
        // The panel frame hugs the visible bar, so every point is interactive.
        ignoresMouseEvents = false
    }

    func isMouseInsideHoverRegion() -> Bool {
        isVisible && visualSidebarFrame().contains(NSEvent.mouseLocation)
    }

    func isMouseInsideInteractiveRegion() -> Bool {
        guard isVisible else { return false }
        return isPointInsideInteractiveRegion(NSEvent.mouseLocation)
    }

    func isPointInsideInteractiveRegion(_ point: CGPoint) -> Bool {
        guard isVisible else { return false }
        if projectActionMenuPresentationExtraWidth > 0 || projectMenuPresentationExtraHeight > 0 {
            return frame.contains(point)
        }
        return visualSidebarFrame().contains(point)
    }

    func isMouseInsideVisibleRegion() -> Bool {
        isVisible && visualSidebarFrame().contains(NSEvent.mouseLocation)
    }

    func isMouseDeepEnoughToExpand(collapsedWidth: CGFloat) -> Bool {
        isVisible
    }

    func visualSidebarFrame() -> NSRect {
        workspaceSidebarFloatingProjectBarVisualFrame(panelFrame: frame)
    }

    func sideAreaBackgroundFrame() -> NSRect {
        visualSidebarFrame()
    }
}
