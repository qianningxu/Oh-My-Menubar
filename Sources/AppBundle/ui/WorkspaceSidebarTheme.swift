import AppKit
import Common
import SwiftUI

enum WorkspaceSidebarProjectThemeFamily: String, CaseIterable, Hashable {
    case gray
    case blue
    case teal
    case green
    case amber
    case red
    case pink
    case purple

    static func resolve(configuredHex: String?) -> WorkspaceSidebarProjectThemeFamily? {
        guard let configuredHex = configuredHex.flatMap(normalizedWorkspaceSidebarColorHex),
              let color = workspaceSidebarNSColor(hex: configuredHex)?.usingColorSpace(.sRGB)
        else { return .gray }

        if let exact = workspaceSidebarProjectColorPresets.first(where: { $0.hex == configuredHex }) {
            return WorkspaceSidebarProjectThemeFamily(rawValue: exact.name.lowercased())
        }

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        guard saturation > 0.08 else { return .gray }

        return allCases.min {
            circularHueDistance(hue, $0.anchorHue) < circularHueDistance(hue, $1.anchorHue)
        }
    }

    func nsColor(step: Int, theme: AppearanceTheme) -> NSColor {
        GeistColorSystem.color(self, GeistColorStep(rawValue: step) ?? .color7, theme: theme)
    }

    private var anchorHue: CGFloat {
        let color = nsColor(step: 700, theme: .light).usingColorSpace(.sRGB).orDie()
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return hue
    }

}

func workspaceSidebarProjectThemeFamily(
    projects: [WorkspaceSidebarProjectViewModel],
    activeProjectId: WorkspaceProjectId
) -> WorkspaceSidebarProjectThemeFamily? {
    let configuredHex = projects.first { $0.id == activeProjectId }?.colorHex
    return WorkspaceSidebarProjectThemeFamily.resolve(configuredHex: configuredHex)
}

private struct WorkspaceSidebarProjectThemeFamilyKey: EnvironmentKey {
    static let defaultValue: WorkspaceSidebarProjectThemeFamily? = nil
}

extension EnvironmentValues {
    var workspaceSidebarProjectThemeFamily: WorkspaceSidebarProjectThemeFamily? {
        get { self[WorkspaceSidebarProjectThemeFamilyKey.self] }
        set { self[WorkspaceSidebarProjectThemeFamilyKey.self] = newValue }
    }
}

struct WorkspaceSidebarWidgetShapeStyle: ShapeStyle {
    enum Source {
        case active(GeistColorStep)
        case semantic(WorkspaceSidebarProjectThemeFamily, GeistColorStep)
    }

    let source: Source

    func resolve(in environment: EnvironmentValues) -> Color {
        let palette = WinMuxOverlayPalette(
            colorScheme: environment.colorScheme,
            projectThemeFamily: environment.workspaceSidebarProjectThemeFamily
        )
        let color: NSColor
        switch source {
            case .active(let step):
                color = palette.colorNSColor(palette.activeGeistFamily, step)
            case .semantic(let family, let step):
                color = palette.colorNSColor(family, step)
        }
        return Color(nsColor: color)
    }
}

func workspaceSidebarWidgetContent(_ role: GeistContentRole) -> WorkspaceSidebarWidgetShapeStyle {
    WorkspaceSidebarWidgetShapeStyle(source: .active(role.step))
}

func workspaceSidebarWidgetComponentBackground(
    _ state: GeistComponentState
) -> WorkspaceSidebarWidgetShapeStyle {
    WorkspaceSidebarWidgetShapeStyle(source: .active(state.step))
}

func workspaceSidebarWidgetBorder(_ state: GeistBorderState) -> WorkspaceSidebarWidgetShapeStyle {
    WorkspaceSidebarWidgetShapeStyle(source: .active(state.step))
}

func workspaceSidebarWidgetHighContrastBackground(
    _ state: GeistHighContrastState
) -> WorkspaceSidebarWidgetShapeStyle {
    WorkspaceSidebarWidgetShapeStyle(source: .active(state.step))
}

func workspaceSidebarWidgetColor(_ step: GeistColorStep) -> WorkspaceSidebarWidgetShapeStyle {
    WorkspaceSidebarWidgetShapeStyle(source: .active(step))
}

func workspaceSidebarWidgetSemanticColor(
    _ family: WorkspaceSidebarProjectThemeFamily,
    _ step: GeistColorStep
) -> WorkspaceSidebarWidgetShapeStyle {
    WorkspaceSidebarWidgetShapeStyle(source: .semantic(family, step))
}

private func circularHueDistance(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat {
    let distance = abs(lhs - rhs)
    return min(distance, 1 - distance)
}

@MainActor
extension TrayMenuModel {
    func projectPalette(workspaceName: String? = nil, colorScheme: ColorScheme? = nil) -> WinMuxOverlayPalette {
        let projectId = workspaceName.flatMap { name in
            workspaceSidebarWorkspaces.first { $0.name == name }?.projectId
        } ?? workspaceSidebarActiveProjectId
        return WinMuxOverlayPalette(
            theme: colorScheme.map(AppearanceTheme.init(colorScheme:)) ?? .current,
            projectThemeFamily: workspaceSidebarProjectThemeFamily(
                projects: workspaceSidebarProjects,
                activeProjectId: projectId
            )
        )
    }
}
