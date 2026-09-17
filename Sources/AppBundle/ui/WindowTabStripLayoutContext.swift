import AppKit

struct WindowTabStripLayoutContext {
    let strip: WindowTabStripViewModel
    let width: CGFloat

    var tabOrder: [UInt32] {
        strip.tabs.map(\.windowId)
    }

    var tabIndicesById: [UInt32: Int] {
        Dictionary(uniqueKeysWithValues: strip.tabs.enumerated().map { ($0.element.windowId, $0.offset) })
    }

    var tabWidth: CGFloat {
        windowTabStripTabWidth(stripWidth: width, count: strip.tabs.count)
    }

    var showsTabTitles: Bool {
        // Keep titles visible and truncate them as tabs shrink to fit.
        true
    }

    var effectiveTabWidth: CGFloat {
        tabWidth + windowTabStripTabSpacing
    }

    func pointerXInContent(sourceIndex: Int, pointerXInSourceTab: CGFloat) -> CGFloat {
        windowTabStripContentHorizontalPadding
            + CGFloat(sourceIndex) * effectiveTabWidth
            + pointerXInSourceTab
    }

    var scrollViewportWidth: CGFloat {
        windowTabStripScrollViewportWidth(stripWidth: width)
    }

    var scrollContentWidth: CGFloat {
        CGFloat(strip.tabs.count) * tabWidth
            + CGFloat(max(strip.tabs.count - 1, 0)) * windowTabStripTabSpacing
            + windowTabStripContentHorizontalPadding * 2
    }

    var isScrollable: Bool {
        scrollContentWidth > scrollViewportWidth + 1
    }

    var scrollCoordinateSpaceName: String {
        "window-tab-strip-scroll-\(strip.id.hashValue)"
    }

    var outerTopRadius: CGFloat {
        windowTabGroupOuterCornerRadius(
            innerCornerRadius: windowTabGroupTopInnerCornerRadius(strip.activeWindowCornerRadius)
        )
    }

    func trailingFadeWidth(contentMinX: CGFloat) -> CGFloat {
        windowTabTrailingScrollFadeWidth(
            isScrollable: shouldFadeTabScroll,
            contentMaxX: contentMinX + scrollContentWidth,
            viewportWidth: scrollViewportWidth,
            stripWidth: width,
        )
    }

    func leadingFadeWidth(contentMinX: CGFloat) -> CGFloat {
        windowTabLeadingScrollFadeWidth(
            isScrollable: shouldFadeTabScroll,
            contentMinX: contentMinX,
            stripWidth: width,
        )
    }

    private var shouldFadeTabScroll: Bool { isScrollable }

}
