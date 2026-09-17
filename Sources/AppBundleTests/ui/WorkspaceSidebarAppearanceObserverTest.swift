@testable import AppBundle
import AppKit
import XCTest

final class WorkspaceSidebarAppearanceObserverTest: XCTestCase {
    @MainActor
    func testRefreshesWhenAppearanceChangesAndReturnsToSystem() async {
        let app = NSApplication.shared
        let originalAppearance = app.appearance
        defer { app.appearance = originalAppearance }
        app.appearance = nil
        let systemTheme = AppearanceTheme.current
        var refreshedThemes: [AppearanceTheme] = []
        let observer = WorkspaceSidebarAppearanceObserver {
            refreshedThemes.append(.current)
        }
        observer.startObserving()
        observer.startObserving()

        app.appearance = NSAppearance(named: systemTheme == .dark ? .aqua : .darkAqua)
        for _ in 0..<20 where refreshedThemes.isEmpty {
            await Task.yield()
        }
        XCTAssertEqual(refreshedThemes.last, systemTheme == .dark ? .light : .dark)

        refreshedThemes.removeAll()
        app.appearance = nil
        for _ in 0..<20 where refreshedThemes.isEmpty {
            await Task.yield()
        }
        XCTAssertEqual(refreshedThemes.last, systemTheme)
        withExtendedLifetime(observer) {}
    }
}
