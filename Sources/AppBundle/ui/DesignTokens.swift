import AppKit
import CoreGraphics
import SwiftUI

/// The smallest visual rhythm unit used by WinMux surfaces.
///
/// Layout code must express spacing as a multiple of this value so the
/// interface can be retuned coherently without hunting for numeric literals.
enum WinMuxDesignTokens {
    static let standardGap: CGFloat = 4
    static let transparent: Color = Color.clear
    static let transparentNSColor: NSColor = NSColor.clear
    static let mask = Color.black
    static let projectFrameTintOpacity = 1.0
}

let standardGap = WinMuxDesignTokens.standardGap

/// Named spacing roles derived from the four-point base rhythm.
///
/// Prefer these over ad-hoc multipliers in view code. The names describe the
/// intended visual density, while every value remains a standard-gap multiple.
enum WinMuxSpacing {
    static let none: CGFloat = standardGap * 0
    static let hairline: CGFloat = standardGap * 0.5
    static let compact: CGFloat = standardGap
    static let comfortable: CGFloat = standardGap * 1.5
    static let regular: CGFloat = standardGap * 2
    static let section: CGFloat = standardGap * 3
    static let panel: CGFloat = standardGap * 4
    static let page: CGFloat = standardGap * 6
}
