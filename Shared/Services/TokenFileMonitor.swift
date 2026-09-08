import Foundation
import Combine

final class TokenFileMonitor: TokenFileMonitorProtocol {

    // MARK: - Nested Types

    private struct Fingerprint: Equatable {
        let modified: Date?
        let inode: UInt64?
        let size: UInt64?
    }

    // MARK: - Internal Properties

    var tokenChanged: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }
    var codexAuthChanged: AnyPublisher<Void, Never> { codexSubject.eraseToAnyPublisher() }

    // MARK: - Private Properties

    private let subject = PassthroughSubject<Void, Never>()
    private let codexSubject = PassthroughSubject<Void, Never>()
    private let queue = DispatchQueue(label: "com.tokeneater.filemonitor", qos: .utility)
    private let queueKey = DispatchSpecificKey<Bool>()
    private let debounceInterval: TimeInterval
    private let watchedFiles: [URL]
    private let codexAuthURL: URL
    private var sources: [URL: DispatchSourceFileSystemObject] = [:]
    private var fingerprints: [URL: Fingerprint] = [:]
    private var pending: [Bool: DispatchWorkItem] = [:]

    // MARK: - Initializers

    init(debounceInterval: TimeInterval = 2.0, homeDirectory: URL? = nil, codexHomeURL: URL? = nil) {
        self.debounceInterval = debounceInterval
        queue.setSpecific(key: queueKey, value: true)
        let home = homeDirectory ?? URL(fileURLWithPath: getpwuid(getuid()).map {
            String(cString: $0.pointee.pw_dir)
        } ?? NSHomeDirectory())
        codexAuthURL = (codexHomeURL ?? CodexAuthReader().codexHomeURL)
            .appendingPathComponent("auth.json")
        watchedFiles = [
            home.appendingPathComponent("Library/Application Support/Claude/config.json"),
            home.appendingPathComponent(".claude/.credentials.json"),
            codexAuthURL,
        ]
    }

    deinit { stopMonitoring() }

    // MARK: - TokenFileMonitorProtocol

    func startMonitoring() {
        queue.sync {
            stop()
            for file in watchedFiles { fingerprints[file] = fingerprint(file) }
            reconcileWatches()
        }
    }

    func stopMonitoring() {
        if DispatchQueue.getSpecific(key: queueKey) == true { stop() }
        else { queue.sync { stop() } }
    }

    // MARK: - Private Methods

    private func stop() {
        for work in pending.values { work.cancel() }
        pending.removeAll()
        for source in sources.values { source.cancel() }
        sources.removeAll()
    }

    private func reconcileWatches() {
        var directories = Set<URL>()
        for file in watchedFiles {
            var directory = file.deletingLastPathComponent()
            while !FileManager.default.fileExists(atPath: directory.path), directory.path != "/" {
                directory = directory.deletingLastPathComponent()
            }
            directories.insert(directory)
        }
        for directory in Array(sources.keys) where !directories.contains(directory) {
            sources.removeValue(forKey: directory)?.cancel()
        }
        for directory in directories where sources[directory] == nil {
            let fd = open(directory.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: queue
            )
            source.setEventHandler { [weak self] in
                guard let self else { return }
                if let data = self.sources[directory]?.data, !data.intersection([.delete, .rename]).isEmpty {
                    self.sources.removeValue(forKey: directory)?.cancel()
                }
                self.handleDirectoryChange()
            }
            source.setCancelHandler { close(fd) }
            sources[directory] = source
            source.resume()
        }
    }

    private func handleDirectoryChange() {
        for file in watchedFiles {
            let current = fingerprint(file)
            guard current != fingerprints[file] else { continue }
            fingerprints[file] = current
            let isCodex = file == codexAuthURL
            pending[isCodex]?.cancel()
            let publisher = isCodex ? codexSubject : subject
            let work = DispatchWorkItem { publisher.send(()) }
            pending[isCodex] = work
            queue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
        }
        reconcileWatches()
    }

    private func fingerprint(_ url: URL) -> Fingerprint? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return Fingerprint(
            modified: attributes[.modificationDate] as? Date,
            inode: attributes[.systemFileNumber] as? UInt64,
            size: attributes[.size] as? UInt64
        )
    }
}
