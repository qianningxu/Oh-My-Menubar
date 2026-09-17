import Foundation

extension WindowTabStripPanelController {
    func refresh() {
        guard TrayMenuModel.shared.isEnabled, legacyWindowTabBehaviorIsEnabled() else {
            hideAll()
            return
        }

        let strips = windowTabStripsWithTransientResizeApplied(TrayMenuModel.shared.windowTabStrips)
        let activeIds = Set(strips.map(\.id))
        if let mouseInteractionChromeMode {
            refreshSuppressedChrome(mode: mouseInteractionChromeMode, strips: strips, activeIds: activeIds)
            return
        }
        refreshInteractiveChrome(strips: strips, activeIds: activeIds)
    }

    func windowTabStripsWithTransientResizeApplied(_ strips: [WindowTabStripViewModel]) -> [WindowTabStripViewModel] {
        strips.map { strip in
            if let active = transientResizeTabGroupStrip, strip.id == active.id { return active }
            return transientRelatedResizeStrips[strip.id] ?? strip
        }
    }

    func refreshInteractiveChrome(strips: [WindowTabStripViewModel], activeIds: Set<ObjectIdentifier>) {
        for strip in strips {
            guard !hiddenPassiveTabGroupChromeIds.contains(strip.id) else {
                orderOutPanels(id: strip.id)
                continue
            }
            visualPanel(for: strip.id).update(with: strip)
            stripPanel(for: strip.id).update(with: strip)
        }
        removeStalePanels(activeIds: activeIds)
    }

    func refreshSuppressedChrome(
        mode: MouseInteractionChromeMode,
        strips: [WindowTabStripViewModel],
        activeIds: Set<ObjectIdentifier>,
    ) {
        switch mode {
            case .frameOnly:
                refreshFrameOnlyChrome(strips: strips, activeIds: activeIds)
            case .hidden:
                refreshHiddenChrome(activeIds: activeIds)
        }
    }

    func refreshFrameOnlyChrome(strips: [WindowTabStripViewModel], activeIds: Set<ObjectIdentifier>) {
        for strip in strips {
            guard !hiddenPassiveTabGroupChromeIds.contains(strip.id) else {
                orderOutPanels(id: strip.id)
                continue
            }
            visualPanel(for: strip.id).update(with: strip)
            orderOutIfVisible(stripPanels[strip.id])
        }
        removeStalePanels(activeIds: activeIds)
    }
}
