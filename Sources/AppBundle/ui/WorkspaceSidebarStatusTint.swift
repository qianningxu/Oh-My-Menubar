import SwiftUI

extension WorkspaceSidebarBatterySnapshot {
    var tintColor: Color {
        switch state {
            case .charging:
                return winMuxOverlayColor(.green, .color9)
            case .ac:
                return winMuxOverlayColor(.green, .color9)
            case .discharging:
                return winMuxOverlayColor(.amber, .color9)
            case .unavailable:
                return winMuxOverlayContent(.secondary)
        }
    }
}

extension WorkspaceSidebarAudioSnapshot {
    var tintColor: Color {
        isMuted ? winMuxOverlayContent(.secondary) : winMuxOverlayColor(.green, .color9)
    }
}

extension WorkspaceSidebarNetworkSnapshot {
    var tintColor: Color {
        interfaceName == nil ? winMuxOverlayContent(.secondary) : winMuxOverlayColor(.blue, .color9)
    }
}
