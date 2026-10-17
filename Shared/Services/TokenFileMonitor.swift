import Foundation
import Combine

final class TokenFileMonitor: TokenFileMonitorProtocol {

    // MARK: - Nested Types

    private struct Fingerprint: Equatable {
        let modified: Date?
        let inode: UInt64?
        let size: UInt64?
    }

    /// Who a watched file belongs to, which decides the publisher it fires.
    private enum Owner: Hashable {
        case claudeMain
        case claudeAccount(AccountID)
        case codex
    }

    // MARK: - Internal Properties

    var tokenChanged: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }
    var codexAuthChanged: AnyPublisher<Void, Never> { codexSubject.eraseToAnyPublisher() }
    var accountTokenChanged: AnyPublisher<AccountID, Never> { accountSubject.eraseToAnyPublisher() }

    // MARK: - Private Properties

    private let subject = PassthroughSubject<Void, Never>()
    private let codexSubject = PassthroughSubject<Void, Never>()
    private let accountSubject = PassthroughSubject<AccountID, Never>()
    private let queue = DispatchQueue(label: "com.tokeneater.filemonitor", qos: .utility)
    private let queueKey = DispatchSpecificKey<Bool>()
    private let debounceInterval: TimeInterval
    private let codexAuthURL: URL
    /// The files watched and whose they are. Mutated only on `queue`.
    private var owners: [URL: Owner]
    private var watchedFiles: [URL] { Array(owners.keys) }
    private var isMonitoring = false
    private var sources: [URL: DispatchSourceFileSystemObject] = [:]
    private var fingerprints: [URL: Fingerprint] = [:]
    private var pending: [Owner: DispatchWorkItem] = [:]

    // MARK: - Initializers

    init(debounceInterval: TimeInterval = 2.0, homeDirectory: URL? = nil, codexHomeURL: URL? = nil) {
        self.debounceInterval = debounceInterval
        queue.setSpecific(key: queueKey, value: true)
        let home = homeDirectory ?? URL(fileURLWithPath: getpwuid(getuid()).map {
            String(cString: $0.pointee.pw_dir)
        } ?? NSHomeDirectory())
        let codexAuthURL = (codexHomeURL ?? CodexAuthReader().codexHomeURL)
            .appendingPathComponent("auth.json")
        self.codexAuthURL = codexAuthURL
        let desktopConfigURL = home.appendingPathComponent("Library/Application Support/Claude/config.json")
        self.desktopConfigURL = desktopConfigURL
        owners = [
            desktopConfigURL: .claudeMain,
            home.appendingPathComponent(".claude/.credentials.json"): .claudeMain,
            codexAuthURL: .codex,
        ]
    }

    /// Claude Desktop's config, watched for the main account while it reads
    /// the default chain.
    private let desktopConfigURL: URL

    /// Swaps the Claude credential files watched: the main account's (its
    /// folder's `.credentials.json`, plus Claude Desktop's config when its
    /// scope reads it) and each added account's. Codex is unaffected. A file
    /// that is new to the watch starts from its current state, so swapping
    /// does not by itself report a change.
    func setClaudeCredentialFiles(main: URL, includeDesktopConfig: Bool, extras: [AccountID: URL]) {
        let apply = {
            var next: [URL: Owner] = [self.codexAuthURL: .codex]
            for (id, url) in extras where !id.isMain { next[url.standardizedFileURL] = .claudeAccount(id) }
            next[main.standardizedFileURL] = .claudeMain
            if includeDesktopConfig { next[self.desktopConfigURL] = .claudeMain }
            guard next != self.owners else { return }
            for url in self.owners.keys where next[url] == nil {
                self.fingerprints.removeValue(forKey: url)
            }
            for url in next.keys where self.owners[url] == nil {
                self.fingerprints[url] = self.fingerprint(url)
            }
            self.owners = next
            if self.isMonitoring { self.reconcileWatches() }
        }
        if DispatchQueue.getSpecific(key: queueKey) == true { apply() } else { queue.sync(execute: apply) }
    }

    deinit { stopMonitoring() }

    // MARK: - TokenFileMonitorProtocol

    func startMonitoring() {
        queue.sync {
            stop()
            isMonitoring = true
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
        isMonitoring = false
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
        for (file, owner) in owners {
            let current = fingerprint(file)
            guard current != fingerprints[file] else { continue }
            fingerprints[file] = current
            pending[owner]?.cancel()
            let work: DispatchWorkItem
            switch owner {
            case .claudeMain:
                let publisher = subject
                work = DispatchWorkItem { publisher.send(()) }
            case .codex:
                let publisher = codexSubject
                work = DispatchWorkItem { publisher.send(()) }
            case .claudeAccount(let id):
                let publisher = accountSubject
                work = DispatchWorkItem { publisher.send(id) }
            }
            pending[owner] = work
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
