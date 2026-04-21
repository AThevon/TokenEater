import Foundation

struct JSONLParseResult: Sendable {
    let sessionId: String
    let projectPath: String
    let gitBranch: String?
    let model: String?
    let state: SessionState
    let timestamp: Date
    /// Input prompt size (input_tokens + cache_creation + cache_read) from the
    /// most recent assistant message. Represents how full the current context
    /// window is for the conversation's next turn. Nil if no assistant message
    /// has been seen yet (brand-new session).
    let contextTokens: Int?
    /// Observed context window capacity in tokens. Computed dynamically by
    /// scanning every assistant message's usage and taking the max: any value
    /// above 200k implies the session runs with the 1M-context variant that
    /// Claude Code auto-enables for Opus in agentic mode even though the model
    /// string in the JSONL is the bare `claude-opus-4-7`. Default is 200k.
    let contextMax: Int?
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

        /// Size of the input prompt the model processed on this turn - the sum
        /// of fresh input, newly cached content, and cache reads. Matches
        /// what Claude Code's `/context` reports. Excludes `output_tokens`
        /// because those are freshly generated and will show up as part of
        /// `cache_read` on the next turn.
        var contextInput: Int {
            (input_tokens ?? 0)
                + (cache_creation_input_tokens ?? 0)
                + (cache_read_input_tokens ?? 0)
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
        var lastAssistantContext: Int?
        var lastAssistantModel: String?
        var maxObservedContext: Int = 0

        for line in lines.reversed() {
            guard let data = line.data(using: .utf8),
                  let event = try? JSONDecoder().decode(RawEvent.self, from: data) else {
                continue
            }

            if latestMeta == nil, let sid = event.sessionId, let cwd = event.cwd {
                latestMeta = (sid, cwd, event.gitBranch)
            }

            // Track every assistant message's context size. The LATEST one (first
            // we encounter in reverse iteration) gives us current context; the
            // MAX across the whole file tells us whether the session is running
            // on a 1M-context variant - Claude Code auto-enables 1M context for
            // Opus even though the JSONL still logs the bare `claude-opus-4-7`
            // model string. Without this heuristic a busy Opus session shows as
            // "over 100% full" because we'd compare its real usage to the base
            // 200k cap.
            if event.type == "assistant", let usage = event.message?.usage {
                let context = usage.contextInput
                if lastAssistantContext == nil, context > 0 {
                    lastAssistantContext = context
                    lastAssistantModel = event.message?.model ?? lastAssistantModel
                }
                if context > maxObservedContext { maxObservedContext = context }
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

            // State detection: only promote an event to `lastMeaningfulEvent`
            // if we haven't settled on one yet. Keep iterating even after a
            // meaningful event is picked so we still have a chance to see an
            // assistant message with token usage further back in the tail -
            // otherwise `lastAssistantContext` stays nil when the very last
            // event is a system `turn_duration` or a `queue-operation`, and
            // the UI falls back to the "no data yet" look even on long
            // sessions. Early-exit only when both buckets are filled.

            if lastMeaningfulEvent == nil {
                if event.type == "system" {
                    if event.subtype == "turn_duration" || event.subtype == "stop_hook_summary" || event.subtype == "compact_boundary" {
                        lastMeaningfulEvent = event
                    }
                } else if event.type == "assistant" || event.type == "user" {
                    lastMeaningfulEvent = event
                } else if event.type == "progress" {
                    // Progress events are a soft fallback - any later definitive
                    // event (system turn-end, assistant, user) would replace it,
                    // but since we gate this branch on `lastMeaningfulEvent ==
                    // nil` we simply accept it as the best we've got so far.
                    lastMeaningfulEvent = event
                }
            }

            if lastMeaningfulEvent != nil && lastAssistantContext != nil {
                break
            }
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

        // Max detection: if any turn's context input exceeded 200k, the session
        // is using the 1M variant (Claude Code auto-enables it for Opus in
        // agentic mode without surfacing that in the model string). Else the
        // default 200k matches Sonnet / Haiku and non-agentic Opus.
        let detectedMax: Int?
        if lastAssistantContext != nil {
            detectedMax = maxObservedContext > 200_000 ? 1_000_000 : 200_000
        } else {
            detectedMax = nil
        }

        return JSONLParseResult(
            sessionId: meta.sessionId,
            projectPath: meta.cwd,
            gitBranch: lastMeaningfulEvent?.gitBranch ?? meta.gitBranch,
            model: lastMeaningfulEvent?.message?.model ?? lastAssistantModel,
            state: state,
            timestamp: timestamp,
            contextTokens: lastAssistantContext,
            contextMax: detectedMax
        )
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
