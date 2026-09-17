import Common

@MainActor
@discardableResult
func normalizeSystemOverlayWindow(_ window: Window, level: MacOsWindowLevel?) -> Bool {
    guard isNativeOverlayWindow(
        level: level,
        appId: window.app.rawAppBundleId.flatMap(KnownBundleId.init(rawValue:))
    ) else { return false }
    // Also repair helpers restored from layouts saved before overlay filtering.
    let emptiedWorkspace = workspaceToCloseAfterClosingLastWindow(window)
    (window as? MacWindow)?.unhideFromCorner(restoringTiledOverlay: true)
    window.layoutReason = .standard
    window.bind(to: macosPopupWindowsContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    closeWorkspaceIfEmptiedByLastWindowClosure(emptiedWorkspace)
    return true
}
