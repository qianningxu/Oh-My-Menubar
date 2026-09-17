import AppKit

enum ResizePreviewPalette {
    static let shadeFillNSColor = NSColor.clear
    static let shadeStrokeNSColor = NSColor(calibratedWhite: 1, alpha: 1)

    static let fillNSColor = WinMuxOverlayPalette.adaptiveNSColor { $0.highContrastBackgroundNSColor(.normal) }
    static var fill: CGColor { fillNSColor.cgColor }

    static let strokeNSColor = WinMuxOverlayPalette.adaptiveNSColor {
        $0.geistBorderNSColor(.active)
    }
    static var stroke: CGColor { strokeNSColor.cgColor }

    static let tabGroupBarNSColor = WinMuxOverlayPalette.adaptiveNSColor {
        $0.componentBackgroundNSColor(.hover)
    }
    static var tabGroupBar: CGColor { tabGroupBarNSColor.cgColor }

    static let fallbackIconFillNSColor = WinMuxOverlayPalette.adaptiveNSColor {
        $0.componentBackgroundNSColor(.active)
    }
    static var fallbackIconFill: CGColor { fallbackIconFillNSColor.cgColor }

    static let sourceFrameFillNSColor = WinMuxOverlayPalette.adaptiveNSColor { $0.componentBackgroundNSColor(.hover) }
    static var sourceFrameFill: CGColor { sourceFrameFillNSColor.cgColor }

    static let sourceFrameStrokeNSColor = WinMuxOverlayPalette.adaptiveNSColor {
        $0.geistBorderNSColor(.normal)
    }
    static var sourceFrameStroke: CGColor { sourceFrameStrokeNSColor.cgColor }

    static let sourceMockTabFillNSColor = WinMuxOverlayPalette.adaptiveNSColor {
        $0.componentBackgroundNSColor(.normal)
    }
    static var sourceMockTabFill: CGColor { sourceMockTabFillNSColor.cgColor }

    static let sourceMockTabStrokeNSColor = WinMuxOverlayPalette.adaptiveNSColor {
        $0.geistBorderNSColor(.hover)
    }
    static var sourceMockTabStroke: CGColor { sourceMockTabStrokeNSColor.cgColor }

    static let fallbackTextNSColor = WinMuxOverlayPalette.adaptiveNSColor {
        $0.contentNSColor(.primary)
    }
    static var fallbackText: CGColor { fallbackTextNSColor.cgColor }
}
