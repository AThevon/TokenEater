import Foundation

enum CodexHistoryParser {
    // MARK: - Nested Types

    private struct Event: Decodable {
        let timestamp: String
        let type: String
        let payload: Payload
    }

    private struct Payload: Decodable {
        let type: String?
        let id: String?
        let session_id: String?
        let thread_id: String?
        let turn_id: String?
        let response_id: String?
        let cwd: String?
        let model: String?
        let thread_source: String?
        let source: Source?
        let usage: Usage?
        let info: Info?
    }

    private struct Source: Decodable {
        let isGuardian: Bool

        private enum CodingKeys: String, CodingKey { case subagent, other }

        init(from decoder: Decoder) throws {
            let container = try? decoder.container(keyedBy: CodingKeys.self)
            let subagent = try? container?.nestedContainer(keyedBy: CodingKeys.self, forKey: .subagent)
            isGuardian = (try? subagent?.decode(String.self, forKey: .other)) == "guardian"
        }
    }

    private struct Info: Decodable {
        let total_token_usage: Usage?
        let last_token_usage: Usage?
    }

    private struct Usage: Decodable, Equatable {
        let input_tokens: Int
        let cached_input_tokens: Int?
        let cache_write_input_tokens: Int?
        let output_tokens: Int

        var cached: Int { max(0, cached_input_tokens ?? 0) }
        var written: Int { max(0, cache_write_input_tokens ?? 0) }
        var isValid: Bool {
            input_tokens >= 0 && output_tokens >= 0
                && cached <= input_tokens && written <= input_tokens - cached
        }

        func delta(from previous: Usage) -> Usage? {
            guard input_tokens >= previous.input_tokens,
                  output_tokens >= previous.output_tokens,
                  cached >= previous.cached,
                  written >= previous.written else { return nil }
            return Usage(
                input_tokens: input_tokens - previous.input_tokens,
                cached_input_tokens: cached - previous.cached,
                cache_write_input_tokens: written - previous.written,
                output_tokens: output_tokens - previous.output_tokens
            )
        }
    }

    // MARK: - Type Methods

    static func parse(_ content: String, path: String, mtime: Date) throws -> HistoryFileCacheEntry {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        let decoder = JSONDecoder()
        var events: [(date: Date, event: Event)] = []
        content.enumerateLines { line, stop in
            if Task.isCancelled { stop = true; return }
            guard line.contains("\"session_meta\"") || line.contains("\"turn_context\"")
                || line.contains("\"token_usage_record\"") || line.contains("\"token_count\""),
                  let data = line.data(using: .utf8),
                  let event = try? decoder.decode(Event.self, from: data),
                  ["session_meta", "turn_context", "token_usage_record", "event_msg"].contains(event.type),
                  let date = fractional.date(from: event.timestamp) ?? plain.date(from: event.timestamp)
            else { return }
            events.append((date, event))
        }
        try Task.checkCancellation()

        let meta = events.last { $0.event.type == "session_meta" }
        if meta?.event.payload.thread_source == "guardian_review" || meta?.event.payload.source?.isGuardian == true {
            return HistoryFileCacheEntry(path: path, mtime: mtime, buckets: [], sessionIds: [])
        }
        let sessionID = meta?.event.payload.id ?? meta?.event.payload.session_id
        let firstRecordDate = events.first {
            $0.event.type == "token_usage_record"
                && owns($0.event.payload, sessionID: sessionID)
                && $0.event.payload.usage?.isValid == true
        }?.date
        var project = meta?.event.payload.cwd ?? "Codex"
        var model = ""
        var turnModels: [String: String] = [:]
        var responses: Set<String> = []
        var previous: Usage?
        var buckets: [Date: HistoryBucket] = [:]

        for (date, event) in events {
            try Task.checkCancellation()
            let payload = event.payload
            if event.type == "turn_context" {
                model = payload.model ?? model
                project = payload.cwd ?? project
                if let turn = payload.turn_id { turnModels[turn] = model }
                continue
            }

            let usage: Usage
            let eventModel: String
            if event.type == "token_usage_record" {
                guard owns(payload, sessionID: sessionID), let recorded = payload.usage,
                      recorded.isValid else { continue }
                let identity = payload.response_id ?? "\(payload.turn_id ?? ""):\(event.timestamp)"
                guard responses.insert(identity).inserted else { continue }
                usage = recorded
                eventModel = payload.turn_id.flatMap { turnModels[$0] } ?? model
            } else if event.type == "event_msg", payload.type == "token_count" {
                guard let total = payload.info?.total_token_usage, total.isValid else { continue }
                let old = previous
                previous = total
                // New logs mirror each response in token_count; only older events need the cumulative fallback.
                guard firstRecordDate.map({ date < $0 }) ?? true,
                      meta.map({ date >= $0.date }) ?? true, total != old else { continue }
                if let old {
                    guard let delta = total.delta(from: old) ?? payload.info?.last_token_usage,
                          delta.isValid else { continue }
                    usage = delta
                } else {
                    usage = payload.info?.last_token_usage ?? total
                }
                eventModel = model
            } else {
                continue
            }

            guard usage.isValid, eventModel.lowercased() != "codex-auto-review" else { continue }
            let input = usage.input_tokens - usage.cached - usage.written
            let active = input + usage.written + usage.output_tokens
            guard active + usage.cached > 0 else { continue }
            let hour = Calendar.current.dateInterval(of: .hour, for: date)?.start ?? date
            var bucket = buckets[hour] ?? HistoryBucket.merging(.empty, .empty, date: hour)
            bucket.tokensByModel[.codex(model: eventModel), default: 0] += active
            bucket.tokensByProject[project, default: 0] += active
            bucket.inputTokens += input
            bucket.outputTokens += usage.output_tokens
            bucket.cacheReadTokens += usage.cached
            bucket.cacheCreateTokens += usage.written
            buckets[hour] = bucket
        }
        if let earliest = buckets.keys.min() { buckets[earliest]?.sessionsCount = 1 }
        return HistoryFileCacheEntry(
            path: path, mtime: mtime,
            buckets: buckets.values.sorted { $0.date < $1.date },
            sessionIds: sessionID.map { [$0] } ?? []
        )
    }

    private static func owns(_ payload: Payload, sessionID: String?) -> Bool {
        guard let sessionID, let owner = payload.thread_id else { return true }
        return owner == sessionID
    }
}
