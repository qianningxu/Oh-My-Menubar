import AppKit
import SwiftUI

enum WindowIntentPreviewPalette {
    static let gridBaseFill = winMuxOverlayColor(.blue, .color1)
    static let gridLineStroke = winMuxOverlayColor(.blue, .color5)
    static let gridOuterStroke = winMuxOverlayColor(.blue, .color5)

    static func gridZoneFill(isActive: Bool) -> Color {
        winMuxOverlayColor(.blue, isActive ? .color3 : .color1)
    }

    static func gridSymbol(isActive: Bool) -> Color {
        winMuxOverlayContent(isActive ? .primary : .secondary)
    }
}
