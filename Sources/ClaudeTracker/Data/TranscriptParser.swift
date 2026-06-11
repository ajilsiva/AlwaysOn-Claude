import Foundation

struct TranscriptRecord: Decodable {
    let type: String?
    let isSidechain: Bool?
    let timestamp: String?
    let cwd: String?
    let version: String?
    let message: Message?

    struct Message: Decodable {
        let model: String?
        let usage: Usage?
    }

    struct Usage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheCreationInputTokens: Int?
        let cacheReadInputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
        }
    }
}

enum TranscriptParser {
    /// Only the tail of a transcript is needed for "current" values.
    static let tailWindow: UInt64 = 262_144
    /// Context formula: input + cache_creation + cache_read — what the API
    /// counts as input next turn. Flip for CCometixLine parity (+output).
    static let includeOutputTokens = false

    struct LastUsage {
        let model: String
        let contextTokens: Int
        let timestamp: Date?
    }

    static func lastAssistantUsage(in url: URL) -> LastUsage? {
        for line in tailLines(of: url).reversed() {
            guard let record = try? decoder.decode(TranscriptRecord.self, from: line),
                  record.type == "assistant",
                  record.isSidechain != true,
                  let message = record.message,
                  let usage = message.usage,
                  let model = message.model,
                  !model.contains("<") // skip "<synthetic>" records
            else { continue }
            var tokens = (usage.inputTokens ?? 0)
                + (usage.cacheCreationInputTokens ?? 0)
                + (usage.cacheReadInputTokens ?? 0)
            if includeOutputTokens { tokens += usage.outputTokens ?? 0 }
            return LastUsage(model: model,
                             contextTokens: tokens,
                             timestamp: record.timestamp.flatMap(parseISO))
        }
        return nil
    }

    static func sessionMeta(in url: URL) -> (cwd: String?, version: String?) {
        var cwd: String?
        var version: String?
        for line in tailLines(of: url).reversed() {
            guard let record = try? decoder.decode(TranscriptRecord.self, from: line) else { continue }
            if cwd == nil { cwd = record.cwd }
            if version == nil { version = record.version }
            if cwd != nil, version != nil { break }
        }
        return (cwd, version)
    }

    static func contextLimit(modelId: String?, configuredModel: String?) -> Int {
        if modelId?.contains("[1m]") == true || configuredModel?.contains("[1m]") == true {
            return 1_000_000
        }
        return 200_000
    }

    // MARK: - Helpers

    private static let decoder = JSONDecoder()

    static func tailLines(of url: URL) -> [Data] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return [] }
        let offset = size > tailWindow ? size - tailWindow : 0
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd() else { return [] }
        var lines = data.split(separator: UInt8(ascii: "\n"))
        if offset > 0, !lines.isEmpty { lines.removeFirst() } // drop partial first line
        return lines
    }

    static func parseISO(_ string: String) -> Date? {
        isoFractional.date(from: string) ?? iso.date(from: string)
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
