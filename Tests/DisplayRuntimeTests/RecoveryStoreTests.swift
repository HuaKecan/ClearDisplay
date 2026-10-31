import Dispatch
import DisplayCore
import Foundation
import XCTest
@testable import DisplayRuntime

final class RecoveryStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func withTemporaryStore(_ body: (RecoveryStore) throws -> Void) rethrows {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClearDisplay-RecoveryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(RecoveryStore(url: directory.appendingPathComponent("private/recovery.json")))
    }

    private func receipt(expiresIn seconds: TimeInterval = 20) -> RecoveryReceipt {
        let mode = DisplayModeSpec(width: 1920, height: 1080, pixelWidth: 3840,
                                   pixelHeight: 2160, refreshRate: 59.94, ioModeID: 11)
        let second = DisplayModeSpec(width: 2560, height: 1440, pixelWidth: 2560,
                                     pixelHeight: 1440, refreshRate: 60, ioModeID: 22)
        let snapshot = DesktopSnapshot(displays: [
            DisplaySnapshotEntry(uuid: "fixture-primary", displayID: 111, mode: mode, x: 0, y: 0),
            DisplaySnapshotEntry(uuid: "fixture-secondary", displayID: 222, mode: second, x: 1920, y: -100)
        ])
        return RecoveryReceipt(snapshot: snapshot, expiresAt: now.addingTimeInterval(seconds),
                               summary: "测试模式切换")
    }

    func testBeginWritesCompleteReadableReceiptWithPrivatePermissions() throws {
        try withTemporaryStore { store in
            let expected = receipt()
            XCTAssertNil(try store.read())
            try store.begin(expected)

            XCTAssertEqual(try store.read(), expected)
            let persisted = try JSONDecoder().decode(RecoveryReceipt.self, from: Data(contentsOf: store.url))
            XCTAssertEqual(persisted, expected)
            let attributes = try FileManager.default.attributesOfItem(atPath: store.url.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
            let directoryAttributes = try FileManager.default.attributesOfItem(atPath: store.url.deletingLastPathComponent().path)
            XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
            let children = try FileManager.default.contentsOfDirectory(atPath: store.url.deletingLastPathComponent().path)
            XCTAssertEqual(Set(children), Set(["recovery.json", "recovery.json.lock"]))
        }
    }

    func testSecondPendingChangeIsRejectedWithoutOverwritingFirst() throws {
        try withTemporaryStore { store in
            let original = receipt()
            try store.begin(original)
            XCTAssertThrowsError(try store.begin(receipt(expiresIn: 60)))
            XCTAssertEqual(try store.read(), original)
        }
    }

    func testWrongTokenCannotConfirmOrRestore() throws {
        try withTemporaryStore { store in
            let original = receipt()
            try store.begin(original)
            let wrongToken = UUID()
            XCTAssertFalse(try store.confirm(token: wrongToken, now: now))
            var restored = false
            XCTAssertFalse(try store.restore(token: wrongToken, now: now) { _ in restored = true })
            XCTAssertFalse(restored)
            XCTAssertEqual(try store.read(), original)
        }
    }

    func testExpiredConfirmationIsRejectedAndRetainsReceipt() throws {
        for deadlineOffset: TimeInterval in [-1, 0] {
            try withTemporaryStore { store in
                let original = receipt(expiresIn: deadlineOffset)
                try store.begin(original)
                XCTAssertThrowsError(try store.confirm(token: original.token, now: now))
                XCTAssertEqual(try store.read(), original)
            }
        }
    }

    func testOnlyIfExpiredDoesNotRestoreBeforeDeadline() throws {
        try withTemporaryStore { store in
            let original = receipt(expiresIn: 0.01)
            try store.begin(original)
            var restored = false
            XCTAssertFalse(try store.restore(token: original.token, onlyIfExpired: true, now: now) { _ in restored = true })
            XCTAssertFalse(restored)
            XCTAssertEqual(try store.read(), original)
        }
    }

    func testSuccessfulExpiredRestorationReceivesOriginalSnapshotAndClearsReceipt() throws {
        try withTemporaryStore { store in
            let original = receipt(expiresIn: 0)
            try store.begin(original)
            var restored: DesktopSnapshot?
            XCTAssertTrue(try store.restore(token: original.token, onlyIfExpired: true, now: now) { restored = $0 })
            XCTAssertEqual(restored, original.snapshot)
            XCTAssertNil(try store.read())
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
        }
    }

    func testManualRollbackCanRestoreBeforeDeadline() throws {
        try withTemporaryStore { store in
            let original = receipt()
            try store.begin(original)
            var restored: DesktopSnapshot?
            XCTAssertTrue(try store.restore(token: original.token, now: now) { restored = $0 })
            XCTAssertEqual(restored, original.snapshot)
            XCTAssertNil(try store.read())
        }
    }

    func testFailedRestorationRetainsReceiptForRetry() throws {
        enum RestoreFailure: Error { case intentional }
        try withTemporaryStore { store in
            let original = receipt(expiresIn: -1)
            try store.begin(original)
            XCTAssertThrowsError(try store.restore(token: original.token, onlyIfExpired: true, now: now) { _ in
                throw RestoreFailure.intentional
            }) { error in
                XCTAssertTrue(error is RestoreFailure)
            }
            XCTAssertEqual(try store.read(), original)
            XCTAssertTrue(try store.restore(token: original.token, onlyIfExpired: true, now: now) { _ in })
            XCTAssertNil(try store.read())
        }
    }

    func testEarlyConfirmationDeletesReceiptAndPreventsLaterRestoration() throws {
        try withTemporaryStore { store in
            let original = receipt()
            try store.begin(original)
            XCTAssertTrue(try store.confirm(token: original.token, now: now))
            XCTAssertNil(try store.read())
            XCTAssertFalse(try store.confirm(token: original.token, now: now))
            var restored = false
            XCTAssertFalse(try store.restore(token: original.token, now: now.addingTimeInterval(30)) { _ in restored = true })
            XCTAssertFalse(restored)
        }
    }

    func testConcurrentIndependentStoresRestoreSameTokenExactlyOnce() throws {
        try withTemporaryStore { store in
            let original = receipt(expiresIn: -1)
            try store.begin(original)
            let url = store.url
            let token = original.token
            let fixedNow = now
            let results = ConcurrentResults()

            DispatchQueue.concurrentPerform(iterations: 24) { _ in
                // Each worker opens its own file descriptor, as the separate rescue
                // process does. The advisory lock must protect the read/action/delete.
                let independent = RecoveryStore(url: url)
                do {
                    let didRestore = try independent.restore(token: token, onlyIfExpired: true, now: fixedNow) { _ in
                        results.recordAction()
                        Thread.sleep(forTimeInterval: 0.005)
                    }
                    results.recordResult(restored: didRestore)
                } catch {
                    results.recordError(error)
                }
            }

            XCTAssertEqual(results.actionCount, 1)
            XCTAssertEqual(results.successCount, 1)
            XCTAssertEqual(results.completedCount, 24)
            XCTAssertTrue(results.errors.isEmpty, results.errors.joined(separator: "\n"))
            XCTAssertNil(try store.read())
        }
    }

    func testRemainingSecondsCeilAndClampAtDeadline() {
        XCTAssertEqual(receipt(expiresIn: 1.01).secondsRemaining(at: now), 2)
        XCTAssertEqual(receipt(expiresIn: 0.01).secondsRemaining(at: now), 1)
        XCTAssertEqual(receipt(expiresIn: 0).secondsRemaining(at: now), 0)
        XCTAssertEqual(receipt(expiresIn: -20).secondsRemaining(at: now), 0)
    }
}

private final class ConcurrentResults: @unchecked Sendable {
    private let lock = NSLock()
    private var actions = 0
    private var successes = 0
    private var completed = 0
    private var failures: [String] = []

    var actionCount: Int { lock.withLock { actions } }
    var successCount: Int { lock.withLock { successes } }
    var completedCount: Int { lock.withLock { completed } }
    var errors: [String] { lock.withLock { failures } }

    func recordAction() { lock.withLock { actions += 1 } }
    func recordResult(restored: Bool) {
        lock.withLock {
            completed += 1
            if restored { successes += 1 }
        }
    }
    func recordError(_ error: Error) {
        lock.withLock {
            completed += 1
            failures.append(String(describing: error))
        }
    }
}
