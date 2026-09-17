import AppKit
import SwiftUI

var usesNativeLiquidGlass: Bool {
    false
}

@ViewBuilder
func liquidGlassBackground<S: Shape, Fallback: View>(
    in shape: S,
    isInteractive _: Bool = true,
    @ViewBuilder fallback: () -> Fallback,
) -> some View {
    fallback()
}

struct LiquidGlassSurface<S: Shape>: View {
    @Environment(\.colorScheme) private var colorScheme

    let shape: S
    var lineWidth: CGFloat = 0.7
    var isInteractive: Bool = true
    var usesEvenOddFill: Bool = false

    var body: some View {
        let palette = WinMuxOverlayPalette(colorScheme: colorScheme)
        ZStack {
            liquidGlassBackground(in: shape, isInteractive: isInteractive) {
                shape.fill(palette.geistBackground(.primary), style: fillStyle)
            }
            shape
                .fill(palette.componentBackground(.normal), style: fillStyle)
            shape.stroke(palette.geistBorder(.normal), lineWidth: lineWidth)
        }
        .compositingGroup()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var fillStyle: FillStyle {
        FillStyle(eoFill: usesEvenOddFill)
    }
}
