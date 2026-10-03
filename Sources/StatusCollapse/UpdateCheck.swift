import Foundation

/// A published release newer than the running app.
struct ReleaseInfo: Equatable {
    let version: String
    let url: URL
}

/// Asks GitHub for the latest release. Nothing is sent but the request itself (no identifier, no
/// version), and nothing is downloaded or installed: the user opens the release page.
enum UpdateCheck {
    /// The one place the repository is named, so renaming it is a one-line change.
    static let repository = "andyboltondev/status-menu-collapse"
    static let endpoint = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!

    /// Whether `remote` is a higher dotted version than `local`. Missing parts count as zero and
    /// anything non-numeric (a tag like "beta") is never newer.
    static func isNewer(_ remote: String, than local: String) -> Bool {
        guard let remote = components(remote), let local = components(local) else { return false }
        for index in 0..<max(remote.count, local.count) {
            let (a, b) = (index < remote.count ? remote[index] : 0, index < local.count ? local[index] : 0)
            if a != b { return a > b }
        }
        return false
    }

    private static func components(_ version: String) -> [Int]? {
        let trimmed = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        return parts.isEmpty || parts.contains(nil) ? nil : parts.compactMap { $0 }
    }

    /// Reads GitHub's "latest release" JSON. Drafts and pre-releases are ignored, and the page URL
    /// must be on github.com, since the app will open it.
    static func parse(_ data: Data) -> ReleaseInfo? {
        struct Payload: Decodable {
            let tag_name: String
            let html_url: String
            let draft: Bool?
            let prerelease: Bool?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.draft != true, payload.prerelease != true,
              let url = URL(string: payload.html_url), url.scheme == "https", url.host == "github.com",
              components(payload.tag_name) != nil
        else { return nil }
        let tag = payload.tag_name
        return ReleaseInfo(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, url: url)
    }

    enum Outcome: Equatable {
        case upToDate
        case available(ReleaseInfo)
        case failed
    }

    static func check(currentVersion: String) async -> Outcome {
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("StatusCollapse", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let release = parse(data)
        else { return .failed }
        return isNewer(release.version, than: currentVersion) ? .available(release) : .upToDate
    }
}
