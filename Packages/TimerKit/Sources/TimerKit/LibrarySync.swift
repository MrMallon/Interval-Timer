import Foundation

/// A saved timer as it travels between iPhone and Apple Watch.
public struct SyncedTimer: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var colorName: String
    public var sortOrder: Int
    public var definition: TimerDefinition
    public var updatedAt: Date

    public init(id: UUID, name: String, colorName: String, sortOrder: Int, definition: TimerDefinition, updatedAt: Date) {
        self.id = id
        self.name = name
        self.colorName = colorName
        self.sortOrder = sortOrder
        self.definition = definition
        self.updatedAt = updatedAt
    }
}

/// Everything one device knows about the timer library.
public struct LibrarySnapshot: Codable, Hashable, Sendable {
    public var timers: [SyncedTimer]
    /// Deleted timer ids and when they were deleted.
    public var tombstones: [UUID: Date]

    public init(timers: [SyncedTimer], tombstones: [UUID: Date]) {
        self.timers = timers
        self.tombstones = tombstones
    }
}

/// Last-writer-wins merge of two timer libraries, with deletions that stick.
public enum LibrarySync {
    public struct Changes: Equatable, Sendable {
        /// Timers to create or overwrite locally.
        public var upserts: [SyncedTimer] = []
        /// Local timers to delete.
        public var deletions: Set<UUID> = []
        /// The merged tombstone list to keep locally.
        public var tombstones: [UUID: Date] = [:]

        public var isEmpty: Bool { upserts.isEmpty && deletions.isEmpty }
    }

    /// Works out what the local device must change to absorb `remote`.
    ///
    /// - A remote timer wins when it is newer than the local copy and newer
    ///   than any local deletion of it.
    /// - A remote deletion wins when it is newer than the local copy's last edit.
    /// - Tombstones older than `tombstoneLifetime` are forgotten.
    public static func merge(
        local: LibrarySnapshot,
        remote: LibrarySnapshot,
        now: Date = Date(),
        tombstoneLifetime: TimeInterval = 60 * 60 * 24 * 90
    ) -> Changes {
        var changes = Changes()
        var tombstones = local.tombstones
        for (id, date) in remote.tombstones where (tombstones[id] ?? .distantPast) < date {
            tombstones[id] = date
        }
        tombstones = tombstones.filter { now.timeIntervalSince($0.value) < tombstoneLifetime }
        changes.tombstones = tombstones

        let localByID = Dictionary(local.timers.map { ($0.id, $0) }, uniquingKeysWith: { a, b in a.updatedAt >= b.updatedAt ? a : b })

        for timer in remote.timers {
            if let deletedAt = tombstones[timer.id], deletedAt >= timer.updatedAt { continue }
            if let mine = localByID[timer.id] {
                if timer.updatedAt > mine.updatedAt, timer != mine {
                    changes.upserts.append(timer)
                }
            } else {
                changes.upserts.append(timer)
            }
        }

        for timer in local.timers {
            if let deletedAt = tombstones[timer.id], deletedAt >= timer.updatedAt {
                changes.deletions.insert(timer.id)
            }
        }
        changes.upserts.removeAll { changes.deletions.contains($0.id) }
        return changes
    }
}
