import AppKit
import SwiftUI

let mattePanelNSColor = WinMuxOverlayPalette.adaptiveNSColor { $0.geistBackgroundNSColor(.primary) }
let mattePanelFill = WinMuxOverlayPalette.adaptiveColor { $0.geistBackgroundNSColor(.primary) }
let mattePanelBorder = mattePanelFill
let mattePanelInsetShadow = WinMuxOverlayPalette.adaptiveColor { $0.geistBorderNSColor(.normal) }
let mattePanelSeparatorNSColor = WinMuxOverlayPalette.adaptiveNSColor { $0.geistBorderNSColor(.normal) }
let mattePanelSeparator = WinMuxOverlayPalette.adaptiveColor { $0.geistBorderNSColor(.normal) }
