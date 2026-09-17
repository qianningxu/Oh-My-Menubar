import Common
import Foundation

private let persistedFrozenWorldVersion = 1
private let persistedSidebarStateVersion = 2
private let persistedFrozenWorldFilename = "window-state.json"
private let persistedSidebarStateFilename = "sidebar-state.json"
@MainActor private var pendingPersistedFrozenWorld: FrozenWorld? = nil
@MainActor private var didRestorePersistedFrozenWorldDuringCurrentSession = false
@MainActor private var pendingPersistedSidebarState: FrozenSidebarState? = nil
@MainActor private var didRestorePersistedSidebarStateDuringCurrentSession = false
@MainActor private var didLoadPersistedSidebarStateDuringCurrentSession = false
@MainActor private var isPersistedSidebarStateReady = false
@MainActor private var isSidebarStatePersistenceScheduled = false
@MainActor private var restartStatePersistenceGeneration: UInt64 = 0
@MainActor private var persistedStateDirectory: URL?

private struct PersistedFrozenWorldEnvelope: Codable, Sendable {
    let version: Int
    let world: FrozenWorld
}

private struct PersistedSidebarStateEnvelope: Codable, Sendable {
    let version: Int
    let sidebar: FrozenSidebarState
}

private enum PendingFrozenWorldWrite: Sendable {
    case snapshot(FrozenWorld)
    case remove
}

private struct PendingSidebarWrite: Sendable {
    let generation: UInt64
    let state: FrozenSidebarState
    let url: URL
}

private struct PendingWorldWrite: Sendable {
    let generation: UInt64
    let write: PendingFrozenWorldWrite
    let url: URL
}

/// Performs persistence away from the main actor while keeping the newest
/// snapshot for each file.  Actor isolation serializes atomic replacements so
/// an older, slower write can never finish after a newer write and overwrite it.
private actor RestartStatePersistenceWriter {
    private var pendingSidebar: PendingSidebarWrite?
    private var pendingWorld: PendingWorldWrite?
    private var newestSidebarGeneration: UInt64 = 0
    private var newestWorldGeneration: UInt64 = 0
    private var isDraining = false
    private var flushWaiters: [CheckedContinuation<Void, Never>] = []

    func enqueue(
        sidebar: PendingSidebarWrite?,
        world: PendingWorldWrite?,
    ) {
        if let sidebar,
           sidebar.generation >= newestSidebarGeneration
        {
            pendingSidebar = sidebar
            newestSidebarGeneration = sidebar.generation
        }
        if let world,
           world.generation >= newestWorldGeneration
        {
            pendingWorld = world
            newestWorldGeneration = world.generation
        }
        startDrainIfNeeded()
    }

    func flush() async {
        guard isDraining || pendingSidebar != nil || pendingWorld != nil else { return }
        await withCheckedContinuation { continuation in
            flushWaiters.append(continuation)
            startDrainIfNeeded()
        }
    }

    private func startDrainIfNeeded() {
        guard !isDraining, pendingSidebar != nil || pendingWorld != nil else { return }
        isDraining = true
        Task { drain() }
    }

    private func drain() {
        while pendingSidebar != nil || pendingWorld != nil {
            let sidebar = pendingSidebar
            let world = pendingWorld
            pendingSidebar = nil
            pendingWorld = nil

            // Write the durable sidebar copy first.  The world snapshot embeds
            // a fallback sidebar, so this ordering favors the newest metadata.
            if let sidebar {
                writeSidebar(sidebar.state, url: sidebar.url)
            }
            if let world {
                writeWorld(world.write, url: world.url)
            }
        }

        isDraining = false
        let waiters = flushWaiters
        flushWaiters.removeAll(keepingCapacity: true)
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func writeSidebar(_ sidebar: FrozenSidebarState, url: URL) {
        do {
            let data = try persistenceData(
                PersistedSidebarStateEnvelope(version: persistedSidebarStateVersion, sidebar: sidebar),
            )
            try data.write(to: url, options: .atomic)
        } catch {
            // Restart persistence is best effort and must never interrupt UI.
        }
    }

    private func writeWorld(_ write: PendingFrozenWorldWrite, url: URL) {
        do {
            switch write {
                case .remove:
                    try? FileManager.default.removeItem(at: url)
                case .snapshot(let world):
                    let data = try persistenceData(
                        PersistedFrozenWorldEnvelope(version: persistedFrozenWorldVersion, world: world),
                    )
                    try data.write(to: url, options: .atomic)
            }
        } catch {
            // Restart persistence is best effort and must never interrupt quit.
        }
    }
}

private let restartStatePersistenceWriter = RestartStatePersistenceWriter()

private func persistenceData<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    // Pretty-printing is useful for diagnostics but needlessly increases the
    // encode and atomic-write cost for these frequently updated snapshots.
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
}

@MainActor
private func persistedStateDirectoryUrl() throws -> URL {
    if let persistedStateDirectory {
        return persistedStateDirectory
    }
    let appSupport = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true,
    )
    let directory = appSupport.appendingPathComponent(winMuxAppName, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    persistedStateDirectory = directory
    return directory
}

@MainActor
private func persistedFrozenWorldUrl() throws -> URL {
    try persistedStateDirectoryUrl()
        .appendingPathComponent(persistedFrozenWorldFilename, isDirectory: false)
}

@MainActor
private func persistedSidebarStateUrl() throws -> URL {
    try persistedStateDirectoryUrl()
        .appendingPathComponent(persistedSidebarStateFilename, isDirectory: false)
}

/// Folder identity, order, membership, and folded state are independent from
/// the temporary window-layout restart snapshot.  Save them independently so
/// a folder change survives a quick quit, a crash, or a restart that cannot
/// match the old macOS window IDs.
@MainActor
func persistSidebarStateForRestartIfPossible() {
    guard !isUnitTest, isPersistedSidebarStateReady else { return }
    let sidebar = FrozenSidebarState(restorableWorkspaces: Workspace.all.filter { !$0.isArchived })
    enqueueRestartState(sidebar: sidebar, world: nil)
}

/// State mutations often happen through an `inout` access to
/// `winMuxWorkspaceState`.  Saving synchronously from a property observer
/// re-entered that access and caused a Swift exclusivity crash at launch.
/// Coalesce the write onto the next main-loop turn instead.
@MainActor
func scheduleSidebarStatePersistenceForRestart() {
    guard !isUnitTest,
          isPersistedSidebarStateReady,
          !isSidebarStatePersistenceScheduled
    else { return }
    isSidebarStatePersistenceScheduled = true
    DispatchQueue.main.async {
        isSidebarStatePersistenceScheduled = false
        persistSidebarStateForRestartIfPossible()
    }
}

@MainActor
private func enqueueRestartState(
    sidebar: FrozenSidebarState?,
    world: PendingFrozenWorldWrite?,
) {
    restartStatePersistenceGeneration &+= 1
    let generation = restartStatePersistenceGeneration
    do {
        let sidebarWrite = try sidebar.map {
            PendingSidebarWrite(
                generation: generation,
                state: $0,
                url: try persistedSidebarStateUrl(),
            )
        }
        let worldWrite = try world.map {
            PendingWorldWrite(
                generation: generation,
                write: $0,
                url: try persistedFrozenWorldUrl(),
            )
        }
        Task {
            await restartStatePersistenceWriter.enqueue(
                sidebar: sidebarWrite,
                world: worldWrite,
            )
        }
    } catch {
        // Best effort. Path resolution failures should not affect the UI.
    }
}

@MainActor
private func captureRestartState() -> (
    sidebar: FrozenSidebarState?,
    world: PendingFrozenWorldWrite
) {
    let world = snapshotCurrentFrozenWorld()
    let sidebar = isPersistedSidebarStateReady ? world.sidebar : nil
    return (
        sidebar,
        world.windowIds.isEmpty ? .remove : .snapshot(world),
    )
}

/// Enqueue the complete restart snapshot and wait until the background writer
/// has atomically committed it.  This is reserved for termination, where a
/// fire-and-forget write could otherwise be lost to process exit.
@MainActor
func persistFrozenWorldForRestartAndWaitIfPossible() async {
    guard !isUnitTest else { return }
    let snapshot = captureRestartState()
    restartStatePersistenceGeneration &+= 1
    let generation = restartStatePersistenceGeneration
    do {
        let sidebarWrite: PendingSidebarWrite?
        if let sidebar = snapshot.sidebar {
            sidebarWrite = PendingSidebarWrite(
                generation: generation,
                state: sidebar,
                url: try persistedSidebarStateUrl(),
            )
        } else {
            sidebarWrite = nil
        }
        let worldWrite = PendingWorldWrite(
            generation: generation,
            write: snapshot.world,
            url: try persistedFrozenWorldUrl(),
        )
        await restartStatePersistenceWriter.enqueue(
            sidebar: sidebarWrite,
            world: worldWrite,
        )
    } catch {
        // Best effort. The flush below still drains any earlier checkpoint.
    }
    await restartStatePersistenceWriter.flush()
}

@MainActor
func loadPersistedSidebarStateForStartupIfPresent() {
    defer {
        didRestorePersistedSidebarStateDuringCurrentSession = false
        isPersistedSidebarStateReady = false
    }
    didLoadPersistedSidebarStateDuringCurrentSession = false
    do {
        let url = try persistedSidebarStateUrl()
        guard FileManager.default.fileExists(atPath: url.path) else {
            pendingPersistedSidebarState = nil
            return
        }
        let data = try Data(contentsOf: url)
        let envelope = try JSONDecoder().decode(PersistedSidebarStateEnvelope.self, from: data)
        pendingPersistedSidebarState = (1 ... persistedSidebarStateVersion).contains(envelope.version)
            ? envelope.sidebar
            : nil
        didLoadPersistedSidebarStateDuringCurrentSession = pendingPersistedSidebarState != nil
    } catch {
        pendingPersistedSidebarState = nil
    }
}

@MainActor
func finalizePersistedSidebarStateAfterStartupIfNeeded() {
    guard !didRestorePersistedSidebarStateDuringCurrentSession else { return }
    if let sidebar = pendingPersistedSidebarState {
        restoreFrozenSidebarState(
            sidebar,
            restoredWorkspaceNames: Set(Workspace.all.map(\.name)),
            materializeMissingWorkspaces: true,
        )
        pendingPersistedSidebarState = nil
    }
    didRestorePersistedSidebarStateDuringCurrentSession = true
    isPersistedSidebarStateReady = true
    // Capture the post-restore state immediately.  Unlike window-state.json,
    // sidebar-state.json is intentionally retained for every subsequent run.
    // Persistence must be enabled before this call. Previously these flags
    // were updated in a defer block, so this write always returned at its
    // readiness guard and the restored folders were never checkpointed.
    persistSidebarStateForRestartIfPossible()
}

@discardableResult
@MainActor
func loadPersistedFrozenWorldForStartupIfPresent() -> Bool {
    do {
        let url = try persistedFrozenWorldUrl()
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let data = try Data(contentsOf: url)
        let envelope = try JSONDecoder().decode(PersistedFrozenWorldEnvelope.self, from: data)
        guard envelope.version == persistedFrozenWorldVersion else { return false }
        pendingPersistedFrozenWorld = envelope.world
        didRestorePersistedFrozenWorldDuringCurrentSession = false
        return true
    } catch {
        return false
    }
}

@MainActor
func restorePersistedFrozenWorldIfNeeded(newlyDetectedWindow: Window) async throws -> Bool {
    guard let pendingPersistedFrozenWorld else { return false }
    let didRestore = try await restoreFrozenWorldIfNeeded(pendingPersistedFrozenWorld, newlyDetectedWindow: newlyDetectedWindow)
    if didRestore {
        didRestorePersistedFrozenWorldDuringCurrentSession = true
    }
    return didRestore
}

@MainActor
func finalizePersistedFrozenWorldAfterRefresh(aliveWindowIds: Set<UInt32>) {
    defer { finalizePersistedSidebarStateAfterStartupIfNeeded() }
    guard let world = pendingPersistedFrozenWorld else { return }
    let knownWindowIds = Set(MacWindow.allWindowsMap.keys)
    // Window IDs can legitimately change when WinMux itself is restarted even
    // though the user's browser windows and sidebar workspaces survive. Once
    // the startup scan has found at least the saved number of windows, restore
    // sidebar folder membership by its durable workspace names instead of
    // dropping every folder because no old window ID matched.
    let canRestoreSidebarByWorkspaceName = !didRestorePersistedFrozenWorldDuringCurrentSession &&
        knownWindowIds.count >= world.windowIds.count &&
        Workspace.all.count >= world.workspaces.count
    if canRestoreSidebarByWorkspaceName {
        // sidebar-state.json is updated after every sidebar mutation and is
        // therefore newer than the sidebar copy embedded in window-state.json.
        // Do not let the older layout snapshot overwrite it after a delayed
        // startup refresh.
        if !didLoadPersistedSidebarStateDuringCurrentSession {
            restoreFrozenSidebarState(
                world.sidebar,
                restoredWorkspaceNames: Set(Workspace.all.map(\.name))
            )
        }
        pendingPersistedFrozenWorld = nil
        didRestorePersistedFrozenWorldDuringCurrentSession = false
        try? FileManager.default.removeItem(at: persistedFrozenWorldUrl())
        return
    }
    if world.windowIds.isSubset(of: knownWindowIds) ||
        (didRestorePersistedFrozenWorldDuringCurrentSession &&
            !world.windowIds.isSubset(of: aliveWindowIds))
    {
        pendingPersistedFrozenWorld = nil
        didRestorePersistedFrozenWorldDuringCurrentSession = false
        try? FileManager.default.removeItem(at: persistedFrozenWorldUrl())
    }
}
