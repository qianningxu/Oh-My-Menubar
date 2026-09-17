import AppKit

extension WorkspaceSidebarPanel {
    func installMenuTrackingObservers() {
        let center = NotificationCenter.default
        menuTrackingObservers = [
            center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.beginMenuTrackingIfNeeded() }
            },
            center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.endMenuTrackingIfNeeded() }
            },
        ]
    }

    func removeMenuTrackingObservers() {
        for observer in menuTrackingObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        menuTrackingObservers = []
    }

    func beginMenuTrackingIfNeeded() {
        guard isVisible,
              viewModel.workspaceSidebarVisibleWidth > 0,
              isMouseInsideVisibleRegion()
        else { return }
        menuTrackingDepth += 1
        menuTrackingGraceUntil = .distantFuture
    }

    func endMenuTrackingIfNeeded() {
        guard menuTrackingDepth > 0 else { return }
        menuTrackingDepth -= 1
        guard menuTrackingDepth == 0 else { return }
        menuTrackingGraceUntil = Date().addingTimeInterval(menuTrackingEndGrace)
        scheduleHoverStateUpdate(at: Date().addingTimeInterval(0.08))
        scheduleHoverStateUpdate(at: menuTrackingGraceUntil)
    }

    func isMenuTrackingOrInGracePeriod(now: Date = .now) -> Bool {
        menuTrackingDepth > 0 || now < menuTrackingGraceUntil
    }
}
