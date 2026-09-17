import SwiftUI

struct WorkspaceSidebarDropdownControlStyle: ViewModifier {
    let isActive: Bool
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.workspaceSidebarProjectThemeFamily) private var projectThemeFamily

    private var palette: WinMuxOverlayPalette {
        WinMuxOverlayPalette(colorScheme: colorScheme, projectThemeFamily: projectThemeFamily)
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, workspaceSidebarDropdownPadding)
            .frame(height: workspaceSidebarDropdownHeight)
            .background {
                RoundedRectangle(cornerRadius: workspaceSidebarDropdownCornerRadius, style: .continuous)
                    .fill(controlFill)
                    .overlay {
                        if isHovered || isActive {
                        RoundedRectangle(cornerRadius: workspaceSidebarDropdownCornerRadius, style: .continuous)
                            .strokeBorder(controlStroke, lineWidth: isActive ? 0.8 : 0.65)
                        }
                    }
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var controlFill: Color {
        if isActive {
            return palette.componentBackground(.active)
        }
        return isHovered ? palette.componentBackground(.hover) : WinMuxDesignTokens.transparent
    }

    private var controlStroke: Color {
        if isActive {
            return palette.geistBorder(.active)
        }
        return palette.geistBorder(.hover)
    }
}

struct WorkspaceSidebarDropdownMenuRowStyle: ViewModifier {
    let isSelected: Bool
    var rowHeight: CGFloat = workspaceSidebarDropdownHeight
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.workspaceSidebarProjectThemeFamily) private var projectThemeFamily

    private var palette: WinMuxOverlayPalette {
        WinMuxOverlayPalette(colorScheme: colorScheme, projectThemeFamily: projectThemeFamily)
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, workspaceSidebarDropdownPadding)
            .frame(height: rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: workspaceSidebarRowCornerRadius, style: .continuous)
                    .fill(rowFill)
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }
            .animation(.easeOut(duration: 0.10), value: isHovered)
    }

    private var rowFill: Color {
        if isSelected {
            return palette.componentBackground(.active)
        }
        return isHovered ? palette.componentBackground(.hover) : WinMuxDesignTokens.transparent
    }
}

func checkmark(isVisible: Bool) -> some View {
    WorkspaceSidebarCheckmark(isVisible: isVisible)
}

private struct WorkspaceSidebarCheckmark: View {
    let isVisible: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.workspaceSidebarProjectThemeFamily) private var projectThemeFamily

    private var palette: WinMuxOverlayPalette {
        WinMuxOverlayPalette(colorScheme: colorScheme, projectThemeFamily: projectThemeFamily)
    }

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(isVisible ? palette.content(.primary) : WinMuxDesignTokens.transparent)
    }
}
