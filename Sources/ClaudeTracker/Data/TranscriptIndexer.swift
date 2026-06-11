import Foundation
import CoreServices

/// Finds the active Claude Code session (most recently written transcript
/// across all projects) and watches ~/.claude/projects via FSEvents.
final class TranscriptIndexer {
    let projectsDir: URL
    /// Fired on the main queue, debounced 1 s, after FSEvents activity.
    var onChange: (() -> Void)?

    private var stream: FSEventStreamRef?
    private var debounce: DispatchWorkItem?

    init(projectsDir: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects", isDirectory: true)) {
        self.projectsDir = projectsDir
    }

    struct ActiveSession {
        let url: URL
        let mtime: Date
        let projectDir: URL
    }

    func findActiveSession() -> ActiveSession? {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return nil }

        var best: ActiveSession?
        var bestKey: (Date, Int, String) = (.distantPast, 0, "")
        for dir in projectDirs {
            guard let files = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                guard let values = try? file.resourceValues(
                        forKeys: [.contentModificationDateKey, .fileSizeKey]),
                      let mtime = values.contentModificationDate else { continue }
                let key = (mtime, values.fileSize ?? 0, file.lastPathComponent)
                if key > bestKey {
                    bestKey = key
                    best = ActiveSession(url: file, mtime: mtime, projectDir: dir)
                }
            }
        }
        return best
    }

    /// All top-level transcripts for one project (used by the time aggregator).
    static func transcriptFiles(inProjectDir dir: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return files.filter { $0.pathExtension == "jsonl" }
    }

    // MARK: - FSEvents

    func startWatching() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<TranscriptIndexer>.fromOpaque(info).takeUnretainedValue().scheduleChange()
        }
        let flags = FSEventStreamCreateFlags(
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer))
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            [projectsDir.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            2.0, flags)
        else { return } // polling via the 60 s timer still covers updates
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    func stopWatching() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func scheduleChange() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange?() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }
}
