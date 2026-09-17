import AppKit
import Common

extension WindowTabStripViewModel {
    func alignedForWindowTabChrome() -> WindowTabStripViewModel {
        WindowTabStripViewModel(
            id: id,
            workspaceName: workspaceName,
            frame: frame.alignedToBackingPixels(),
            groupFrame: groupFrame.alignedToBackingPixels(),
            activeWindowId: activeWindowId,
            isFocused: isFocused,
            activeWindowCornerRadius: activeWindowCornerRadius,
            tabs: tabs,
            occludingFloatingWindowFrames: occludingFloatingWindowFrames,
        )
    }
}

@MainActor
func setWindowTabChromePanelFrame(_ frame: CGRect, on panel: NSPanelHud) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    panel.setFrame(frame, display: true, animate: false)
    panel.contentView?.layoutSubtreeIfNeeded()
    CATransaction.commit()
}

@MainActor
func applyWindowTabVisualStackingPolicy(for strip: WindowTabStripViewModel, to panel: NSPanelHud) {
    applyWindowTabChromeStackingPolicy(for: strip, to: panel, order: .below)
}

@MainActor
func applyWindowTabStripStackingPolicy(for strip: WindowTabStripViewModel, to panel: NSPanelHud) {
    // Keep the native window's shadow visible over the workspace tab bar.
    applyWindowTabChromeStackingPolicy(for: strip, to: panel, order: .below)
}

@MainActor
private func applyWindowTabChromeStackingPolicy(
    for strip: WindowTabStripViewModel,
    to panel: NSPanelHud,
    order: NSWindow.OrderingMode,
) {
    let previousLevel = panel.level
    let previousIsFloating = panel.isFloatingPanel
    let targetLevel = WinMuxPanelLayer.windowChrome.level

    panel.isFloatingPanel = false
    WinMuxMenuPresentation.shared.setLevel(targetLevel, for: panel)
    if WinMuxMenuPresentation.shared.owns(panel) {
        panel.orderFrontRegardless()
        return
    }
    if let activeWindowId = strip.activeWindowId {
        panel.order(order, relativeTo: Int(activeWindowId))
    } else if !panel.isVisible || previousLevel != targetLevel || previousIsFloating {
        panel.orderFrontRegardless()
    }
}
