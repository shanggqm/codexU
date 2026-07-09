import Foundation

enum AppArchitecture: String, Codable, Equatable {
    case arm64
    case x86_64
    case unknown

    static var current: AppArchitecture {
        #if arch(arm64)
        return .arm64
        #elseif arch(x86_64)
        return .x86_64
        #else
        return .unknown
        #endif
    }

    init(assetName: String) {
        let normalized = assetName.lowercased()
        if normalized.contains("arm64") || normalized.contains("apple-silicon") || normalized.contains("aarch64") {
            self = .arm64
        } else if normalized.contains("x86_64") || normalized.contains("intel") || normalized.contains("amd64") {
            self = .x86_64
        } else {
            self = .unknown
        }
    }
}

enum AppUpdateStatus: String, Codable, Equatable {
    case idle
    case disabled
    case checking
    case upToDate
    case updateAvailable
    case failed
}

struct AppVersion: Codable, Equatable, Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int
    let prereleaseLabel: String?
    let prereleaseNumber: Int?

    init?(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withoutPrefix: String
        if trimmed.lowercased().hasPrefix("v") {
            withoutPrefix = String(trimmed.dropFirst())
        } else {
            withoutPrefix = trimmed
        }

        let parts = withoutPrefix.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numberParts = parts[0].split(separator: ".")
        guard numberParts.count == 3,
              let major = Int(numberParts[0]),
              let minor = Int(numberParts[1]),
              let patch = Int(numberParts[2])
        else { return nil }

        self.major = major
        self.minor = minor
        self.patch = patch

        guard parts.count > 1 else {
            prereleaseLabel = nil
            prereleaseNumber = nil
            return
        }

        let prerelease = parts[1]
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "_", with: "")
        let label = prerelease.prefix { $0.isLetter }
        let number = prerelease.dropFirst(label.count)
        prereleaseLabel = label.isEmpty ? String(prerelease) : String(label)
        prereleaseNumber = number.isEmpty ? nil : Int(number)
    }

    var description: String {
        let base = "\(major).\(minor).\(patch)"
        guard let prereleaseLabel else { return base }
        if let prereleaseNumber {
            return "\(base)-\(prereleaseLabel)\(String(format: "%02d", prereleaseNumber))"
        }
        return "\(base)-\(prereleaseLabel)"
    }

    var isPrerelease: Bool {
        prereleaseLabel != nil
    }

    static func current(bundle: Bundle = .main) -> String {
        bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        switch (lhs.prereleaseLabel, rhs.prereleaseLabel) {
        case (nil, nil):
            return false
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        case let (lhsLabel?, rhsLabel?):
            let lhsRank = prereleaseRank(lhsLabel)
            let rhsRank = prereleaseRank(rhsLabel)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if lhsLabel != rhsLabel { return lhsLabel < rhsLabel }
            return (lhs.prereleaseNumber ?? 0) < (rhs.prereleaseNumber ?? 0)
        }
    }

    private static func prereleaseRank(_ label: String) -> Int {
        switch label {
        case "alpha", "a":
            return 0
        case "beta", "b":
            return 1
        case "rc":
            return 2
        default:
            return -1
        }
    }
}

struct GitHubReleaseAsset: Codable, Equatable, Identifiable {
    let name: String
    let browserDownloadURL: URL
    let size: Int64
    let contentType: String?

    var id: String { browserDownloadURL.absoluteString }
    var architecture: AppArchitecture { AppArchitecture(assetName: name) }
    var isDMG: Bool { name.lowercased().hasSuffix(".dmg") }

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
        case contentType = "content_type"
    }
}

struct GitHubReleaseInfo: Codable, Equatable, Identifiable {
    let tagName: String
    let name: String
    let htmlURL: URL
    let publishedAt: Date?
    let prerelease: Bool
    let draft: Bool
    let body: String
    let assets: [GitHubReleaseAsset]

    var id: String { tagName }
    var version: AppVersion? { AppVersion(tagName) }
    var versionLabel: String { version?.description ?? tagName }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case prerelease
        case draft
        case body
        case assets
    }

    init(
        tagName: String,
        name: String,
        htmlURL: URL,
        publishedAt: Date?,
        prerelease: Bool,
        draft: Bool,
        body: String,
        assets: [GitHubReleaseAsset]
    ) {
        self.tagName = tagName
        self.name = name
        self.htmlURL = htmlURL
        self.publishedAt = publishedAt
        self.prerelease = prerelease
        self.draft = draft
        self.body = body
        self.assets = assets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? tagName
        htmlURL = try container.decode(URL.self, forKey: .htmlURL)
        publishedAt = try container.decodeIfPresent(Date.self, forKey: .publishedAt)
        prerelease = try container.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false
        draft = try container.decodeIfPresent(Bool.self, forKey: .draft) ?? false
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        assets = try container.decodeIfPresent([GitHubReleaseAsset].self, forKey: .assets) ?? []
    }

    func preferredAsset(for architecture: AppArchitecture) -> GitHubReleaseAsset? {
        let dmgAssets = assets.filter(\.isDMG)
        guard !dmgAssets.isEmpty else { return nil }

        if architecture == .unknown {
            return dmgAssets.first
        }

        let matching = dmgAssets.filter { $0.architecture == architecture }
        guard !matching.isEmpty else { return nil }

        let expectedVersion = version?.description.lowercased()
        return matching.first { asset in
            let normalized = asset.name.lowercased()
            return normalized.contains("codexu")
                && expectedVersion.map { normalized.contains($0) } ?? true
        } ?? matching.first
    }
}

struct AppUpdateResult: Codable, Equatable {
    let status: AppUpdateStatus
    let checkedAt: Date
    let currentVersion: String
    let latestRelease: GitHubReleaseInfo?
    let preferredAsset: GitHubReleaseAsset?
    let errorMessage: String?

    static func idle(currentVersion: String = AppVersion.current()) -> AppUpdateResult {
        AppUpdateResult(
            status: .idle,
            checkedAt: Date(),
            currentVersion: currentVersion,
            latestRelease: nil,
            preferredAsset: nil,
            errorMessage: nil
        )
    }

    func refreshed(at date: Date) -> AppUpdateResult {
        AppUpdateResult(
            status: status,
            checkedAt: date,
            currentVersion: currentVersion,
            latestRelease: latestRelease,
            preferredAsset: preferredAsset,
            errorMessage: errorMessage
        )
    }

    var latestVersionLabel: String? {
        latestRelease?.versionLabel
    }

    var releaseURL: URL? {
        latestRelease?.htmlURL
    }

    var preferredOpenURL: URL? {
        preferredAsset?.browserDownloadURL ?? latestRelease?.htmlURL
    }
}

struct AppUpdateCache: Codable, Equatable {
    let schemaVersion: Int
    let checkedAt: Date
    let etag: String?
    let result: AppUpdateResult
}

enum AppUpdateSelfTest {
    static func run() -> Bool {
        var failures: [String] = []

        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() {
                failures.append(message)
            }
        }

        guard let beta01 = AppVersion("v1.0.0-beta01"),
              let beta02 = AppVersion("1.0.0-beta02"),
              let stable = AppVersion("1.0.0"),
              let nextPatch = AppVersion("1.0.1")
        else {
            print("update self-test failed: version parsing returned nil")
            return false
        }

        expect(beta01 < beta02, "beta01 should be lower than beta02")
        expect(beta02 < stable, "stable should be higher than beta")
        expect(stable < nextPatch, "next patch should be higher than current stable")
        expect(AppArchitecture(assetName: "codexU-1.0.0-mac-arm64.dmg") == .arm64, "arm64 asset detection")
        expect(AppArchitecture(assetName: "codexU-1.0.0-mac-x86_64.dmg") == .x86_64, "x86_64 asset detection")

        let fixture = """
        [
          {
            "tag_name": "v1.0.0-beta03",
            "name": "codexU v1.0.0-beta03",
            "html_url": "https://github.com/shanggqm/codexU/releases/tag/v1.0.0-beta03",
            "published_at": "2026-07-09T12:00:00Z",
            "prerelease": true,
            "draft": false,
            "body": "Beta update",
            "assets": [
              {
                "name": "codexU-1.0.0-beta03-mac-arm64.dmg",
                "browser_download_url": "https://github.com/shanggqm/codexU/releases/download/v1.0.0-beta03/codexU-1.0.0-beta03-mac-arm64.dmg",
                "size": 1234,
                "content_type": "application/octet-stream"
              }
            ]
          }
        ]
        """.data(using: .utf8)!

        do {
            let releases = try AppUpdateJSON.decoder.decode([GitHubReleaseInfo].self, from: fixture)
            let result = GitHubReleaseUpdateChecker.evaluate(
                releases: releases,
                currentVersion: "1.0.0-beta02",
                includePrereleases: true,
                checkedAt: Date(timeIntervalSince1970: 0),
                architecture: .arm64
            )
            expect(result.status == .updateAvailable, "fixture should produce updateAvailable")
            expect(result.latestVersionLabel == "1.0.0-beta03", "latest version label should normalize beta03")
            expect(result.preferredAsset?.architecture == .arm64, "preferred asset should match architecture")

            let revalidated = GitHubReleaseUpdateChecker.revalidateCachedResult(
                result,
                currentVersion: "1.0.0-beta03",
                includePrereleases: true,
                checkedAt: Date(timeIntervalSince1970: 1),
                architecture: .arm64
            )
            expect(revalidated.status == .upToDate, "cached beta03 release should be up to date after installing beta03")
            expect(revalidated.currentVersion == "1.0.0-beta03", "revalidated cache should use the running app version")
            expect(revalidated.preferredAsset == nil, "up-to-date cache result should not keep a download asset")
        } catch {
            failures.append("fixture decode failed: \(error.localizedDescription)")
        }

        if failures.isEmpty {
            print("update self-test passed")
            return true
        }

        print("update self-test failed")
        for failure in failures {
            print("- \(failure)")
        }
        return false
    }
}

enum AppUpdateJSON {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
