import AppKit

private let windowTabBarOuterInsetValue = WinMuxSpacing.none
// The workspace layout already supplies the gap between groups. Keep the
// bar and native window on the same horizontal bounds without adding it twice.
private let windowTabGroupShellHorizontalInsetValue = WinMuxSpacing.none
// The canvas supplies the top gap; reserve only the gap below the tab bar.
private let windowTabGroupShellTopInsetValue = WinMuxSpacing.comfortable
private let windowTabGroupShellBottomInsetValue = WinMuxSpacing.none
// Match the visible height of the menu-bar surfaces.
private let windowTabBarMinimumHeightValue = workspaceSidebarTabRowHeight - standardGap * 0.5

func windowTabGroupShellHorizontalInset() -> CGFloat {
    windowTabGroupShellHorizontalInsetValue
}

func windowTabGroupShellTopInset() -> CGFloat {
    windowTabGroupShellTopInsetValue
}

func windowTabGroupShellBottomInset() -> CGFloat {
    windowTabGroupShellBottomInsetValue
}

func windowTabBarOuterInset() -> CGFloat {
    windowTabBarOuterInsetValue
}

@MainActor
func resolvedWindowTabBarHeight() -> CGFloat {
    guard NSScreen.main != nil else { return WinMuxBarStyle.workspaceBarHeight }
    return WinMuxBarStyle.workspaceBarHeight
}
