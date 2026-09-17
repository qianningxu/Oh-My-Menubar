import CoreGraphics
import Foundation
import SwiftUI

public let sidebarWidgetAPIVersion = 1

public struct SidebarWidgetContext: Sendable {
    public let id: String
    public let sectionWidth: CGFloat
    public let isCompact: Bool

    public init(id: String, sectionWidth: CGFloat, isCompact: Bool) {
        self.id = id
        self.sectionWidth = sectionWidth
        self.isCompact = isCompact
    }
}

public protocol SidebarWidgetPlugin: AnyObject {
    var apiVersion: Int { get }

    @MainActor
    func makeView(context: SidebarWidgetContext) -> AnyView
}
