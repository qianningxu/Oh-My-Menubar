import CoreGraphics

@MainActor
func buildWindowTabChromeItemsFromSource10Tree() async -> [WindowTabChromeItem] {
    guard TrayMenuModel.shared.isEnabled, legacyWindowTabBehaviorIsEnabled() else { return [] }
    guard !shouldSuppressChromeForNativeFullscreenContent else { return [] }
    pruneCachedWindowTitles()

    let visibleWorkspaces = Workspace.all.filter(\.isVisible)
    let titleWindows = visibleWorkspaces.flatMap { workspace in
        workspace.rootTilingContainer.allTabbedContainersRecursive.flatMap { container in
            container.children.compactMap(\.tabRepresentativeWindow)
        }
    }

    return await withWindowTabCachedWindowTitles(titleWindows) {
        var items: [WindowTabChromeItem] = []
        for workspace in visibleWorkspaces {
            for container in workspace.rootTilingContainer.allTabbedContainersRecursive {
                if let item = await makeWindowTabChromeItem(container: container, workspace: workspace) {
                    items.append(item)
                }
            }
        }
        return items
    }
}

@MainActor
private func makeWindowTabChromeItem(
    container: TilingContainer,
    workspace: Workspace,
) async -> WindowTabChromeItem? {
    guard let activeWindow = container.tabActiveWindow,
          let contentFrame = activeWindowContentFrame(activeWindow, container: container)
    else { return nil }
    let tabs = await makeWindowTabChromeTabs(container: container, activeWindowId: activeWindow.windowId)
    guard !tabs.isEmpty else { return nil }
    return WindowTabChromeItem(
        id: ObjectIdentifier(container),
        workspaceName: workspace.name,
        activeWindowId: activeWindow.windowId,
        orderingWindowId: activeWindow.windowId,
        contentFrame: contentFrame.toAppKitScreenRect.alignedToBackingPixels(),
        visibleFrame: container.windowTabGroupFrameRect?.toAppKitScreenRect.alignedToBackingPixels(),
        tabs: tabs,
    )
}
