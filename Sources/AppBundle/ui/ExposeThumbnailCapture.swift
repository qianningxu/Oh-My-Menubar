import AppKit

private let exposeThumbnailCacheLimit = 64
private let exposeThumbnailMaxPendingCaptures = 64
let exposeThumbnailMaxConcurrentCaptures = 2

private actor ExposeThumbnailCaptureLimiter {
    private var availablePermits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        precondition(limit > 0)
        availablePermits = limit
    }

    func acquire() async {
        if availablePermits > 0 {
            availablePermits -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            availablePermits += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

@MainActor
final class ExposeThumbnailCaptureCoordinator {
    typealias Capture = @Sendable (UInt32) -> CGImage?

    private struct Request {
        let generation: UInt64
        let task: Task<CGImage?, Never>
    }

    private let cacheLimit: Int
    private let maxPendingCaptures: Int
    private let limiter: ExposeThumbnailCaptureLimiter
    private let capture: Capture
    private var cache: [UInt32: CGImage] = [:]
    private var cacheOrder: [UInt32] = []
    private var requests: [UInt32: Request] = [:]
    private var nextGeneration: UInt64 = 0

    init(
        cacheLimit: Int = exposeThumbnailCacheLimit,
        maxPendingCaptures: Int = exposeThumbnailMaxPendingCaptures,
        maxConcurrentCaptures: Int = exposeThumbnailMaxConcurrentCaptures,
        capture: @escaping Capture
    ) {
        precondition(cacheLimit > 0)
        precondition(maxPendingCaptures > 0)
        precondition(maxConcurrentCaptures > 0)
        self.cacheLimit = cacheLimit
        self.maxPendingCaptures = maxPendingCaptures
        limiter = ExposeThumbnailCaptureLimiter(limit: maxConcurrentCaptures)
        self.capture = capture
    }

    func thumbnail(for windowId: UInt32) async -> CGImage? {
        guard !Task.isCancelled else { return cache[windowId] }
        if let cachedThumbnail = cache[windowId] {
            scheduleRefresh(for: windowId)
            return cachedThumbnail
        }
        return await revalidatedThumbnail(for: windowId)
    }

    func revalidatedThumbnail(for windowId: UInt32) async -> CGImage? {
        guard !Task.isCancelled else { return cache[windowId] }
        guard let request = beginCapture(for: windowId) else {
            return cache[windowId]
        }
        let freshThumbnail = await request.task.value
        return finishCapture(freshThumbnail, for: windowId, generation: request.generation)
    }

    @discardableResult
    func scheduleRefresh(for windowId: UInt32) -> Bool {
        beginCapture(for: windowId) != nil
    }

    func cachedThumbnail(for windowId: UInt32) -> CGImage? {
        cache[windowId]
    }

    var pendingCaptureCount: Int {
        requests.count
    }

    func invalidatePendingCaptures(clearCache: Bool = false) {
        for request in requests.values {
            request.task.cancel()
        }
        requests = [:]
        if clearCache {
            cache = [:]
            cacheOrder = []
        }
    }

    private func beginCapture(for windowId: UInt32) -> Request? {
        if let request = requests[windowId] {
            return request
        }
        guard requests.count < maxPendingCaptures else { return nil }

        nextGeneration &+= 1
        let generation = nextGeneration
        let limiter = limiter
        let capture = capture
        let task: Task<CGImage?, Never> = Task.detached(priority: .utility) {
            await limiter.acquire()
            guard !Task.isCancelled else {
                await limiter.release()
                return nil
            }
            let thumbnail = capture(windowId)
            await limiter.release()
            return thumbnail
        }
        let request = Request(generation: generation, task: task)
        requests[windowId] = request

        Task { @MainActor [weak self] in
            let freshThumbnail = await task.value
            self?.finishCapture(freshThumbnail, for: windowId, generation: generation)
        }
        return request
    }

    @discardableResult
    private func finishCapture(_ cgImage: CGImage?, for windowId: UInt32, generation: UInt64) -> CGImage? {
        guard requests[windowId]?.generation == generation else {
            return cache[windowId]
        }
        requests.removeValue(forKey: windowId)
        guard let cgImage else { return cache[windowId] }

        remember(cgImage, for: windowId)
        return cgImage
    }

    private func remember(_ thumbnail: CGImage, for windowId: UInt32) {
        cache[windowId] = thumbnail
        cacheOrder.removeAll { $0 == windowId }
        cacheOrder.append(windowId)
        while cacheOrder.count > cacheLimit {
            let expired = cacheOrder.removeFirst()
            cache.removeValue(forKey: expired)
        }
    }
}

@MainActor private let exposeThumbnailCaptures = ExposeThumbnailCaptureCoordinator(
    capture: { windowId in captureFreshExposeThumbnail(windowId) }
)

@MainActor
func captureExposeThumbnail(_ windowId: UInt32) async -> CGImage? {
    await exposeThumbnailCaptures.thumbnail(for: windowId)
}

@MainActor
func cachedExposeThumbnail(_ windowId: UInt32) -> CGImage? {
    exposeThumbnailCaptures.cachedThumbnail(for: windowId)
}

@MainActor
func captureRevalidatedExposeThumbnail(_ windowId: UInt32) async -> CGImage? {
    await exposeThumbnailCaptures.revalidatedThumbnail(for: windowId)
}

@MainActor
func refreshExposeThumbnailCache(_ windowId: UInt32) {
    exposeThumbnailCaptures.scheduleRefresh(for: windowId)
}

private func captureFreshExposeThumbnail(_ windowId: UInt32) -> CGImage? {
    guard let cgImage = CGWindowListCreateImage(
        .null,
        .optionIncludingWindow,
        CGWindowID(windowId),
        [.boundsIgnoreFraming, .nominalResolution]
    ) else {
        return nil
    }
    return isLikelyBlankWindowThumbnail(cgImage) ? nil : cgImage
}

func isLikelyBlankWindowThumbnail(_ image: CGImage, sampleGrid: Int = 18) -> Bool {
    let bitmap = NSBitmapImageRep(cgImage: image)
    let width = bitmap.pixelsWide
    let height = bitmap.pixelsHigh
    let grid = max(3, min(sampleGrid, width, height))
    guard width > 1, height > 1 else { return true }

    var sampleCount = 0
    var minLuminance = CGFloat.greatestFiniteMagnitude
    var maxLuminance = CGFloat.leastNormalMagnitude
    var maxChannelSpread: CGFloat = 0

    for yIndex in 0 ..< grid {
        let y = Int(round(CGFloat(yIndex) * CGFloat(height - 1) / CGFloat(grid - 1)))
        for xIndex in 0 ..< grid {
            let x = Int(round(CGFloat(xIndex) * CGFloat(width - 1) / CGFloat(grid - 1)))
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                  color.alphaComponent > 0.05
            else {
                continue
            }

            let red = color.redComponent
            let green = color.greenComponent
            let blue = color.blueComponent
            let luminance = red * 0.2126 + green * 0.7152 + blue * 0.0722
            minLuminance = min(minLuminance, luminance)
            maxLuminance = max(maxLuminance, luminance)
            maxChannelSpread = max(maxChannelSpread, max(red, green, blue) - min(red, green, blue))
            sampleCount += 1
        }
    }

    guard sampleCount >= grid * grid / 2 else { return true }
    return (maxLuminance - minLuminance) < 0.035 && maxChannelSpread < 0.035
}
