import XCTest
@testable import TimerKit

final class LibrarySyncTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func timer(_ id: UUID, _ name: String, at offset: TimeInterval) -> SyncedTimer {
        SyncedTimer(id: id, name: name, colorName: "red", sortOrder: 0,
                    definition: .simple(SimpleConfig()), updatedAt: t0.addingTimeInterval(offset))
    }

    func testNewRemoteTimerIsAdded() {
        let id = UUID()
        let changes = LibrarySync.merge(
            local: LibrarySnapshot(timers: [], tombstones: [:]),
            remote: LibrarySnapshot(timers: [timer(id, "Legs", at: 0)], tombstones: [:]),
            now: t0
        )
        XCTAssertEqual(changes.upserts.map(\.id), [id])
        XCTAssertTrue(changes.deletions.isEmpty)
    }

    func testNewerEditWinsOlderIsIgnored() {
        let id = UUID()
        let newer = LibrarySync.merge(
            local: LibrarySnapshot(timers: [timer(id, "Old", at: 0)], tombstones: [:]),
            remote: LibrarySnapshot(timers: [timer(id, "New", at: 10)], tombstones: [:]),
            now: t0
        )
        XCTAssertEqual(newer.upserts.first?.name, "New")

        let older = LibrarySync.merge(
            local: LibrarySnapshot(timers: [timer(id, "Mine", at: 10)], tombstones: [:]),
            remote: LibrarySnapshot(timers: [timer(id, "Stale", at: 0)], tombstones: [:]),
            now: t0
        )
        XCTAssertTrue(older.isEmpty)
    }

    func testRemoteDeletionRemovesLocalTimer() {
        let id = UUID()
        let changes = LibrarySync.merge(
            local: LibrarySnapshot(timers: [timer(id, "Legs", at: 0)], tombstones: [:]),
            remote: LibrarySnapshot(timers: [], tombstones: [id: t0.addingTimeInterval(5)]),
            now: t0
        )
        XCTAssertEqual(changes.deletions, [id])
        XCTAssertNotNil(changes.tombstones[id])
    }

    func testEditAfterDeletionKeepsTheTimer() {
        let id = UUID()
        let changes = LibrarySync.merge(
            local: LibrarySnapshot(timers: [timer(id, "Edited later", at: 20)], tombstones: [:]),
            remote: LibrarySnapshot(timers: [], tombstones: [id: t0.addingTimeInterval(5)]),
            now: t0
        )
        XCTAssertTrue(changes.deletions.isEmpty)
    }

    func testLocalDeletionBlocksResurrection() {
        let id = UUID()
        let changes = LibrarySync.merge(
            local: LibrarySnapshot(timers: [], tombstones: [id: t0.addingTimeInterval(10)]),
            remote: LibrarySnapshot(timers: [timer(id, "Zombie", at: 0)], tombstones: [:]),
            now: t0
        )
        XCTAssertTrue(changes.upserts.isEmpty, "A timer deleted here must not come back from the other device")
    }

    func testIdenticalLibrariesProduceNoChanges() {
        let a = timer(UUID(), "A", at: 0)
        let snapshot = LibrarySnapshot(timers: [a], tombstones: [:])
        XCTAssertTrue(LibrarySync.merge(local: snapshot, remote: snapshot, now: t0).isEmpty)
    }

    func testOldTombstonesExpire() {
        let id = UUID()
        let changes = LibrarySync.merge(
            local: LibrarySnapshot(timers: [], tombstones: [id: t0]),
            remote: LibrarySnapshot(timers: [], tombstones: [:]),
            now: t0.addingTimeInterval(60 * 60 * 24 * 100)
        )
        XCTAssertTrue(changes.tombstones.isEmpty)
    }

    func testSnapshotRoundTripsThroughJSON() throws {
        let id = UUID()
        let snapshot = LibrarySnapshot(timers: [timer(UUID(), "A", at: 0)], tombstones: [id: t0])
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(LibrarySnapshot.self, from: data), snapshot)
    }
}
