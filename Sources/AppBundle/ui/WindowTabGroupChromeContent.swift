import CoreGraphics

struct WindowTabGroupChromeContent: Equatable {
    let workspaceName: String
    let activeWindowId: UInt32?
    let isFocused: Bool
    let activeWindowCornerRadius: CGFloat
    let tabs: [WindowTabItemViewModel]
    let occludingFloatingWindowFrames: [CGRect]

    init(strip: WindowTabStripViewModel) {
        workspaceName = strip.workspaceName
        activeWindowId = strip.activeWindowId
        isFocused = strip.isFocused
        activeWindowCornerRadius = strip.activeWindowCornerRadius
        tabs = strip.tabs
        occludingFloatingWindowFrames = strip.occludingFloatingWindowFrames
    }
}
