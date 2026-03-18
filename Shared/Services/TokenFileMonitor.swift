import Foundation
import Combine

final class TokenFileMonitor: TokenFileMonitorProtocol {
    private let subject = PassthroughSubject<Void, Never>()
    private var sources: [DispatchSourceFileSystemObject] = []
    private var fileDescriptors: [Int32] = []
    private let debounceInterval: TimeInterval
    private var lastEmit: Date = .distantPast
    private let queue = DispatchQueue(label: "com.tokeneater.filemonitor", qos: .utility)
    private let watchedDirectories: [String]
    private let watchedFilenames: [String: String] // directory -> filename
    private var lastModDates: [String: Date] = [:]

    var tokenChanged: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }

    init(debounceInterval: TimeInterval = 2.0) {
        self.debounceInterval = debounceInterval
        guard let pw = getpwuid(getuid()) else {
            watchedDirectories = []
            watchedFilenames = [:]
            return
        }
        let home = String(cString: pw.pointee.pw_dir)
        let claudeDir = home + "/Library/Application Support/Claude"
        let dotClaudeDir = home + "/.claude"
        watchedDirectories = [claudeDir, dotClaudeDir]
        watchedFilenames = [
            claudeDir: "config.json",
            dotClaudeDir: ".credentials.json",
        ]
    }

    func startMonitoring() {
        stopMonitoring()
        for dir in watchedDirectories {
            let fd = open(dir, O_EVTONLY)
            guard fd >= 0 else { continue }
            fileDescriptors.append(fd)
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: .write, queue: queue
            )
            source.setEventHandler { [weak self] in self?.handleDirectoryChange(dir) }
            source.setCancelHandler { close(fd) }
            sources.append(source)
            source.resume()
            // Record initial modification date
            if let filename = watchedFilenames[dir] {
                lastModDates[dir + "/" + filename] = modDate(dir + "/" + filename)
            }
        }
    }

    func stopMonitoring() {
        for source in sources { source.cancel() }
        sources.removeAll()
        fileDescriptors.removeAll()
    }

    private func handleDirectoryChange(_ dir: String) {
        guard let filename = watchedFilenames[dir] else { return }
        let path = dir + "/" + filename
        let newDate = modDate(path)
        guard let date = newDate, date != lastModDates[path] else { return }
        lastModDates[path] = date
        let now = Date()
        guard now.timeIntervalSince(lastEmit) >= debounceInterval else { return }
        lastEmit = now
        subject.send(())
    }

    private func modDate(_ path: String) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }

    deinit { stopMonitoring() }
}
