import Foundation

struct JSONLParseResult: Sendable {
    let sessionId: String
    let projectPath: String
    let gitBranch: String?
    let model: String?
    let state: SessionState
    let timestamp: Date
}

enum JSONLParser {
    private struct RawEvent: Decodable {
        let type: String
        let sessionId: String?
        let cwd: String?
        let gitBranch: String?
        let timestamp: String?
        let message: RawMessage?
    }

    private struct RawMessage: Decodable {
        let role: String?
        let model: String?
        let stop_reason: String?
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

        for line in lines.reversed() {
            guard let data = line.data(using: .utf8),
                  let event = try? JSONDecoder().decode(RawEvent.self, from: data) else {
                continue
            }

            if latestMeta == nil, let sid = event.sessionId, let cwd = event.cwd {
                latestMeta = (sid, cwd, event.gitBranch)
            }

            if event.type == "system" || event.type == "file-history-snapshot" {
                continue
            }

            lastMeaningfulEvent = event
            break
        }

        guard let event = lastMeaningfulEvent,
              let meta = latestMeta else { return nil }

        let state = determineState(event)
        let timestamp = event.timestamp.flatMap(parseDate) ?? Date()

        return JSONLParseResult(
            sessionId: meta.sessionId,
            projectPath: meta.cwd,
            gitBranch: event.gitBranch ?? meta.gitBranch,
            model: event.message?.model,
            state: state,
            timestamp: timestamp
        )
    }

    private static func determineState(_ event: RawEvent) -> SessionState {
        switch event.type {
        case "assistant":
            guard let stopReason = event.message?.stop_reason else { return .working }
            switch stopReason {
            case "end_turn": return .idle
            case "tool_use": return .toolExec
            default: return .working
            }
        case "progress": return .working
        case "user": return .working
        default: return .working
        }
    }
}
