import AppKit
import SwiftUI

enum AppearanceTheme: Hashable {
    case light
    case dark

    @MainActor
    static var current: AppearanceTheme {
        from(NSApplication.shared.effectiveAppearance)
    }

    init(colorScheme: ColorScheme) {
        self = colorScheme == .dark ? .dark : .light
    }

    static func from(_ appearance: NSAppearance) -> AppearanceTheme {
        let name = appearance.bestMatch(from: [
            .aqua,
            .darkAqua,
            .vibrantLight,
            .vibrantDark,
            .accessibilityHighContrastAqua,
            .accessibilityHighContrastDarkAqua,
            .accessibilityHighContrastVibrantLight,
            .accessibilityHighContrastVibrantDark,
        ]) ?? appearance.name
        let isDarkAppearance = name == .vibrantDark ||
            name == .darkAqua ||
            name == .accessibilityHighContrastDarkAqua ||
            name == .accessibilityHighContrastVibrantDark
        return isDarkAppearance ? .dark : .light
    }
}

struct WinMuxOverlayPalette {
    let theme: AppearanceTheme
    let projectThemeFamily: WorkspaceSidebarProjectThemeFamily?

    init(
        theme: AppearanceTheme,
        projectThemeFamily: WorkspaceSidebarProjectThemeFamily? = nil
    ) {
        self.theme = theme
        self.projectThemeFamily = projectThemeFamily
    }

    init(
        colorScheme: ColorScheme,
        projectThemeFamily: WorkspaceSidebarProjectThemeFamily? = nil
    ) {
        self.theme = AppearanceTheme(colorScheme: colorScheme)
        self.projectThemeFamily = projectThemeFamily
    }

    @MainActor
    static var current: WinMuxOverlayPalette {
        WinMuxOverlayPalette(theme: .current)
    }

    var colorScheme: ColorScheme {
        theme == .dark ? .dark : .light
    }

    var isDark: Bool {
        theme == .dark
    }

    static func adaptiveNSColor(_ provider: @escaping (WinMuxOverlayPalette) -> NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            provider(WinMuxOverlayPalette(theme: AppearanceTheme.from(appearance)))
        }
    }

    static func adaptiveColor(_ provider: @escaping (WinMuxOverlayPalette) -> NSColor) -> Color {
        Color(nsColor: adaptiveNSColor(provider))
    }
}

func winMuxOverlayContent(_ role: GeistContentRole) -> Color {
    WinMuxOverlayPalette.adaptiveColor { $0.contentNSColor(role) }
}

func winMuxOverlayGeistBackground(_ role: GeistBackgroundRole) -> Color {
    WinMuxOverlayPalette.adaptiveColor { $0.geistBackgroundNSColor(role) }
}

func winMuxOverlayComponentBackground(_ state: GeistComponentState) -> Color {
    WinMuxOverlayPalette.adaptiveColor { $0.componentBackgroundNSColor(state) }
}

func winMuxOverlayBorder(_ state: GeistBorderState) -> Color {
    WinMuxOverlayPalette.adaptiveColor { $0.geistBorderNSColor(state) }
}

func winMuxOverlayHighContrastBackground(_ state: GeistHighContrastState) -> Color {
    WinMuxOverlayPalette.adaptiveColor { $0.highContrastBackgroundNSColor(state) }
}

func winMuxOverlayColor(
    _ family: WorkspaceSidebarProjectThemeFamily,
    _ step: GeistColorStep
) -> Color {
    WinMuxOverlayPalette.adaptiveColor { $0.colorNSColor(family, step) }
}
