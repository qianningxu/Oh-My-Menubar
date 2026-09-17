import AppKit
import SwiftUI

enum GeistBackgroundRole: CaseIterable {
    case primary
    case secondary
}

enum GeistComponentState: CaseIterable {
    case normal
    case hover
    case active

    var step: GeistColorStep {
        switch self {
            case .normal: .color1
            case .hover: .color2
            case .active: .color3
        }
    }
}

enum GeistBorderState: CaseIterable {
    case normal
    case hover
    case active

    var step: GeistColorStep {
        switch self {
            case .normal: .color4
            case .hover: .color5
            case .active: .color6
        }
    }
}

enum GeistHighContrastState: CaseIterable {
    case normal
    case hover

    var step: GeistColorStep {
        switch self {
            case .normal: .color7
            case .hover: .color8
        }
    }
}

enum GeistContentRole: CaseIterable {
    case secondary
    case primary

    var step: GeistColorStep {
        switch self {
            case .secondary: .color9
            case .primary: .color10
        }
    }
}

enum GeistColorStep: Int, CaseIterable {
    case color1 = 100
    case color2 = 200
    case color3 = 300
    case color4 = 400
    case color5 = 500
    case color6 = 600
    case color7 = 700
    case color8 = 800
    case color9 = 900
    case color10 = 1000

    var index: Int {
        (rawValue / 100) - 1
    }
}

enum GeistColorSystem {
    static func background(_ role: GeistBackgroundRole, theme: AppearanceTheme) -> NSColor {
        GeistColorTokens.background(role, theme: theme).nsColor
    }

    static func color(
        _ family: WorkspaceSidebarProjectThemeFamily,
        _ step: GeistColorStep,
        theme: AppearanceTheme
    ) -> NSColor {
        GeistColorTokens.color(family, step, theme: theme).nsColor
    }
}

extension WinMuxOverlayPalette {
    var activeGeistFamily: WorkspaceSidebarProjectThemeFamily {
        projectThemeFamily ?? .gray
    }

    var rootSurfaceNSColor: NSColor {
        GeistColorSystem.color(activeGeistFamily, .color3, theme: theme)
    }

    var rootSurface: Color {
        Color(nsColor: rootSurfaceNSColor)
    }

    func geistBackgroundNSColor(_ role: GeistBackgroundRole) -> NSColor {
        GeistColorSystem.background(role, theme: theme)
    }

    func geistBackground(_ role: GeistBackgroundRole) -> Color {
        Color(nsColor: geistBackgroundNSColor(role))
    }

    func componentBackgroundNSColor(_ state: GeistComponentState) -> NSColor {
        if state == .normal {
            return GeistColorSystem.background(.primary, theme: theme)
        }
        return GeistColorSystem.color(activeGeistFamily, state.step, theme: theme)
    }

    func componentBackground(_ state: GeistComponentState) -> Color {
        Color(nsColor: componentBackgroundNSColor(state))
    }

    func geistBorderNSColor(_ state: GeistBorderState) -> NSColor {
        GeistColorSystem.color(activeGeistFamily, state.step, theme: theme)
    }

    func geistBorder(_ state: GeistBorderState) -> Color {
        Color(nsColor: geistBorderNSColor(state))
    }

    func highContrastBackgroundNSColor(_ state: GeistHighContrastState) -> NSColor {
        GeistColorSystem.color(activeGeistFamily, state.step, theme: theme)
    }

    func highContrastBackground(_ state: GeistHighContrastState) -> Color {
        Color(nsColor: highContrastBackgroundNSColor(state))
    }

    func contentNSColor(_ role: GeistContentRole) -> NSColor {
        GeistColorSystem.color(activeGeistFamily, role.step, theme: theme)
    }

    func content(_ role: GeistContentRole) -> Color {
        Color(nsColor: contentNSColor(role))
    }

    func colorNSColor(
        _ family: WorkspaceSidebarProjectThemeFamily,
        _ step: GeistColorStep
    ) -> NSColor {
        GeistColorSystem.color(family, step, theme: theme)
    }

    func color(
        _ family: WorkspaceSidebarProjectThemeFamily,
        _ step: GeistColorStep
    ) -> Color {
        Color(nsColor: colorNSColor(family, step))
    }
}
