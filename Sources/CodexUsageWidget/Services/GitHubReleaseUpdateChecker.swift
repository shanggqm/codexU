import Foundation

final class GitHubReleaseUpdateChecker {
    private let releasesURL: URL
    private let cacheURL: URL
    private let session: URLSession
    private let now: () -> Date
    private let minimumAutomaticCheckInterval: TimeInterval
    private let cacheSchemaVersion = 1

    init(
        owner: String = "shanggqm",
        repo: String = "codexU",
        cacheDirectory: URL = RuntimeLoadContext.live().cacheDirectory,
        session: URLSession = .shared,
        minimumAutomaticCheckInterval: TimeInterval = 24 * 60 * 60,
        now: @escaping () -> Date = Date.init
    ) {
        releasesURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases")!
        cacheURL = cacheDirectory.appendingPathComponent("update-check.json", isDirectory: false)
        self.session = session
        self.minimumAutomaticCheckInterval = minimumAutomaticCheckInterval
        self.now = now
    }

    func check(
        currentVersion: String,
        includePrereleases: Bool,
        force: Bool,
        completion: @escaping (AppUpdateResult) -> Void
    ) {
        let checkedAt = now()
        let cached = readCache()

        if !force,
           let cached,
           checkedAt.timeIntervalSince(cached.checkedAt) < minimumAutomaticCheckInterval {
            let result = Self.revalidateCachedResult(
                cached.result,
                currentVersion: currentVersion,
                includePrereleases: includePrereleases,
                checkedAt: cached.result.checkedAt,
                architecture: .current
            )
            if result != cached.result {
                writeCache(result: result, etag: cached.etag, checkedAt: cached.checkedAt)
            }
            completion(result)
            return
        }

        var request = URLRequest(url: releasesURL)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("codexU/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        if let etag = cached?.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            if let error {
                completion(self.failedResult(
                    currentVersion: currentVersion,
                    checkedAt: checkedAt,
                    message: error.localizedDescription,
                    cached: cached
                ))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(self.failedResult(
                    currentVersion: currentVersion,
                    checkedAt: checkedAt,
                    message: "Invalid GitHub response",
                    cached: cached
                ))
                return
            }

            if httpResponse.statusCode == 304, let cached {
                let refreshed = Self.revalidateCachedResult(
                    cached.result,
                    currentVersion: currentVersion,
                    includePrereleases: includePrereleases,
                    checkedAt: checkedAt,
                    architecture: .current
                )
                self.writeCache(result: refreshed, etag: cached.etag, checkedAt: checkedAt)
                completion(refreshed)
                return
            }

            guard (200..<300).contains(httpResponse.statusCode), let data else {
                let message = httpResponse.statusCode == 403
                    ? "GitHub rate limit reached. Try again later."
                    : "GitHub release request failed with HTTP \(httpResponse.statusCode)."
                completion(self.failedResult(
                    currentVersion: currentVersion,
                    checkedAt: checkedAt,
                    message: message,
                    cached: cached
                ))
                return
            }

            do {
                let releases = try AppUpdateJSON.decoder.decode([GitHubReleaseInfo].self, from: data)
                let result = Self.evaluate(
                    releases: releases,
                    currentVersion: currentVersion,
                    includePrereleases: includePrereleases,
                    checkedAt: checkedAt,
                    architecture: .current
                )
                self.writeCache(
                    result: result,
                    etag: Self.etag(from: httpResponse),
                    checkedAt: checkedAt
                )
                completion(result)
            } catch {
                completion(self.failedResult(
                    currentVersion: currentVersion,
                    checkedAt: checkedAt,
                    message: "Unable to parse GitHub release metadata.",
                    cached: cached
                ))
            }
        }.resume()
    }

    static func evaluate(
        releases: [GitHubReleaseInfo],
        currentVersion: String,
        includePrereleases: Bool,
        checkedAt: Date,
        architecture: AppArchitecture
    ) -> AppUpdateResult {
        guard let current = AppVersion(currentVersion) else {
            return AppUpdateResult(
                status: .failed,
                checkedAt: checkedAt,
                currentVersion: currentVersion,
                latestRelease: nil,
                preferredAsset: nil,
                errorMessage: "Unable to parse current app version."
            )
        }

        let candidates = releases.compactMap { release -> (release: GitHubReleaseInfo, version: AppVersion)? in
            guard !release.draft,
                  includePrereleases || !release.prerelease,
                  let version = release.version
            else { return nil }
            return (release, version)
        }
        .sorted { lhs, rhs in
            if lhs.version != rhs.version {
                return lhs.version > rhs.version
            }
            return (lhs.release.publishedAt ?? .distantPast) > (rhs.release.publishedAt ?? .distantPast)
        }

        guard let latest = candidates.first, latest.version > current else {
            return AppUpdateResult(
                status: .upToDate,
                checkedAt: checkedAt,
                currentVersion: currentVersion,
                latestRelease: candidates.first?.release,
                preferredAsset: nil,
                errorMessage: nil
            )
        }

        return AppUpdateResult(
            status: .updateAvailable,
            checkedAt: checkedAt,
            currentVersion: currentVersion,
            latestRelease: latest.release,
            preferredAsset: latest.release.preferredAsset(for: architecture),
            errorMessage: nil
        )
    }

    static func revalidateCachedResult(
        _ cachedResult: AppUpdateResult,
        currentVersion: String,
        includePrereleases: Bool,
        checkedAt: Date,
        architecture: AppArchitecture
    ) -> AppUpdateResult {
        guard let latestRelease = cachedResult.latestRelease else {
            return AppUpdateResult(
                status: cachedResult.status,
                checkedAt: checkedAt,
                currentVersion: currentVersion,
                latestRelease: nil,
                preferredAsset: nil,
                errorMessage: cachedResult.errorMessage
            )
        }

        return evaluate(
            releases: [latestRelease],
            currentVersion: currentVersion,
            includePrereleases: includePrereleases,
            checkedAt: checkedAt,
            architecture: architecture
        )
    }

    private func failedResult(
        currentVersion: String,
        checkedAt: Date,
        message: String,
        cached: AppUpdateCache?
    ) -> AppUpdateResult {
        AppUpdateResult(
            status: .failed,
            checkedAt: checkedAt,
            currentVersion: currentVersion,
            latestRelease: cached?.result.latestRelease,
            preferredAsset: cached?.result.preferredAsset,
            errorMessage: message
        )
    }

    private func readCache() -> AppUpdateCache? {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? AppUpdateJSON.decoder.decode(AppUpdateCache.self, from: data),
              cache.schemaVersion == cacheSchemaVersion
        else { return nil }
        return cache
    }

    private func writeCache(result: AppUpdateResult, etag: String?, checkedAt: Date) {
        let cache = AppUpdateCache(
            schemaVersion: cacheSchemaVersion,
            checkedAt: checkedAt,
            etag: etag,
            result: result
        )
        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try AppUpdateJSON.encoder.encode(cache)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            // Cache writes are best effort; update checks should never break the app.
        }
    }

    private static func etag(from response: HTTPURLResponse) -> String? {
        response.value(forHTTPHeaderField: "ETag")
            ?? response.value(forHTTPHeaderField: "Etag")
            ?? response.value(forHTTPHeaderField: "etag")
    }
}
