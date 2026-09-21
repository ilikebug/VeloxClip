import Foundation

/// Process-wide exclusive claim, held for the lifetime of the app.
///
/// The old check polled `NSWorkspace.runningApplications` and compared PIDs.
/// That is a TOCTOU race: two copies launched together each saw the other and
/// BOTH terminated, leaving zero instances. It also raced the clipboard monitor,
/// which used to start polling from a property initializer before the check ran,
/// so a doomed second process could still write to the shared SQLite file.
///
/// `flock` settles it in the kernel: exactly one process can hold the lock, and
/// it is released automatically when that process exits (including on crash), so
/// a stale lockfile never wedges the app.
enum SingleInstanceGuard {
    /// Kept for the process lifetime — closing the descriptor releases the lock.
    private nonisolated(unsafe) static var lockDescriptor: Int32 = -1

    static func defaultLockURL() -> URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("VeloxClip", isDirectory: true)
            .appendingPathComponent("instance.lock")
    }

    /// Attempts to claim the lock. `true` means this process owns it.
    @discardableResult
    static func claim(at url: URL = defaultLockURL()) -> Bool {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let descriptor = open(url.path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else {
            // Can't create a lockfile at all (read-only home, sandbox denial).
            // Refusing to launch would be worse than the race we're avoiding.
            return true
        }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return false
        }

        lockDescriptor = descriptor
        return true
    }

    /// Releases the claim. Only needed in tests — the OS reclaims it on exit.
    static func release() {
        guard lockDescriptor >= 0 else { return }
        flock(lockDescriptor, LOCK_UN)
        close(lockDescriptor)
        lockDescriptor = -1
    }
}
