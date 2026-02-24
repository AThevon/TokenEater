import Foundation

struct GitHubRelease: Codable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: String
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case assets
    }
}

struct GitHubAsset: Codable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

struct UpdateInfo: Sendable {
    let version: String
    let releaseNotes: String?
    let downloadURL: URL?
    let releaseURL: URL
}
