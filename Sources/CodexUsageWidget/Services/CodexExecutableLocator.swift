import AppKit
import Foundation

enum CodexExecutableLocator {
    static func resolve() -> URL? {
        var applications: [URL] = []
        // Resolve the bundle identity first so renamed or relocated apps work.
        if let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") {
            applications.append(application)
        }
        applications.append(contentsOf: [
            URL(fileURLWithPath: "/Applications/ChatGPT.app"),
            URL(fileURLWithPath: "/Applications/Codex.app")
        ])
        return resolve(applicationURLs: applications, cliPaths: [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex"
        ])
    }

    static func resolve(applicationURLs: [URL], cliPaths: [String]) -> URL? {
        let bundlePaths = [
            "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "Contents/Resources/codex-cli/bin/codex",
            "Contents/Resources/codex"
        ]
        let candidates = applicationURLs.flatMap { application in
            bundlePaths.map { application.appendingPathComponent($0) }
        } + cliPaths.map { URL(fileURLWithPath: $0) }
        return candidates.first {
            let values = try? $0.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true && FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }
}
