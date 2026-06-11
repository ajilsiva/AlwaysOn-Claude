import Foundation

/// Cumulative active time for a project: per transcript, the sum of
/// consecutive-record timestamp deltas no larger than the idle gap (5 min);
/// all of the project's sessions summed. Incremental: each file is parsed
/// once, then only the appended bytes are read on subsequent calls.
///
/// Not thread-safe by design — call only from one serial queue.
final class ProjectTimeAggregator {
    static let maxGap: TimeInterval = 300

    private struct ParseState {
        var offset: UInt64 = 0
        var lastTimestamp: Date?
        var activeSeconds: Double = 0
    }

    private struct TimestampOnly: Decodable {
        let timestamp: String?
    }

    private var states: [String: ParseState] = [:]
    private let decoder = JSONDecoder()

    func activeSeconds(forProjectDir dir: URL) -> TimeInterval {
        TranscriptIndexer.transcriptFiles(inProjectDir: dir)
            .reduce(0) { $0 + seconds(for: $1) }
    }

    private func seconds(for url: URL) -> TimeInterval {
        let path = url.path
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?
            .uint64Value ?? 0
        var state = states[path] ?? ParseState()
        if size < state.offset { state = ParseState() } // truncated/replaced: reparse
        if size == state.offset {
            states[path] = state
            return state.activeSeconds
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return state.activeSeconds }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: state.offset)) != nil,
              let data = try? handle.readToEnd() else { return state.activeSeconds }

        // Consume only complete lines; a trailing partial line (mid-write)
        // stays unconsumed and is picked up next time.
        var index = data.startIndex
        while let newline = data[index...].firstIndex(of: UInt8(ascii: "\n")) {
            let line = data[index..<newline]
            state.offset += UInt64(newline - index + 1)
            index = data.index(after: newline)
            guard let record = try? decoder.decode(TimestampOnly.self, from: line),
                  let ts = record.timestamp.flatMap(TranscriptParser.parseISO)
            else { continue }
            if let last = state.lastTimestamp {
                let delta = ts.timeIntervalSince(last)
                if delta > 0, delta <= Self.maxGap {
                    state.activeSeconds += delta
                }
            }
            if ts > (state.lastTimestamp ?? .distantPast) {
                state.lastTimestamp = ts
            }
        }

        states[path] = state
        return state.activeSeconds
    }
}
