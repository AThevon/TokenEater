import Foundation

final class UpdateService: NSObject, UpdateServiceProtocol, URLSessionDownloadDelegate {
    private let feedURL: URL
    private let currentVersion: String
    private var progressHandler: (@Sendable (Double) -> Void)?
    private var downloadContinuation: CheckedContinuation<URL, Error>?

    init(
        feedURL: URL = URL(string: "https://raw.githubusercontent.com/AThevon/TokenEater/main/docs/appcast.xml")!,
        currentVersion: String? = nil
    ) {
        self.feedURL = feedURL
        self.currentVersion = currentVersion
            ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0")
        super.init()
    }

    // MARK: - UpdateServiceProtocol

    func checkForUpdate() async throws -> AppcastItem? {
        let (data, _) = try await URLSession.shared.data(from: feedURL)
        let parser = AppcastXMLParser()
        parser.parse(data: data)
        guard let latest = parser.latestItem else { return nil }
        return VersionComparator.isNewer(latest.version, than: currentVersion) ? latest : nil
    }

    func downloadUpdate(from url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        self.progressHandler = progress
        return try await withCheckedThrowingContinuation { continuation in
            self.downloadContinuation = continuation
            let config = URLSessionConfiguration.default
            let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            session.downloadTask(with: url).resume()
        }
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("TokenEater.dmg")
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            downloadContinuation?.resume(returning: dest)
        } catch {
            downloadContinuation?.resume(throwing: error)
        }
        downloadContinuation = nil
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let pct = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler?(pct)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            downloadContinuation?.resume(throwing: error)
            downloadContinuation = nil
        }
    }
}

// MARK: - Appcast XML Parser

final class AppcastXMLParser: NSObject, XMLParserDelegate {
    private(set) var items: [AppcastItem] = []
    private var inItem = false
    private var currentElement = ""
    private var currentText = ""
    private var currentVersion: String?
    private var currentURL: String?
    private var currentSignature: String?
    private var currentLength: Int64?

    var latestItem: AppcastItem? {
        items.max { VersionComparator.compare($0.version, $1.version) == .orderedAscending }
    }

    func parse(data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = qName ?? elementName
        if name == "item" {
            inItem = true
            currentVersion = nil
            currentURL = nil
            currentSignature = nil
            currentLength = nil
        } else if inItem {
            currentElement = name
            currentText = ""
            if name == "enclosure" {
                currentURL = attributeDict["url"]
                currentSignature = attributeDict["sparkle:edSignature"]
                currentLength = attributeDict["length"].flatMap(Int64.init)
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inItem { currentText += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = qName ?? elementName
        if name == "item" {
            if let version = currentVersion,
               let urlString = currentURL,
               let url = URL(string: urlString) {
                items.append(
                    AppcastItem(
                        version: version,
                        downloadURL: url,
                        edSignature: currentSignature,
                        expectedLength: currentLength
                    )
                )
            }
            inItem = false
        } else if inItem && name == "sparkle:version" {
            currentVersion = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
