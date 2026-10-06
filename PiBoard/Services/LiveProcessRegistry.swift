import Darwin
import Foundation

struct LiveProcessEntry: Codable, Equatable, Sendable {
    let pid: Int32
    let taskID: UUID
    let startedAt: Date
    let executablePath: String
}

/// On-disk list of Pi children spawned by this PiBoard run. A force-quit or crash leaves the
/// forkpty children running, so the next launch reads this file to offer stopping them.
@MainActor
final class LiveProcessRegistry {
    private static let directoryName = "runtime"
    private static let fileName = "live-processes.json"

    let fileURL: URL
    private(set) var entries: [LiveProcessEntry]

    init(fileURL: URL) {
        self.fileURL = fileURL
        entries = Self.read(from: fileURL)
    }

    static func defaultFileURL() throws -> URL {
        try AppPaths.applicationSupportDirectory()
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    func add(_ entry: LiveProcessEntry) {
        entries.removeAll { $0.pid == entry.pid }
        entries.append(entry)
        persist()
    }

    func remove(pid: Int32) {
        let before = entries.count
        entries.removeAll { $0.pid == pid }
        guard entries.count != before else { return }
        persist()
    }

    func clear() {
        entries = []
        persist()
    }

    private func persist() {
        do {
            if entries.isEmpty {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }
                return
            }
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encoder.encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            Diagnostics.process.error("live process registry write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // A missing or unreadable file means nothing was left behind.
    private static func read(from url: URL) -> [LiveProcessEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? decoder.decode([LiveProcessEntry].self, from: data)) ?? []
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Read-only process queries used to tell a leftover Pi child from an unrelated process that
/// reused its pid.
enum ProcessInspector {
    /// Seconds between the recorded spawn time and the kernel start time still treated as the same process.
    static let startTimeTolerance: TimeInterval = 2
    private static let launchdPID: pid_t = 1
    // PROC_PIDPATHINFO_MAXSIZE is a macro Swift cannot import.
    private static let pidPathBufferSize = 4 * Int(MAXPATHLEN)

    private static func kernelInfo(pid: pid_t) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }

    /// Zombies count as gone: they no longer run and only wait for their parent to reap them.
    static func isAlive(pid: pid_t) -> Bool {
        guard pid > 0, let info = kernelInfo(pid: pid) else { return false }
        return info.kp_proc.p_stat != SZOMB
    }

    static func startTime(pid: pid_t) -> Date? {
        guard pid > 0, let info = kernelInfo(pid: pid) else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }

    static func parentPID(pid: pid_t) -> pid_t? {
        guard pid > 0, let info = kernelInfo(pid: pid) else { return nil }
        return info.kp_eproc.e_ppid
    }

    static func executablePath(pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: pidPathBufferSize)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }

    /// True when `entry` still names the process it was recorded for: alive, same start time and same executable.
    static func isSameProcess(_ entry: LiveProcessEntry) -> Bool {
        guard isAlive(pid: entry.pid),
              let started = startTime(pid: entry.pid),
              abs(started.timeIntervalSince(entry.startedAt)) <= startTimeTolerance,
              let path = executablePath(pid: entry.pid) else { return false }
        return URL(fileURLWithPath: path).resolvingSymlinksInPath() == URL(fileURLWithPath: entry.executablePath).resolvingSymlinksInPath()
    }

    /// The parent of a crashed app's children becomes launchd; a child still owned by a running
    /// PiBoard (for example a second instance) is not an orphan.
    static func isOrphaned(pid: pid_t) -> Bool {
        parentPID(pid: pid) == launchdPID
    }
}

/// Finds and stops Pi children left running by a PiBoard run that crashed or was force-quit.
@MainActor
enum OrphanedProcessCleanup {
    static let killGracePeriod: TimeInterval = 5

    static func orphans(in entries: [LiveProcessEntry], expectedExecutable: URL?) -> [LiveProcessEntry] {
        entries.filter { entry in
            if let expectedExecutable,
               URL(fileURLWithPath: entry.executablePath).resolvingSymlinksInPath() != expectedExecutable.resolvingSymlinksInPath() {
                return false
            }
            return ProcessInspector.isSameProcess(entry) && ProcessInspector.isOrphaned(pid: entry.pid)
        }
    }

    /// SIGTERM now, SIGKILL after the grace period for any entry that is still the same process.
    static func stop(_ entries: [LiveProcessEntry], gracePeriod: TimeInterval = killGracePeriod) async {
        for entry in entries where ProcessInspector.isSameProcess(entry) {
            Darwin.kill(entry.pid, SIGTERM)
        }
        try? await Task.sleep(nanoseconds: UInt64(gracePeriod * 1_000_000_000))
        for entry in entries where ProcessInspector.isSameProcess(entry) {
            Darwin.kill(entry.pid, SIGKILL)
        }
    }
}
