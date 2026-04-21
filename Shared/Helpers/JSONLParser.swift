import Foundation

struct JSONLParseResult: Sendable {
    let sessionId: String
    let projectPath: String
    let gitBranch: String?
    let model: String?
    let state: SessionState
    let timestamp: Date
    /// Sum of input + cache_creation + cache_read + output tokens from the most
    /// recent assistant message in the JSONL. Represents the total size of the
    /// conversation's current context window snapshot. Nil if no assistant
    /// message has been seen yet (brand-new session).
    let contextTokens: Int?
}

enum JSONLParser {
    private struct RawEvent: Decodable {
        let type: String
        let subtype: String?
        let sessionId: String?
        let cwd: String?
        let gitBranch: String?
        let timestamp: String?
        let message: RawMessage?
        let data: RawProgressData?
        let operation: String?
    }

    private struct RawMessage: Decodable {
        let role: String?
        let model: String?
        let stop_reason: String?
        let content: [RawContentBlock]?
        let usage: RawUsage?

        private enum CodingKeys: String, CodingKey {
            case role, model, stop_reason, content, usage
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            role = try container.decodeIfPresent(String.self, forKey: .role)
            model = try container.decodeIfPresent(String.self, forKey: .model)
            stop_reason = try container.decodeIfPresent(String.self, forKey: .stop_reason)
            // content can be a string (user msgs) or an array (assistant) — graceful fallback
            content = try? container.decode([RawContentBlock].self, forKey: .content)
            usage = try? container.decode(RawUsage.self, forKey: .usage)
        }
    }

    private struct RawUsage: Decodable {
        let input_tokens: Int?
        let cache_creation_input_tokens: Int?
        let cache_read_input_tokens: Int?
        let output_tokens: Int?

        var total: Int {
            (input_tokens ?? 0)
                + (cache_creation_input_tokens ?? 0)
                + (cache_read_input_tokens ?? 0)
                + (output_tokens ?? 0)
        }
    }

    private struct RawContentBlock: Decodable {
        let type: String?
        let name: String?
    }

    private struct RawProgressData: Decodable {
        let type: String?
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseDate(_ string: String) -> Date? {
        isoFormatter.date(from: string) ?? isoFormatterNoFrac.date(from: string)
    }

    static func parseLastState(from content: String) -> JSONLParseResult? {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        guard !lines.isEmpty else { return nil }

        var lastMeaningfulEvent: RawEvent?
        var latestMeta: (sessionId: String, cwd: String, gitBranch: String?)?
        var pendingPermission = false
        var seenQueueRemove = false
        var lastAssistantUsage: Int?
        var lastAssistantModel: String?

        for line in lines.reversed() {
            guard let data = line.data(using: .utf8),
                  let event = try? JSONDecoder().decode(RawEvent.self, from: data) else {
                continue
            }

            if latestMeta == nil, let sid = event.sessionId, let cwd = event.cwd {
                latestMeta = (sid, cwd, event.gitBranch)
            }

            // Capture the most recent assistant message's usage - independent of
            // whatever became `lastMeaningfulEvent` (which might be a progress
            // event or a system turn-duration that has no token data).
            if lastAssistantUsage == nil,
               event.type == "assistant",
               let usage = event.message?.usage {
                let total = usage.total
                if total > 0 { lastAssistantUsage = total }
                lastAssistantModel = event.message?.model ?? lastAssistantModel
            }

            // Track queue-operation events for permission detection
            if event.type == "queue-operation" {
                if event.operation == "remove" && !seenQueueRemove {
                    seenQueueRemove = true
                }
                if event.operation == "enqueue" && !seenQueueRemove {
                    pendingPermission = true
                }
                continue
            }

            // System events: only turn_duration, stop_hook_summary, and compact_boundary indicate idle
            if event.type == "system" {
                if event.subtype == "turn_duration" || event.subtype == "stop_hook_summary" || event.subtype == "compact_boundary" {
                    lastMeaningfulEvent = event
                    break
                }
                continue
            }

            // Only consider known state-indicating types; skip everything else
            guard event.type == "assistant" || event.type == "user" || event.type == "progress" else {
                continue
            }

            // Progress events are not definitive (post-turn hooks emit them after stop_hook_summary).
            // Save as fallback and keep searching for a definitive event.
            if event.type == "progress" {
                if lastMeaningfulEvent == nil { lastMeaningfulEvent = event }
                continue
            }

            lastMeaningfulEvent = event
            break
        }

        guard let meta = latestMeta else { return nil }

        let state: SessionState
        let timestamp: Date
        if let event = lastMeaningfulEvent {
            state = determineState(event, pendingPermission: pendingPermission)
            timestamp = event.timestamp.flatMap(parseDate) ?? Date()
        } else {
            state = .idle
            timestamp = Date()
        }

        return JSONLParseResult(
            sessionId: meta.sessionId,
            projectPath: meta.cwd,
            gitBranch: lastMeaningfulEvent?.gitBranch ?? meta.gitBranch,
            model: lastMeaningfulEvent?.message?.model ?? lastAssistantModel,
            state: state,
            timestamp: timestamp,
            contextTokens: lastAssistantUsage
        )
    }

    /// Map a Claude Code model string to its context window size. Defaults to
    /// 200k - the standard context for every current Claude model. The `[1m]`
    /// suffix in model strings (e.g. `claude-opus-4-7[1m]`) signals the 1M
    /// variant that Anthropic exposes opt-in.
    static func contextMax(for model: String?) -> Int {
        guard let model else { return 200_000 }
        if model.contains("[1m]") || model.contains("-1m") {
            return 1_000_000
        }
        return 200_000
    }

    private static func determineState(_ event: RawEvent, pendingPermission: Bool) -> SessionState {
        switch event.type {
        case "assistant":
            guard let stopReason = event.message?.stop_reason else { return .thinking }
            switch stopReason {
            case "end_turn": return .idle
            case "tool_use":
                if pendingPermission { return .waiting }
                let hasAskUser = event.message?.content?.contains { $0.type == "tool_use" && $0.name == "AskUserQuestion" } ?? false
                return hasAskUser ? .waiting : .toolExec
            case "stop_sequence": return pendingPermission ? .waiting : .thinking
            default: return .thinking
            }
        case "progress":
            switch event.data?.type {
            case "bash_progress", "mcp_progress", "hook_progress", "waiting_for_task": return .toolExec
            case "agent_progress": return .subagent
            default: return .thinking
            }
        case "system":
            if event.subtype == "turn_duration" || event.subtype == "stop_hook_summary" || event.subtype == "compact_boundary" {
                return .idle
            }
            return .thinking
        case "user":
            return .thinking
        default:
            return .thinking
        }
    }
}
