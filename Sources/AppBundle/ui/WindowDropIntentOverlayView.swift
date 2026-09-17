import SwiftUI

struct WindowDropIntentOverlayView: View {
    let model: WindowDropIntentOverlayModel

    @Environment(\.colorScheme) private var colorScheme

    private let borderLineWidth: CGFloat = 1
    @ObservedObject private var trayModel = TrayMenuModel.shared
    private var palette: WinMuxOverlayPalette { trayModel.projectPalette(colorScheme: colorScheme) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(gridBaseFill)

            ForEach(localZones) { zone in
                dropZoneView(zone)
            }

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(gridOuterStroke, lineWidth: borderLineWidth)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .frame(width: model.targetFrame.width, height: model.targetFrame.height)
        .compositingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var cornerRadius: CGFloat {
        model.cornerRadius ?? min(max(min(model.targetFrame.width, model.targetFrame.height) * 0.022, 12), 18)
    }

    private var localZones: [WindowIntentZone] {
        WindowIntentZoneBuilder.zones(in: Rect(
            topLeftX: 0,
            topLeftY: 0,
            width: model.targetFrame.width,
            height: model.targetFrame.height
        ))
    }

    private func dropZoneView(_ zone: WindowIntentZone) -> some View {
        let isActive = zone.zone == model.activeZone
        let rect = zone.frame
        return ZStack {
            RoundedRectangle(cornerRadius: zoneCornerRadius(for: rect), style: .continuous)
                .fill(isActive ? gridZoneFill : inactiveZoneFill)
                .overlay {
                    RoundedRectangle(cornerRadius: zoneCornerRadius(for: rect), style: .continuous)
                        .strokeBorder(isActive ? activeZoneStroke : inactiveZoneStroke, lineWidth: borderLineWidth)
                }
            if let name = symbolName(for: zone.zone)
            {
                Image(systemName: name)
                    .font(.system(size: iconSize(for: rect), weight: .semibold))
                    .foregroundStyle(isActive ? activeGridSymbol : gridSymbol)
            }
        }
        .padding(zoneInsets(for: zone.zone))
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.center.x, y: rect.center.y)
    }

    private func zoneInsets(for zone: WindowDropZone) -> EdgeInsets {
        let outer = WinMuxSpacing.section
        let inner = WinMuxSpacing.comfortable
        return switch zone {
            case .tab:
                EdgeInsets(top: outer, leading: outer, bottom: inner, trailing: outer)
            case .left:
                EdgeInsets(top: inner, leading: outer, bottom: outer, trailing: inner)
            case .right:
                EdgeInsets(top: inner, leading: inner, bottom: outer, trailing: outer)
            case .top, .middle:
                EdgeInsets(top: inner, leading: inner, bottom: inner, trailing: inner)
            case .bottom:
                EdgeInsets(top: inner, leading: inner, bottom: outer, trailing: inner)
        }
    }

    private func symbolName(for zone: WindowDropZone) -> String? {
        switch zone {
            case .left:
                "arrow.left"
            case .right:
                "arrow.right"
            case .top:
                "arrow.up"
            case .bottom:
                "arrow.down"
            case .middle:
                "arrow.left.arrow.right"
            case .tab:
                "rectangle.3.group"
        }
    }

    private func iconSize(for frame: Rect) -> CGFloat {
        min(max(min(frame.width, frame.height) * 0.45, 14), 48)
    }

    private var gridBaseFill: Color {
        // Use the low-intensity background scale across large areas;
        // high-contrast accents overwhelm the content beneath a drag preview.
        palette.color(palette.activeGeistFamily, .color1).opacity(0.65)
    }

    private var gridOuterStroke: Color {
        palette.geistBorder(.normal)
    }

    private var gridZoneFill: Color {
        palette.componentBackground(.active).opacity(0.85)
    }

    private var inactiveZoneFill: Color {
        palette.componentBackground(.hover).opacity(0.30)
    }

    private var inactiveZoneStroke: Color {
        palette.geistBorder(.normal).opacity(0.75)
    }

    private var activeZoneStroke: Color {
        palette.geistBorder(.active)
    }

    private var gridSymbol: Color {
        palette.content(.secondary)
    }

    private var activeGridSymbol: Color {
        palette.content(.primary)
    }

    private func zoneCornerRadius(for frame: Rect) -> CGFloat {
        return min(max(min(frame.width, frame.height) * 0.06, 8), 14)
    }
}
