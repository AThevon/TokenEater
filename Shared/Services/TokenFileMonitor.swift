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

    /// The real home directory, not the sandbox container. Same `getpwuid`
    /// trick `SharedFileService` uses, and for the same reason.
    private static var realHomeDirectory: URL {
        let pw = getpwuid(getuid())
        if let dir = pw?.pointee.pw_dir.flatMap({ String(cString: $0) }), !dir.isEmpty {
            return URL(fileURLWithPath: dir)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    private func stop() {
        for work in pending.values { work.cancel() }
        pending.removeAll()
        for source in sources.values { source.cancel() }
        sources.removeAll()
    }

    /// - Returns: true when a directory that did not exist a moment ago is now
    ///   being watched, which means anything written to it in the meantime has
    ///   not been reported by any source.
    @discardableResult
    private func reconcileWatches() -> Bool {
        var directories = Set<URL>()
        // Climb to the nearest existing ancestor so a directory created later
        // (a first Codex login, say) is still noticed: the ancestor's own
        // vnode reports the new child, and `handleDirectoryChange` re-runs
        // this pass to attach to it. Capped at the real home directory:
        // without a ceiling, a machine with neither provider's directory
        // watched the volume root, and every write anywhere on the disk woke
        // this queue.
        //
        // So on a machine with no `~/.codex` the climb does stop at home and
        // home does get a watch. That is deliberate, and it is the price of
        // noticing a first login without a relaunch: home sees a handful of
        // events a day where "/" saw thousands, and every event costs three
        // `stat` calls that publish nothing unless a fingerprint moved.
        let home = Self.realHomeDirectory
        for file in watchedFiles {
            var directory = file.deletingLastPathComponent()
            while !FileManager.default.fileExists(atPath: directory.path),
                  directory.path != home.path,
                  directory.path != "/" {
                directory = directory.deletingLastPathComponent()
            }
            // The climb ends at home or at "/", both of which exist, so there
            // is nothing to test for existence here. "/" is only reachable
            // from a path outside home, which no watched file is today, and
            // watching it is the exact regression the ceiling prevents.
            guard directory.path != "/" else { continue }
            directories.insert(directory)
        }
        for directory in Array(sources.keys) where !directories.contains(directory) {
            sources.removeValue(forKey: directory)?.cancel()
        }
        var attached = false
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
            attached = true
        }
        return attached
    }

    private func handleDirectoryChange() {
        emitChanges()
        // A source only reports events that happen after it is attached. When
        // `~/.codex` is created and `auth.json` written in the same breath, the
        // pass above runs while the file does not exist yet and the watch lands
        // after the write, so nothing would ever report that first login. One
        // extra scan after attaching closes that window.
        if reconcileWatches() { emitChanges() }
    }

    private func emitChanges() {
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
