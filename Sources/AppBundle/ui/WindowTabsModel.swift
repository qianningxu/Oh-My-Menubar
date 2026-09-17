import AppKit

@MainActor
func updateWindowTabModel() async {
    let tabChromeController = WindowTabStripPanelController.shared
    let didClearMouseInteractionChromeSuppression =
        tabChromeController.clearMouseInteractionChromeSuppressionIfInactive()
    // A transient strip follows an in-progress native resize. Once the mouse
    // session has ended, it must yield to the freshly observed window frame.
    let didClearTransientResizeChrome = currentlyManipulatedWithMouseWindowId == nil &&
        tabChromeController.clearTransientResizeChrome()
    guard TrayMenuModel.shared.isEnabled, legacyWindowTabBehaviorIsEnabled() else {
        TrayMenuModel.shared.windowTabStrips = []
        tabChromeController.refresh()
        debugFocusLog("updateWindowTabModel disabled -> cleared")
        return
    }
    pruneCachedWindowTitles()

    let strips = await buildWindowTabStripViewModelsFromChromeItems()

    if TrayMenuModel.shared.windowTabStrips != strips {
        debugFocusLog("updateWindowTabModel apply strips old=\(TrayMenuModel.shared.windowTabStrips.map(\.frame)) new=\(strips.map(\.frame))")
        TrayMenuModel.shared.windowTabStrips = strips
        tabChromeController.refresh()
    } else {
        if didClearMouseInteractionChromeSuppression || didClearTransientResizeChrome {
            tabChromeController.refresh()
        }
        debugFocusLog("updateWindowTabModel unchanged strips=\(strips.map(\.frame))")
    }
}
