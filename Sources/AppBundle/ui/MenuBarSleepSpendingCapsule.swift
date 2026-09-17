import SwiftUI

struct MenuBarSleepSpendingCapsule: View {
    let height: CGFloat

    var body: some View {
        TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 60)) { context in
            if Int(floor(context.date.timeIntervalSinceReferenceDate / 60)).isMultiple(of: 2) {
                MenuBarSleepCapsule(height: height)
            } else {
                MenuBarSpendingCapsule(height: height)
            }
        }
    }
}
