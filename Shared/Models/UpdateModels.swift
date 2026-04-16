import Foundation

enum BrewMigrationState: Equatable {
    case notNeeded
    case detected
    case dismissed
}

struct AppcastItem: Equatable {
    let version: String
    let downloadURL: URL
    let edSignature: String?
    let expectedLength: Int64?

    init(
        version: String,
        downloadURL: URL,
        edSignature: String? = nil,
        expectedLength: Int64? = nil
    ) {
        self.version = version
        self.downloadURL = downloadURL
        self.edSignature = edSignature
        self.expectedLength = expectedLength
    }
}

enum UpdateState: Equatable {
    case idle
    case checking
    case available(version: String, downloadURL: URL, signature: String?, expectedLength: Int64?)
    case downloading(progress: Double)
    case downloaded(fileURL: URL, signature: String?, expectedLength: Int64?)
    case installing
    case upToDate
    case error(String)

    var isModalVisible: Bool {
        switch self {
        case .available, .downloading, .downloaded, .installing, .error:
            return true
        default:
            return false
        }
    }

    var availableVersion: String? {
        if case .available(let version, _, _, _) = self { return version }
        return nil
    }
}

enum VersionComparator {
    static func isNewer(_ v1: String, than v2: String) -> Bool {
        compare(v1, v2) == .orderedDescending
    }

    static func compare(_ v1: String, _ v2: String) -> ComparisonResult {
        let (base1, pre1) = splitVersion(v1)
        let (base2, pre2) = splitVersion(v2)

        let nums1 = base1.components(separatedBy: ".").compactMap { Int($0) }
        let nums2 = base2.components(separatedBy: ".").compactMap { Int($0) }

        let maxLen = max(nums1.count, nums2.count)
        for i in 0..<maxLen {
            let n1 = i < nums1.count ? nums1[i] : 0
            let n2 = i < nums2.count ? nums2[i] : 0
            if n1 > n2 { return .orderedDescending }
            if n1 < n2 { return .orderedAscending }
        }

        if pre1 == nil && pre2 != nil { return .orderedDescending }
        if pre1 != nil && pre2 == nil { return .orderedAscending }

        if let p1 = pre1, let p2 = pre2 {
            return p1.compare(p2, options: .numeric)
        }
        return .orderedSame
    }

    private static func splitVersion(_ v: String) -> (base: String, preRelease: String?) {
        let cleaned = v.hasPrefix("v") ? String(v.dropFirst()) : v
        let parts = cleaned.components(separatedBy: "-")
        return (parts[0], parts.count > 1 ? parts.dropFirst().joined(separator: "-") : nil)
    }
}
