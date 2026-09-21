import XCTest
@testable import VeloxClip

final class SingleInstanceGuardTests: XCTestCase {
    private func makeLockURL(_ name: String) -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = root.appendingPathComponent("VeloxClipLock-\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("instance.lock")
    }

    override func tearDown() {
        SingleInstanceGuard.release()
        super.tearDown()
    }

    func testClaimSucceedsWhenUnheld() {
        XCTAssertTrue(SingleInstanceGuard.claim(at: makeLockURL(#function)))
    }

    /// The old check polled runningApplications and compared PIDs, so two
    /// simultaneous launches each saw the other and BOTH quit. A kernel lock
    /// has exactly one winner.
    func testSecondClaimFailsWhileAnotherProcessHoldsTheLock() throws {
        let url = makeLockURL(#function)

        // Hold the lock the way a separate live process would.
        let holder = open(url.path, O_CREAT | O_RDWR, 0o644)
        XCTAssertGreaterThanOrEqual(holder, 0)
        XCTAssertEqual(flock(holder, LOCK_EX | LOCK_NB), 0)
        defer { flock(holder, LOCK_UN); close(holder) }

        XCTAssertFalse(SingleInstanceGuard.claim(at: url),
                       "a second instance must lose the claim, not race it")
    }

    /// flock is released by the kernel when the owning fd closes, so a crashed
    /// instance must never leave a lockfile that wedges the next launch.
    func testLockIsReclaimableAfterTheHolderReleases() throws {
        let url = makeLockURL(#function)

        let holder = open(url.path, O_CREAT | O_RDWR, 0o644)
        XCTAssertEqual(flock(holder, LOCK_EX | LOCK_NB), 0)
        XCTAssertFalse(SingleInstanceGuard.claim(at: url))

        flock(holder, LOCK_UN)
        close(holder)

        XCTAssertTrue(SingleInstanceGuard.claim(at: url),
                      "a stale lockfile must not block a fresh launch")
    }
}
