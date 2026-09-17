import AppKit

extension WorkspaceSidebarPanel {
    func updateDropTargets(_ targets: [WorkspaceSidebarDropTargetFrame]) {
        workspaceSidebarDropTargets = convertDropTargets(targets)
    }

    func convertDropTargets(_ targets: [WorkspaceSidebarDropTargetFrame]) -> [WorkspaceSidebarDropTarget] {
        targets.compactMap { target in
            let windowRect = hostingView.convert(target.frame, to: nil)
            let screenRect = convertToScreen(windowRect)
            return WorkspaceSidebarDropTarget(kind: target.kind, rect: screenRect.monitorFrameNormalized())
        }
    }

    func convertScreenPointToSidebarContentPoint(_ screenPoint: CGPoint) -> CGPoint {
        let windowPoint = convertFromScreen(NSRect(origin: screenPoint, size: .zero)).origin
        return hostingView.convert(windowPoint, from: nil)
    }

    func visibleScreenRectNormalized() -> Rect? {
        guard isVisible, viewModel.workspaceSidebarVisibleWidth > 0 else { return nil }
        return sideAreaBackgroundFrame().monitorFrameNormalized()
    }
}
