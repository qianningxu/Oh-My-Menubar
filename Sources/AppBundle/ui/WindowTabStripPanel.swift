import AppKit
import Common
import SwiftUI

@MainActor
final class WindowTabStripPanel: NSPanelHud {
    let hostingView = WindowTabStripHostingView(rootView: AnyView(EmptyView()))
    var currentContent: WindowTabGroupChromeContent?
    var currentPanelFrame: CGRect?
    var externallyIgnoresMouseEvents = false
    var tabStripIsOccludedByFloatingWindow = false
    private var isRenamingTab = false

    init(id: ObjectIdentifier) {
        super.init()
        identifier = NSUserInterfaceItemIdentifier(windowTabStripPanelPrefix + String(id.hashValue))
        hasShadow = false
        isFloatingPanel = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        backgroundColor = WinMuxDesignTokens.transparentNSColor
        applyWinMuxLayer(.windowChrome)
        contentView = hostingView
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
    }

    override var canBecomeKey: Bool { isRenamingTab }
    override var canBecomeMain: Bool { false }

    func beginTabRename() {
        isRenamingTab = true
        ignoresMouseEvents = false
        orderFrontRegardless()
        makeKeyAndOrderFront(nil)
        makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    func endTabRename() {
        isRenamingTab = false
    }

    func update(with strip: WindowTabStripViewModel) {
        let displayStrip = strip.alignedForWindowTabChrome()
        let nextContent = WindowTabGroupChromeContent(strip: displayStrip)
        guard shouldUpdate(content: nextContent, strip: displayStrip) else { return }
        if currentContent != nextContent {
            // This borderless chrome panel must use its entire content rect.
            // Respecting the hosting view safe area leaves a visible top inset.
            hostingView.rootView = AnyView(WindowTabStripView(strip: displayStrip).ignoresSafeArea())
            currentContent = nextContent
        }
        currentPanelFrame = displayStrip.frame
        debugFocusLog("WindowTabStripPanel.update id=\(String(describing: identifier?.rawValue)) frame=\(displayStrip.frame)")
        setWindowTabChromePanelFrame(displayStrip.frame, on: self)
        tabStripIsOccludedByFloatingWindow = displayStrip.tabStripIsOccludedByFloatingWindow
        updateMousePolicy()
        applyWindowTabStripStackingPolicy(for: displayStrip, to: self)
    }

    func setExternalIgnoresMouseEvents(_ ignoresMouseEvents: Bool) {
        externallyIgnoresMouseEvents = ignoresMouseEvents
        updateMousePolicy()
    }
}
