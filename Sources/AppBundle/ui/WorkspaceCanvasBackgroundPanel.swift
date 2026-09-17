import SwiftUI

// The project frame panel was intentionally removed. Resize previews still use
// the selected project's canvas color so their gap shading matches the project.
func workspaceCanvasProjectThemeFamily(
    activeProjectId: WorkspaceProjectId,
    projectColors: [String: String]
) -> WorkspaceSidebarProjectThemeFamily? {
    WorkspaceSidebarProjectThemeFamily.resolve(
        configuredHex: projectColors[activeProjectId.rawValue]
    )
}

func workspaceCanvasBackground(for palette: WinMuxOverlayPalette) -> Color {
    palette.color(palette.activeGeistFamily, .color1)
}
