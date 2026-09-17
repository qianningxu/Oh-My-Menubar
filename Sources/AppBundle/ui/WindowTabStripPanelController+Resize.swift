import Foundation

extension WindowTabStripPanelController {
    @discardableResult
    func updateResizingTabGroupChrome(window: Window, activeWindowRect: Rect) -> Bool {
        guard let transientStrip = resizingTabGroupStrip(window: window, activeWindowRect: activeWindowRect) else {
            transientResizeTabGroupId = nil
            transientResizeTabGroupStrip = nil
            return false
        }

        transientResizeTabGroupId = transientStrip.id
        transientResizeTabGroupStrip = transientStrip
        if hiddenPassiveTabGroupChromeIds.contains(transientStrip.id) {
            orderOutPanels(id: transientStrip.id)
            return true
        }
        visualPanel(for: transientStrip.id).update(with: transientStrip)
        updateInteractivePanelForResizingStrip(transientStrip)
        return true
    }

    @discardableResult
    func clearTransientResizeChrome() -> Bool {
        guard transientResizeTabGroupId != nil || transientResizeTabGroupStrip != nil || !transientRelatedResizeStrips.isEmpty else { return false }
        transientResizeTabGroupId = nil
        transientResizeTabGroupStrip = nil
        transientRelatedResizeStrips.removeAll()
        return true
    }

    func updateRelatedResizeChrome(window: Window, activeWindowRect: Rect) {
        guard let strip = resizingTabGroupStrip(window: window, activeWindowRect: activeWindowRect) else { return }
        transientRelatedResizeStrips[strip.id] = strip
        refresh()
    }

    func updateInteractivePanelForResizingStrip(_ strip: WindowTabStripViewModel) {
        if mouseInteractionChromeMode != nil {
            orderOutIfVisible(stripPanels[strip.id])
        } else {
            stripPanel(for: strip.id).update(with: strip)
        }
    }

    func resizingTabGroupStrip(window: Window, activeWindowRect: Rect) -> WindowTabStripViewModel? {
        guard TrayMenuModel.shared.isEnabled,
              legacyWindowTabBehaviorIsEnabled(),
              let tabGroup = window.nearestWindowTabGroup,
              tabGroup.usesWindowTabBehavior,
              tabGroup.tabActiveWindow == window
        else { return nil }
        let id = ObjectIdentifier(tabGroup)
        guard let baseStrip = TrayMenuModel.shared.windowTabStrips.first(where: { $0.id == id }) else { return nil }
        return resizingTabGroupStrip(baseStrip: baseStrip, activeWindowRect: activeWindowRect)
    }

    func resizingTabGroupStrip(baseStrip: WindowTabStripViewModel, activeWindowRect: Rect) -> WindowTabStripViewModel {
        let groupFrameRect = windowTabGroupFrameRect(forActiveWindowContentRect: activeWindowRect)
        let tabBarRect = windowTabBarRect(forGroupFrameRect: groupFrameRect)
        return WindowTabStripViewModel(
            id: baseStrip.id,
            workspaceName: baseStrip.workspaceName,
            frame: tabBarRect.toAppKitScreenRect.alignedToBackingPixels(),
            groupFrame: groupFrameRect.toAppKitScreenRect.alignedToBackingPixels(),
            activeWindowId: baseStrip.activeWindowId,
            isFocused: baseStrip.isFocused,
            activeWindowCornerRadius: baseStrip.activeWindowCornerRadius,
            tabs: baseStrip.tabs,
            occludingFloatingWindowFrames: baseStrip.occludingFloatingWindowFrames,
        )
    }
}
