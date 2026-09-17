@testable import AppBundle
import XCTest

@MainActor
final class TerminationPreparationCoordinatorTest: XCTestCase {
    func testRepliesAfterPreparationCompletes() async {
        var events: [String] = []
        let coordinator = TerminationPreparationCoordinator(
            timeoutNanoseconds: 50_000_000,
            prepare: {
                events.append("prepare")
            },
            reply: { shouldTerminate in
                events.append("reply \(shouldTerminate)")
            },
        )

        coordinator.start()
        try? await Task.sleep(nanoseconds: 10_000_000)

        assertEquals(events, ["prepare", "reply true"])
    }

    func testRepliesAfterTimeoutWhenPreparationIsSlow() async {
        var replyCount = 0
        var repliedShouldTerminate: Bool?
        let coordinator = TerminationPreparationCoordinator(
            timeoutNanoseconds: 5_000_000,
            prepare: {
                try? await Task.sleep(nanoseconds: 50_000_000)
            },
            reply: { shouldTerminate in
                replyCount += 1
                repliedShouldTerminate = shouldTerminate
            },
        )

        coordinator.start()
        try? await Task.sleep(nanoseconds: 30_000_000)

        assertEquals(replyCount, 1)
        assertEquals(repliedShouldTerminate, true)
    }

    func testTimeoutCancelsSlowPreparationTask() async {
        var didFinishPreparation = false
        var replyCount = 0
        let coordinator = TerminationPreparationCoordinator(
            timeoutNanoseconds: 5_000_000,
            prepare: {
                do {
                    try await Task.sleep(nanoseconds: 50_000_000)
                    didFinishPreparation = true
                } catch {}
            },
            reply: { _ in
                replyCount += 1
            },
        )

        coordinator.start()
        try? await Task.sleep(nanoseconds: 80_000_000)

        assertEquals(replyCount, 1)
        XCTAssertFalse(didFinishPreparation)
    }
}
