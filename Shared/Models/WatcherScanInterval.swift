import Foundation

/// How often the local session watcher rescans running processes + JSONL tails.
/// Lower = snappier overlay, more local CPU. There is no sub-2s option on
/// purpose: each tick enumerates the whole process table, so 1s is materially
/// heavier for little perceived gain.
enum WatcherScanInterval: Int, CaseIterable, Sendable {
    case twoSeconds = 2
    case fiveSeconds = 5
    case tenSeconds = 10

    var seconds: TimeInterval { TimeInterval(rawValue) }

    /// Compact, locale-neutral chip label ("2s", "5s", "10s").
    var label: String { "\(rawValue)s" }
}
