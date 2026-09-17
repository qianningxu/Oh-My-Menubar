import SwiftUI

struct WindowTabGroupVisualView: View {
    let strip: WindowTabStripViewModel

    @ObservedObject private var trayModel = TrayMenuModel.shared
    @Environment(\.colorScheme) private var colorScheme
    private var palette: WinMuxOverlayPalette { trayModel.projectPalette(workspaceName: strip.workspaceName, colorScheme: colorScheme) }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: WinMuxSpacing.none) {
                WinMuxDesignTokens.transparent
                .frame(
                    width: max(geometry.size.width - windowTabGroupShellHorizontalInset() * 2, 0),
                    height: min(WinMuxBarStyle.workspaceBarHeight, geometry.size.height)
                )
                .winMuxCustomGlassBarSurface(
                    palette,
                    cornerRadius: WinMuxBarStyle.workspaceTabBarCornerRadius,
                    glassStyle: .windowBar,
                    strokeOpacity: 0
                )
                .saturation(WinMuxBarStyle.windowBarBackdropSaturation)
                .overlay {
                    RoundedRectangle(
                        cornerRadius: WinMuxBarStyle.workspaceTabBarCornerRadius,
                        style: .continuous
                    )
                    .strokeBorder(
                        winMuxBarSurfaceStroke(palette).opacity(WinMuxBarStyle.windowBarStrokeOpacity),
                        lineWidth: WinMuxBarStyle.strokeWidth
                    )
                }
                .padding(.top, windowTabBarOuterInset())

                Spacer(minLength: WinMuxSpacing.none)
            }
        }
            .allowsHitTesting(false)
    }
}
