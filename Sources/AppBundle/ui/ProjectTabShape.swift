import SwiftUI

struct ProjectTabShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(WinMuxBarStyle.cornerRadius, rect.height / 2)
        // Continue the selection through the bar’s bottom content padding.
        let bottom = rect.maxY + WinMuxBarStyle.topBarContentInset
        var p = Path()
        p.move(to: CGPoint(x: -r, y: bottom))
        p.addQuadCurve(to: CGPoint(x: 0, y: bottom - r), control: CGPoint(x: 0, y: bottom))
        p.addLine(to: CGPoint(x: 0, y: r))
        p.addQuadCurve(to: CGPoint(x: r, y: 0), control: .zero)
        p.addLine(to: CGPoint(x: rect.maxX - r, y: 0))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: r), control: CGPoint(x: rect.maxX, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX, y: bottom - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX + r, y: bottom), control: CGPoint(x: rect.maxX, y: bottom))
        p.closeSubpath()
        return p
    }
}
