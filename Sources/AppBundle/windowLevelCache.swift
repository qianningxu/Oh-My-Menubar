import CoreGraphics
import Foundation

@MainActor
private let windowLevelCache = WindowLevelCache(loadInventory: copyWindowLevelInventory)

@MainActor
func getWindowLevel(for windowId: UInt32) async throws -> MacOsWindowLevel? {
    try await windowLevelCache.windowLevel(for: windowId)
}

@MainActor
final class WindowLevelCache {
    typealias Inventory = [UInt32: MacOsWindowLevel]
    typealias LoadInventory = @Sendable () -> Inventory?

    private struct InFlightLoad {
        let generation: UInt64
        let task: Task<Inventory?, Never>
        let completion: AwaitableOneTimeBroadcastLatch
    }

    private let loadInventory: LoadInventory
    private var cache: Inventory = [:]
    private var inFlightLoad: InFlightLoad?
    private var loadGeneration: UInt64 = 0

    init(loadInventory: @escaping LoadInventory) {
        self.loadInventory = loadInventory
    }

    func windowLevel(for windowId: UInt32) async throws -> MacOsWindowLevel? {
        try Task.checkCancellation()
        if let existing = cache[windowId] { return existing }

        let load = inFlightLoad ?? startLoad()
        try await load.completion.await()
        try Task.checkCancellation()
        return (await load.task.value)?[windowId]
    }

    private func startLoad() -> InFlightLoad {
        loadGeneration &+= 1
        let generation = loadGeneration
        let loadInventory = loadInventory
        let task = Task.detached(priority: .userInitiated) {
            loadInventory()
        }
        let completion = AwaitableOneTimeBroadcastLatch()
        let load = InFlightLoad(generation: generation, task: task, completion: completion)
        inFlightLoad = load

        Task { @MainActor [weak self] in
            let inventory = await task.value
            guard let self, self.inFlightLoad?.generation == generation else {
                await completion.signalToAll()
                return
            }
            self.inFlightLoad = nil
            if let inventory {
                self.cache = inventory
            }
            await completion.signalToAll()
        }
        return load
    }
}

private func copyWindowLevelInventory() -> WindowLevelCache.Inventory? {
    var result: [UInt32: MacOsWindowLevel] = [:]
    let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
    guard let windowInfos = CGWindowListCopyWindowInfo(options, CGWindowID(0)) as? [[String: Any]] else { return nil }
    for dict in windowInfos {

        guard let rawWindowLayer = dict[kCGWindowLayer as String] as? NSNumber else { continue }
        let windowLayer = rawWindowLayer.intValue

        guard let rawWindowId = dict[kCGWindowNumber as String] as? NSNumber else { continue }
        let windowId = rawWindowId.uint32Value

        result[windowId] = .new(windowLevel: windowLayer)
    }
    return result
}

enum MacOsWindowLevel: Sendable, Equatable {
    case normalWindow
    case alwaysOnTopWindow
    case unknown(windowLevel: Int)

    var isSystemOverlay: Bool {
        if case .unknown(let level) = self {
            return level >= Int(CGWindowLevelForKey(.screenSaverWindow))
        }
        return false
    }

    static func new(windowLevel: Int) -> MacOsWindowLevel {
        switch windowLevel {
            case 0: .normalWindow
            case 3: .alwaysOnTopWindow
            default: .unknown(windowLevel: windowLevel)
        }
    }

    static func fromJson(_ json: Json) -> MacOsWindowLevel? {
        switch json {
            case .string(let str) where str == "normalWindow": .normalWindow
            case .string(let str) where str == "alwaysOnTopWindow": .alwaysOnTopWindow
            case .int(let int): .new(windowLevel: int)
            default: nil
        }
    }

    func toJson() -> Json {
        switch self {
            case .normalWindow: .string("normalWindow")
            case .alwaysOnTopWindow: .string("alwaysOnTopWindow")
            case .unknown(let layerNumber): .int(layerNumber)
        }
    }
}

/// Native companion panels own their geometry and stacking, even when AX calls
/// them dialogs. Keep the main (normal-level) ChatGPT window managed.
func isNativeOverlayWindow(level: MacOsWindowLevel?, appId: KnownBundleId?) -> Bool {
    level?.isSystemOverlay == true ||
        ((appId == .chatgpt || appId == .codex) && level == .alwaysOnTopWindow)
}
