import Foundation
import SwiftData
import WatchConnectivity

/// Keeps the timer library in step between iPhone and Apple Watch, and sends
/// workouts finished on one device to the other's History.
///
/// - The whole library (plus deletions) goes over `updateApplicationContext`,
///   which always delivers the latest copy, even after the other side was off.
/// - Each finished workout goes over `transferUserInfo`, which queues and
///   delivers every item once.
/// Merging is last-writer-wins per timer (see `LibrarySync`).
@MainActor
final class SyncCoordinator: NSObject {
    static let shared = SyncCoordinator()

    private var container: ModelContainer?
    /// Called after the library changes here or arrives from the other device
    /// (the iPhone app refreshes its widget and Siri timer names).
    var onLibraryChange: (() -> Void)?
    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }
    private let tombstoneKey = "sync.tombstones.v1"

    /// Call once at launch.
    func start(container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container
        guard !LaunchEnvironment.usesInMemoryStore, let session else { return }
        session.delegate = self
        session.activate()
    }

    // MARK: - Outgoing

    /// Call after any local change to the library (save, delete, reorder).
    func libraryChanged() {
        onLibraryChange?()
        guard let session, session.activationState == .activated, let snapshot = makeSnapshot() else { return }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        do {
            try session.updateApplicationContext(["library": data])
        } catch {
            print("Sync: could not send library: \(error)")
        }
    }

    /// Records a local deletion so the other device deletes its copy too.
    func recordDeletion(of id: UUID) {
        var tombstones = loadTombstones()
        tombstones[id] = Date()
        saveTombstones(tombstones)
    }

    /// Sends a finished workout to the other device's History.
    func send(_ record: WorkoutRecord) {
        guard let session, session.activationState == .activated else { return }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif
        session.transferUserInfo(["workout": record.transferPayload])
    }

    // MARK: - Incoming

    private func receive(libraryData data: Data) {
        guard
            let container,
            let remote = try? JSONDecoder().decode(LibrarySnapshot.self, from: data),
            let local = makeSnapshot()
        else { return }

        let changes = LibrarySync.merge(local: local, remote: remote)
        saveTombstones(changes.tombstones)
        guard !changes.isEmpty else { return }

        let context = container.mainContext
        let templates = (try? context.fetch(FetchDescriptor<TimerTemplate>())) ?? []
        let byID = Dictionary(templates.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for id in changes.deletions {
            if let template = byID[id] { context.delete(template) }
        }
        for timer in changes.upserts {
            if let template = byID[timer.id] {
                template.apply(timer)
            } else {
                let template = TimerTemplate(
                    id: timer.id,
                    name: timer.name,
                    definition: timer.definition,
                    color: ThemeColor(rawValue: timer.colorName) ?? .red,
                    sortOrder: timer.sortOrder
                )
                template.updatedAt = timer.updatedAt
                context.insert(template)
            }
        }
        try? context.save()
        onLibraryChange?()
    }

    private func receive(workout payload: [String: Any]) {
        guard let container, let record = WorkoutRecord.fromTransfer(payload) else { return }
        let context = container.mainContext
        let id = record.id
        let existing = (try? context.fetchCount(FetchDescriptor<WorkoutRecord>(predicate: #Predicate { $0.id == id }))) ?? 0
        guard existing == 0 else { return }
        context.insert(record)
        try? context.save()
    }

    // MARK: - Helpers

    private func makeSnapshot() -> LibrarySnapshot? {
        guard let container else { return nil }
        let templates = (try? container.mainContext.fetch(FetchDescriptor<TimerTemplate>())) ?? []
        return LibrarySnapshot(timers: templates.map(\.synced), tombstones: loadTombstones())
    }

    private func loadTombstones() -> [UUID: Date] {
        guard
            let data = UserDefaults.standard.data(forKey: tombstoneKey),
            let decoded = try? JSONDecoder().decode([UUID: Date].self, from: data)
        else { return [:] }
        return decoded
    }

    private func saveTombstones(_ tombstones: [UUID: Date]) {
        if let data = try? JSONEncoder().encode(tombstones) {
            UserDefaults.standard.set(data, forKey: tombstoneKey)
        }
    }
}

extension SyncCoordinator: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let data = session.receivedApplicationContext["library"] as? Data
        Task { @MainActor in
            if let data {
                self.receive(libraryData: data)
            }
            self.libraryChanged()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["library"] as? Data else { return }
        Task { @MainActor in self.receive(libraryData: data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let payload = userInfo["workout"] as? [String: Any] else { return }
        Task { @MainActor in self.receive(workout: payload) }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Switching to a different watch: reactivate for the new one.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.libraryChanged() }
    }
    #endif
}
