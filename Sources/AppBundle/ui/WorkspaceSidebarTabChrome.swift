import SwiftUI

enum WorkspaceSidebarTabRowBorderRole: Equatable {
    case color4
    case color5
    case color6
}

private extension WorkspaceSidebarTabRowBorderRole {
    var geistState: GeistBorderState {
        switch self {
            case .color4: .normal
            case .color5: .hover
            case .color6: .active
        }
    }
}

func workspaceSidebarTabRowBorderRole(
    isSelected: Bool,
    isHovered: Bool,
    isActiveInteraction: Bool
) -> WorkspaceSidebarTabRowBorderRole? {
    if isActiveInteraction { return .color6 }
    if isHovered { return .color5 }
    if isSelected { return .color4 }
    return nil
}

private struct WorkspaceSidebarTabRowIsPressedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    fileprivate var workspaceSidebarTabRowIsPressed: Bool {
        get { self[WorkspaceSidebarTabRowIsPressedKey.self] }
        set { self[WorkspaceSidebarTabRowIsPressedKey.self] = newValue }
    }
}

struct WorkspaceSidebarTabRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.workspaceSidebarTabRowIsPressed, configuration.isPressed)
    }
}

private struct WorkspaceSidebarTabRowChrome: ViewModifier {
    let palette: WinMuxOverlayPalette
    let isSelected: Bool
    let isHovered: Bool
    let isActiveInteraction: Bool
    let cornerRadius: CGFloat

    @Environment(\.workspaceSidebarTabRowIsPressed) private var isPressed

    private var borderRole: WorkspaceSidebarTabRowBorderRole? {
        workspaceSidebarTabRowBorderRole(
            isSelected: isSelected,
            isHovered: isHovered,
            isActiveInteraction: isActiveInteraction || isPressed
        )
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .background {
                shape.fill(backgroundFill)
            }
            .overlay {
                if let borderRole {
                    shape.strokeBorder(
                        palette.geistBorder(borderRole.geistState),
                        lineWidth: borderRole == .color6 ? 0.95 : 0.75
                    )
                }
            }
    }

    private var backgroundFill: Color {
        if isActiveInteraction || isPressed || isHovered || isSelected {
            return palette.geistBackground(.primary)
        }
        return WinMuxDesignTokens.transparent
    }
}

extension View {
    func workspaceSidebarTabRowChrome(
        _ palette: WinMuxOverlayPalette,
        isSelected: Bool,
        isHovered: Bool,
        isActiveInteraction: Bool = false,
        cornerRadius: CGFloat = workspaceSidebarRowCornerRadius
    ) -> some View {
        modifier(WorkspaceSidebarTabRowChrome(
            palette: palette,
            isSelected: isSelected,
            isHovered: isHovered,
            isActiveInteraction: isActiveInteraction,
            cornerRadius: cornerRadius
        ))
    }

    func workspaceSidebarIconStroke(
        _ palette: WinMuxOverlayPalette,
        cornerRadius: CGFloat = 4,
        isActive: Bool = false
    ) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(palette.geistBorder(isActive ? .active : .normal), lineWidth: 0.65)
        }
    }
}
