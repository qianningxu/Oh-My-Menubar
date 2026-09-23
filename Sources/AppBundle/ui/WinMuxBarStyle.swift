import AppKit
import SwiftUI

/// Shared visual rules for workspace tabs, window tabs, and the widget bar.
enum WinMuxBarStyle {
    static let cornerRadius = standardGap * 4
    static let topBarCornerRadius = standardGap * 4
    static let topBarSurfaceCornerRadius = standardGap * 4
    static let innerSpacing = standardGap * 0.75
    static let containerInset = WinMuxSpacing.comfortable
    static let topBarContentInset = WinMuxSpacing.compact
    static let contentInset = innerSpacing * 4
    static let iconSpacing = innerSpacing
    static let strokeWidth = standardGap * 0.25
    static let fontSize: CGFloat = 14
    static let maximumTabWidth = standardGap * 50
    static let projectTabsBarOuterInset = WinMuxSpacing.panel
    static let projectTabsBarContentHeight = standardGap * 12
    static let projectTabsBarHorizontalInset = WinMuxSpacing.panel
    static let projectTabsBarFontSize = fontSize + WinMuxSpacing.hairline
    static let projectBarCornerRadius = projectTabsBarContentHeight / 2
    static let projectBarHeight = projectTabsBarContentHeight + projectTabsBarOuterInset
    static let projectBarStrokeOpacity: CGFloat = 0
    static let workspaceTabContentHeight = standardGap * 8
    static let workspaceBarHeight = workspaceTabContentHeight + windowTabStripContentPaddingValue * 2
    static let workspaceTabCornerRadius = cornerRadius
    static let workspaceTabBarCornerRadius = cornerRadius + innerSpacing
    static let workspaceBarStrokeOpacity: CGFloat = 1
    static let workspaceBarSurfaceOpacity: CGFloat = 0.25
    static let workspaceBarStrokeColor = Color(nsColor: NSColor(calibratedWhite: 1, alpha: 1))
    static let workspaceBarShadowOpacity: CGFloat = 0.12
    static let workspaceBarShadowRadius = WinMuxSpacing.regular
    static let workspaceBarShadowY = WinMuxSpacing.hairline
    static let workspaceBarShadowOutset = WinMuxSpacing.section
    static let topBarStrokeOpacity: CGFloat = 0
    static let menuBarLightSurfaceOpacity: CGFloat = 0.70
    static let menuBarDarkSurfaceOpacity: CGFloat = 0.10
    static let dividerOpacity: CGFloat = 0.15
    static let workspaceTabUnfocusedTextOpacity: CGFloat = 0.50
    static let windowTabUnfocusedTextOpacity: CGFloat = 0.50
    static let workspaceSelectedSegmentOpacity: CGFloat = 0.70
    static let windowSelectedSegmentOpacity: CGFloat = 0.80
    static let windowTabHoveredSegmentOpacity: CGFloat = 0.50
    static let windowTabDividerOpacity: CGFloat = 0.40
    static let windowBarStrokeOpacity: CGFloat = 0.45
    static let windowBarBackdropSaturation: CGFloat = 0
    static let selectedSegmentOpacity: CGFloat = 0.18
    static let hoveredSegmentOpacity: CGFloat = 0.08
}

struct WinMuxGlassRecipe: Equatable {
    let blurOpacity: CGFloat
    let whiteTintOpacity: CGFloat
    let shadowOpacity: CGFloat
    let shadowRadius: CGFloat
    let shadowY: CGFloat
}

enum WinMuxGlassStyle {
    case clear
    case workspaceBar
    case windowBar
    case regular

    func surfaceOpacity(isDark: Bool) -> CGFloat {
        switch self {
            case .clear: isDark ? WinMuxBarStyle.menuBarDarkSurfaceOpacity : WinMuxBarStyle.menuBarLightSurfaceOpacity
            case .workspaceBar: WinMuxBarStyle.workspaceBarSurfaceOpacity
            default: 1
        }
    }

    var recipe: WinMuxGlassRecipe {
        switch self {
            case .clear:
                WinMuxGlassRecipe(
                    blurOpacity: 1,
                    whiteTintOpacity: 0.20,
                    shadowOpacity: 0,
                    shadowRadius: 0,
                    shadowY: 0
                )
            case .workspaceBar:
                WinMuxGlassRecipe(
                    blurOpacity: 1,
                    whiteTintOpacity: 0.60,
                    shadowOpacity: WinMuxBarStyle.workspaceBarShadowOpacity,
                    shadowRadius: WinMuxBarStyle.workspaceBarShadowRadius,
                    shadowY: WinMuxBarStyle.workspaceBarShadowY
                )
            case .windowBar:
                WinMuxGlassRecipe(
                    blurOpacity: 0.25,
                    whiteTintOpacity: 0.25,
                    shadowOpacity: 0,
                    shadowRadius: 0,
                    shadowY: 0
                )
            case .regular:
                WinMuxGlassRecipe(
                    blurOpacity: 1,
                    whiteTintOpacity: 0.28,
                    shadowOpacity: 0.12,
                    shadowRadius: WinMuxSpacing.comfortable,
                    shadowY: WinMuxSpacing.hairline
                )
        }
    }
}

struct WinMuxBarDivider: View {
    let height: CGFloat
    let palette: WinMuxOverlayPalette

    var body: some View {
        Rectangle()
            .fill(winMuxBarForeground(palette).opacity(WinMuxBarStyle.dividerOpacity))
            .frame(width: WinMuxBarStyle.strokeWidth, height: height)
            .allowsHitTesting(false)
    }
}

func winMuxBarSurfaceFill(_ palette: WinMuxOverlayPalette) -> Color {
    palette.isDark ? .black : .white
}

func winMuxBarSurfaceStroke(_ palette: WinMuxOverlayPalette) -> Color {
    winMuxBarSurfaceFill(palette)
}

func winMuxBarForeground(_ palette: WinMuxOverlayPalette) -> Color {
    palette.isDark ? .white : .black
}

func winMuxBarForegroundNSColor(_ palette: WinMuxOverlayPalette) -> NSColor {
    palette.isDark ? .white : .black
}

private struct WinMuxGlassBarSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let palette: WinMuxOverlayPalette
    let cornerRadius: CGFloat
    let material: NSVisualEffectView.Material
    let glassStyle: WinMuxGlassStyle
    let blurOpacity: CGFloat?
    let strokeOpacity: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let recipe = glassStyle.recipe
        if reduceTransparency {
            content
                .background(winMuxBarSurfaceFill(palette))
                .clipShape(shape)
                .overlay { stroke(for: shape) }
        } else {
            content
                .background {
                    ZStack {
                        VisualEffectBlur(
                            material: material,
                            blendingMode: .behindWindow,
                            opacity: blurOpacity ?? recipe.blurOpacity
                        )
                        Color.white.opacity(recipe.whiteTintOpacity)
                    }
                    .opacity(glassStyle.surfaceOpacity(isDark: palette.isDark))
                    .clipShape(shape)
                }
                .clipShape(shape)
                .overlay { stroke(for: shape) }
                .compositingGroup()
                .shadow(
                    color: .black.opacity(recipe.shadowOpacity),
                    radius: recipe.shadowRadius,
                    y: recipe.shadowY
                )
        }
    }

    private func stroke(for shape: RoundedRectangle) -> some View {
        shape.strokeBorder(
            strokeColor.opacity(strokeOpacity),
            lineWidth: WinMuxBarStyle.strokeWidth
        )
        .allowsHitTesting(false)
    }

    private var strokeColor: Color {
        switch glassStyle {
            case .workspaceBar: WinMuxBarStyle.workspaceBarStrokeColor
            default: winMuxBarSurfaceStroke(palette)
        }
    }
}

extension View {
    func winMuxCustomGlassBarSurface(
        _ palette: WinMuxOverlayPalette,
        cornerRadius: CGFloat = WinMuxBarStyle.projectBarCornerRadius,
        material: NSVisualEffectView.Material = .underWindowBackground,
        glassStyle: WinMuxGlassStyle = .clear,
        blurOpacity: CGFloat? = nil,
        strokeOpacity: CGFloat = WinMuxBarStyle.projectBarStrokeOpacity
    ) -> some View {
        modifier(WinMuxGlassBarSurfaceModifier(
            palette: palette,
            cornerRadius: cornerRadius,
            material: material,
            glassStyle: glassStyle,
            blurOpacity: blurOpacity,
            strokeOpacity: strokeOpacity
        ))
    }

    func winMuxBarSurface(
        _ palette: WinMuxOverlayPalette,
        joinedToWindow: Bool = false,
        joinsLeadingBar: Bool = false,
        joinsTrailingBar: Bool = false,
        cornerStyle: RoundedCornerStyle = .continuous,
        cornerRadius: CGFloat = WinMuxBarStyle.cornerRadius
    ) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: joinsLeadingBar ? 0 : cornerRadius,
            bottomLeadingRadius: joinedToWindow || joinsLeadingBar ? 0 : cornerRadius,
            bottomTrailingRadius: joinedToWindow || joinsTrailingBar ? 0 : cornerRadius,
            topTrailingRadius: joinsTrailingBar ? 0 : cornerRadius,
            style: cornerStyle
        )
        return self
            .background(winMuxBarSurfaceFill(palette))
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(winMuxBarSurfaceStroke(palette), lineWidth: WinMuxBarStyle.strokeWidth)
                    .allowsHitTesting(false)
            }
    }

    func winMuxBarSegment(
        _ palette: WinMuxOverlayPalette,
        isSelected: Bool,
        isHovered: Bool,
        selectedOpacity: CGFloat = WinMuxBarStyle.selectedSegmentOpacity,
        hoveredOpacity: CGFloat = WinMuxBarStyle.hoveredSegmentOpacity
    ) -> some View {
        background {
            if isSelected {
                Rectangle().fill(
                    winMuxBarSurfaceFill(palette).opacity(selectedOpacity)
                )
            } else if isHovered {
                Rectangle().fill(
                    winMuxBarSurfaceFill(palette)
                        .opacity(hoveredOpacity)
                )
            }
        }
    }
}
