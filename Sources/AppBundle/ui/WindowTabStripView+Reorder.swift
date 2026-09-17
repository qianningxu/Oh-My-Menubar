import SwiftUI

extension WindowTabStripView {
    func tabVisualOffset(
        for tab: WindowTabItemViewModel,
        context: WindowTabStripLayoutContext,
    ) -> CGFloat {
        if let reentryPreview = trayModel.windowTabReentryPreview,
           reentryPreview.stripId == strip.id,
           reentryPreview.orderBeforeDrop == context.tabOrder {
            return tabReentryVisualOffset(for: tab, context: context, drop: reentryPreview)
        }
        if let pendingReorderDrop, pendingReorderDrop.orderBeforeDrop == context.tabOrder {
            return pendingReorderOffset(for: tab, context: context, drop: pendingReorderDrop)
        }
        guard let draggingIndex = draggingIndex(context: context),
              let targetIndex = reorderPreviewTargetIndex
        else {
            return tab.windowId == draggingTabId ? dragTranslationX : 0
        }
        if tab.windowId == draggingTabId {
            return dragTranslationX
        }
        return tabShiftOffset(
            for: tab,
            context: context,
            sourceIndex: draggingIndex,
            targetIndex: targetIndex,
        )
    }

    func draggingIndex(context: WindowTabStripLayoutContext) -> Int? {
        draggingTabId.flatMap { context.tabIndicesById[$0] }
    }

    func pendingReorderOffset(
        for tab: WindowTabItemViewModel,
        context: WindowTabStripLayoutContext,
        drop: WindowTabPendingReorderDrop,
    ) -> CGFloat {
        if tab.windowId == drop.windowId {
            if let sourceVisualOffset = drop.sourceVisualOffset {
                return sourceVisualOffset
            }
            return CGFloat(drop.targetIndex - drop.sourceIndex) * context.effectiveTabWidth
        }
        return tabShiftOffset(
            for: tab,
            context: context,
            sourceIndex: drop.sourceIndex,
            targetIndex: drop.targetIndex,
        )
    }

    func tabReentryVisualOffset(
        for tab: WindowTabItemViewModel,
        context: WindowTabStripLayoutContext,
        drop: WindowTabPendingReorderDrop,
    ) -> CGFloat {
        if tab.windowId == drop.windowId {
            return drop.sourceVisualOffset ?? CGFloat(drop.targetIndex - drop.sourceIndex) * context.effectiveTabWidth
        }
        return tabShiftOffset(
            for: tab,
            context: context,
            sourceIndex: drop.sourceIndex,
            targetIndex: drop.targetIndex,
        )
    }

    func tabShiftOffset(
        for tab: WindowTabItemViewModel,
        context: WindowTabStripLayoutContext,
        sourceIndex: Int,
        targetIndex: Int,
    ) -> CGFloat {
        guard let tabIndex = context.tabIndicesById[tab.windowId] else { return 0 }
        if sourceIndex < targetIndex, tabIndex > sourceIndex, tabIndex <= targetIndex {
            return -context.effectiveTabWidth
        }
        if sourceIndex > targetIndex, tabIndex >= targetIndex, tabIndex < sourceIndex {
            return context.effectiveTabWidth
        }
        return 0
    }

}

func tabReorderTargetIndexForFrames(
    pointerXInViewport: CGFloat,
    tabOrder: [UInt32],
    tabFramesById: [UInt32: CGRect],
    sourceIndex: Int?,
) -> Int? {
    guard tabOrder.count > 1,
          let sourceIndex,
          tabOrder.allSatisfy({ tabFramesById[$0] != nil })
    else { return nil }
    let insertionSlot = tabOrder.firstIndex { tabId in
        guard let frame = tabFramesById[tabId] else { return false }
        return pointerXInViewport < frame.midX
    } ?? tabOrder.count
    let adjustedTarget = insertionSlot > sourceIndex ? insertionSlot - 1 : insertionSlot
    return max(0, min(adjustedTarget, tabOrder.count - 1))
}

func tabReorderTargetIndex(
    pointerX: CGFloat,
    firstTabMinX: CGFloat,
    tabWidth: CGFloat,
    tabCount: Int,
    sourceIndex: Int?,
) -> Int {
    guard tabCount > 1, tabWidth > 0 else { return 0 }
    let effectiveTabWidth = tabWidth + windowTabStripTabSpacing
    let localX = pointerX - firstTabMinX
    let hoveredTabIndex = max(0, min(Int(floor(localX / effectiveTabWidth)), tabCount - 1))
    let hoveredTabCenterX = firstTabMinX + CGFloat(hoveredTabIndex) * effectiveTabWidth + tabWidth / 2
    let insertionSlot = hoveredTabIndex + (pointerX >= hoveredTabCenterX ? 1 : 0)
    guard let sourceIndex else { return max(0, min(insertionSlot, tabCount - 1)) }
    let adjustedTarget = insertionSlot > sourceIndex ? insertionSlot - 1 : insertionSlot
    return max(0, min(adjustedTarget, tabCount - 1))
}
