import AppKit
import Common

func legacyWindowTabBehaviorIsEnabledForEnvironment(configEnabled: Bool, isUnitTestProcess _: Bool) -> Bool {
    configEnabled
}

@MainActor
func legacyWindowTabBehaviorIsEnabled() -> Bool {
    legacyWindowTabBehaviorIsEnabledForEnvironment(
        configEnabled: config.windowTabs.enabled,
        isUnitTestProcess: isUnitTest,
    )
}

extension TilingContainer {
    @MainActor
    var usesWindowTabBehavior: Bool {
        isWindowTabGroup && legacyWindowTabBehaviorIsEnabled()
    }

    @MainActor
    var showsWindowTabs: Bool {
        usesWindowTabBehavior && !hasFullscreenTab
    }

    @MainActor
    var windowTabBarHeight: CGFloat {
        showsWindowTabs ? min(resolvedWindowTabBarHeight(), windowTabBarReferenceRect?.height ?? 0) : 0
    }

    @MainActor
    var windowTabBarRect: Rect? {
        guard showsWindowTabs, let rect = windowTabBarReferenceRect else { return nil }
        return AppBundle.windowTabBarRect(forGroupFrameRect: rect)
    }

    @MainActor
    var windowTabGroupFrameRect: Rect? {
        guard showsWindowTabs else { return nil }
        return windowTabBarReferenceRect
    }

    @MainActor
    var tabActiveWindow: Window? {
        mostRecentChild?.tabRepresentativeWindow ?? mostRecentWindowRecursive
    }

    @MainActor
    var hasFullscreenTab: Bool {
        usesWindowTabBehavior && allLeafWindowsRecursive.contains(where: \.isFullscreen)
    }
}
