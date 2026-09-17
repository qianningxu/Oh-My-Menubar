@testable import AppBundle
import AppKit
import XCTest

@MainActor
final class ExposeThumbnailCaptureTest: XCTestCase {
    func testCaptureWorkRunsOffMainActor() async throws {
        let probe = ExposeThumbnailCaptureProbe(images: [try makeImage(width: 5)])
        let coordinator = ExposeThumbnailCaptureCoordinator(capture: probe.capture)

        let thumbnail = await coordinator.thumbnail(for: 1)

        XCTAssertEqual(thumbnail?.width, 5)
        XCTAssertFalse(probe.didCaptureOnMainThread)
    }

    func testFailedFreshCaptureFallsBackToCachedThumbnail() async throws {
        let probe = ExposeThumbnailCaptureProbe(images: [try makeImage(width: 7), nil])
        let coordinator = ExposeThumbnailCaptureCoordinator(capture: probe.capture)

        let fresh = await coordinator.thumbnail(for: 1)
        let fallback = await coordinator.thumbnail(for: 1)

        XCTAssertNotNil(fresh)
        XCTAssertTrue(fresh === fallback)
        let didFinishRevalidation = await waitUntil {
            probe.completedCaptureCount == 2 && coordinator.pendingCaptureCount == 0
        }
        XCTAssertTrue(didFinishRevalidation)
        XCTAssertTrue(fresh === coordinator.cachedThumbnail(for: 1))
    }

    func testCachedThumbnailReturnsWithoutWaitingForRevalidation() async throws {
        let probe = ExposeThumbnailCaptureProbe(
            images: [try makeImage(width: 7), try makeImage(width: 11)],
            blocksSecondCapture: true
        )
        defer { probe.releaseCaptures() }
        let coordinator = ExposeThumbnailCaptureCoordinator(capture: probe.capture)
        let initial = await coordinator.thumbnail(for: 1)
        var returnedThumbnail: CGImage?
        var didReturn = false

        let readTask = Task { @MainActor in
            returnedThumbnail = await coordinator.thumbnail(for: 1)
            didReturn = true
        }
        let didStartRevalidation = await waitUntil { probe.captureCount == 2 }
        let didReturnWhileRevalidationBlocked = await waitUntil { didReturn }

        XCTAssertTrue(didStartRevalidation)
        XCTAssertTrue(didReturnWhileRevalidationBlocked)
        XCTAssertTrue(initial === returnedThumbnail)
        probe.releaseCaptures()
        await readTask.value
        let didPublishRevalidation = await waitUntil {
            coordinator.cachedThumbnail(for: 1)?.width == 11
        }
        XCTAssertTrue(didPublishRevalidation)
    }

    func testRevalidatedThumbnailWaitsForAndReturnsFreshCapture() async throws {
        let probe = ExposeThumbnailCaptureProbe(
            images: [try makeImage(width: 7), try makeImage(width: 11)],
            blocksSecondCapture: true
        )
        defer { probe.releaseCaptures() }
        let coordinator = ExposeThumbnailCaptureCoordinator(capture: probe.capture)
        let initial = await coordinator.thumbnail(for: 1)
        var didReturn = false
        let refreshTask = Task { @MainActor in
            let refreshed = await coordinator.revalidatedThumbnail(for: 1)
            didReturn = true
            return refreshed
        }

        let didStartRevalidation = await waitUntil { probe.captureCount == 2 }
        XCTAssertTrue(didStartRevalidation)
        XCTAssertFalse(didReturn)
        XCTAssertEqual(initial?.width, 7)

        probe.releaseCaptures()
        let refreshed = await refreshTask.value

        XCTAssertEqual(refreshed?.width, 11)
        XCTAssertEqual(coordinator.cachedThumbnail(for: 1)?.width, 11)
    }

    func testInvalidatedCaptureCannotOverwriteANewerResult() async throws {
        let probe = ExposeThumbnailCaptureProbe(
            images: [try makeImage(width: 2), try makeImage(width: 9)],
            blocksFirstCapture: true
        )
        defer { probe.releaseCaptures(2) }
        let coordinator = ExposeThumbnailCaptureCoordinator(
            maxConcurrentCaptures: 2,
            capture: probe.capture
        )

        XCTAssertTrue(coordinator.scheduleRefresh(for: 42))
        let didStartFirstCapture = await waitUntil { probe.captureCount == 1 }
        XCTAssertTrue(didStartFirstCapture)
        coordinator.invalidatePendingCaptures()
        XCTAssertTrue(coordinator.scheduleRefresh(for: 42))
        let didCacheNewerCapture = await waitUntil {
            coordinator.cachedThumbnail(for: 42)?.width == 9
        }
        XCTAssertTrue(didCacheNewerCapture)

        probe.releaseCaptures()
        let didCompleteBothCaptures = await waitUntil { probe.completedCaptureCount == 2 }
        XCTAssertTrue(didCompleteBothCaptures)
        try? await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(coordinator.cachedThumbnail(for: 42)?.width, 9)
    }

    func testPendingAndConcurrentCaptureWorkAreBounded() async throws {
        let probe = ExposeThumbnailCaptureProbe(
            images: [
                try makeImage(width: 1),
                try makeImage(width: 2),
                try makeImage(width: 3),
            ],
            blocksAllCaptures: true
        )
        defer { probe.releaseCaptures(4) }
        let coordinator = ExposeThumbnailCaptureCoordinator(
            maxPendingCaptures: 3,
            maxConcurrentCaptures: 2,
            capture: probe.capture
        )

        XCTAssertTrue(coordinator.scheduleRefresh(for: 1))
        XCTAssertTrue(coordinator.scheduleRefresh(for: 2))
        XCTAssertTrue(coordinator.scheduleRefresh(for: 3))
        XCTAssertFalse(coordinator.scheduleRefresh(for: 4))
        XCTAssertEqual(coordinator.pendingCaptureCount, 3)
        let didFillConcurrencyLimit = await waitUntil { probe.captureCount == 2 }
        XCTAssertTrue(didFillConcurrencyLimit)
        XCTAssertEqual(probe.maxConcurrentCaptureCount, 2)

        probe.releaseCaptures(3)
        let didDrainCaptures = await waitUntil {
            probe.completedCaptureCount == 3 && coordinator.pendingCaptureCount == 0
        }
        XCTAssertTrue(didDrainCaptures)
        XCTAssertEqual(probe.maxConcurrentCaptureCount, 2)
        XCTAssertNil(coordinator.cachedThumbnail(for: 4))
    }

    private func waitUntil(_ predicate: @MainActor () -> Bool) async -> Bool {
        for _ in 0 ..< 1_000 {
            if predicate() {
                return true
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }

    private func makeImage(width: Int) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ))
        context.setFillColor(NSColor.systemRed.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: 2))
        return try XCTUnwrap(context.makeImage())
    }
}

private final class ExposeThumbnailCaptureProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private let images: [CGImage?]
    private let blocksFirstCapture: Bool
    private let blocksSecondCapture: Bool
    private let blocksAllCaptures: Bool
    private var _captureCount = 0
    private var _completedCaptureCount = 0
    private var activeCaptureCount = 0
    private var _maxConcurrentCaptureCount = 0
    private var _didCaptureOnMainThread = false

    init(
        images: [CGImage?],
        blocksFirstCapture: Bool = false,
        blocksSecondCapture: Bool = false,
        blocksAllCaptures: Bool = false
    ) {
        self.images = images
        self.blocksFirstCapture = blocksFirstCapture
        self.blocksSecondCapture = blocksSecondCapture
        self.blocksAllCaptures = blocksAllCaptures
    }

    var captureCount: Int {
        withLock { _captureCount }
    }

    var completedCaptureCount: Int {
        withLock { _completedCaptureCount }
    }

    var maxConcurrentCaptureCount: Int {
        withLock { _maxConcurrentCaptureCount }
    }

    var didCaptureOnMainThread: Bool {
        withLock { _didCaptureOnMainThread }
    }

    func capture(windowId _: UInt32) -> CGImage? {
        lock.lock()
        let index = _captureCount
        _captureCount += 1
        activeCaptureCount += 1
        _maxConcurrentCaptureCount = max(_maxConcurrentCaptureCount, activeCaptureCount)
        _didCaptureOnMainThread = _didCaptureOnMainThread || Thread.isMainThread
        lock.unlock()

        if blocksAllCaptures || (blocksFirstCapture && index == 0) || (blocksSecondCapture && index == 1) {
            gate.wait()
        }

        lock.lock()
        activeCaptureCount -= 1
        _completedCaptureCount += 1
        lock.unlock()
        return images.indices.contains(index) ? images[index] : nil
    }

    func releaseCaptures(_ count: Int = 1) {
        for _ in 0 ..< count {
            gate.signal()
        }
    }

    private func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}
