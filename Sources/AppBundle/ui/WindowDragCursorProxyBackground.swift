import SwiftUI

struct WindowDragCursorProxyBackground: View {
    var isGroup: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    private var palette: WinMuxOverlayPalette { WinMuxOverlayPalette(colorScheme: colorScheme) }

    var body: some View {
        RoundedRectangle(cornerRadius: workspaceSidebarRowCornerRadius, style: .continuous)
            .fill(palette.componentBackground(isGroup ? .active : .hover))
            .overlay {
                RoundedRectangle(cornerRadius: workspaceSidebarRowCornerRadius, style: .continuous)
                    .strokeBorder(palette.geistBorder(isGroup ? .active : .hover), lineWidth: 0.7)
            }
    }
}
