import AppKit

open class NSPanelHud: NSPanel {
    open override func sendEvent(_ event: NSEvent) {
        let opensContextMenu = event.type == .rightMouseDown ||
            (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        if opensContextMenu { WinMuxMenuPresentation.shared.prepare(self) }
        super.sendEvent(event)
        if opensContextMenu { WinMuxMenuPresentation.shared.finishEvent() }
    }

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false,
        )
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false
        self.isMovableByWindowBackground = false
        self.alphaValue = 1
        self.hasShadow = true
        self.isOpaque = false
        self.backgroundColor = WinMuxDesignTokens.transparentNSColor
    }
}
