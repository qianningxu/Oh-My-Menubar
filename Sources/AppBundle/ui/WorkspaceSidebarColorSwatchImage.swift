import AppKit

@MainActor
func workspaceSidebarProjectColorSwatchImage(hex: String, isSelected: Bool) -> NSImage {
    let theme = AppearanceTheme.current
    let color = WorkspaceSidebarProjectThemeFamily.resolve(configuredHex: hex)?
        .nsColor(step: 700, theme: theme)
        ?? GeistColorSystem.color(.gray, .color7, theme: theme)
    let selectionColor = WinMuxOverlayPalette(theme: theme).geistBackgroundNSColor(.primary)
    return workspaceSidebarSwatchImage {
        drawWorkspaceSidebarSwatchCircle(
            fill: color,
            stroke: isSelected ? selectionColor : WinMuxDesignTokens.transparentNSColor,
            lineWidth: isSelected ? 1.5 : 1,
        )
        guard isSelected else { return }
        drawWorkspaceSidebarSwatchCheckmark(color: selectionColor)
    }
}

func drawWorkspaceSidebarSwatchCheckmark(color: NSColor) {
    let checkPath = NSBezierPath()
    checkPath.move(to: NSPoint(x: 5.2, y: 8.0))
    checkPath.line(to: NSPoint(x: 7.2, y: 6.0))
    checkPath.line(to: NSPoint(x: 10.9, y: 10.2))
    checkPath.lineCapStyle = .round
    checkPath.lineJoinStyle = .round
    checkPath.lineWidth = 1.5
    color.setStroke()
    checkPath.stroke()
}
