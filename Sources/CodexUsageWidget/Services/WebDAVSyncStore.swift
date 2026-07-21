import Combine
import Foundation
import Security

struct SyncedStatusItemConfiguration: Codable, Equatable {
    let displayMode: StatusItemDisplayMode
    let quotaMode: QuotaDisplayMode
    let visibleMetrics: [StatusItemMetric]
    let showsResetCountdown: Bool

    init(_ preferences: StatusItemPreferences) {
        displayMode = preferences.displayMode
        quotaMode = preferences.quotaMode
        visibleMetrics = preferences.orderedVisibleMetrics
        showsResetCountdown = preferences.showsResetCountdown
    }

    var preferences: StatusItemPreferences {
        StatusItemPreferences(
            displayMode: displayMode,
            quotaMode: quotaMode,
            visibleMetrics: Set(visibleMetrics),
            showsResetCountdown: showsResetCountdown
        ).normalized()
    }
}

struct SyncedCodexUConfiguration: Codable, Equatable {
    let language: WidgetLanguage
    let themeMode: WidgetThemeMode
    let visibleRuntimeScopes: [RuntimeScope]
    let statisticsTimeZone: StatisticsTimeZonePreference
    let statusItem: SyncedStatusItemConfiguration
    let keepMainWindowOnTop: Bool
    let keepRunningWhenMainWindowClosed: Bool
    let automaticUpdateChecksEnabled: Bool
}

private struct WebDAVConfigurationEnvelope: Codable {
    let schemaVersion: Int
    let exportedAt: Date
    let configuration: SyncedCodexUConfiguration
}

struct WebDAVConnectionConfiguration: Equatable {
    var serverAddress: String
    var username: String
    var remoteDirectory: String
    var profileName: String
    var automaticSyncEnabled: Bool

    static let `default` = WebDAVConnectionConfiguration(
        serverAddress: "",
        username: "",
        remoteDirectory: "codexu-sync",
        profileName: "default",
        automaticSyncEnabled: false
    )
}

enum WebDAVSyncPhase: Equatable {
    case idle
    case working
    case success(String, String)
    case failure(String, String)

    var isWorking: Bool {
        if case .working = self { return true }
        return false
    }

    func message(language: WidgetLanguage) -> String? {
        switch self {
        case .idle, .working:
            return nil
        case let .success(zh, en), let .failure(zh, en):
            return language.text(zh, en)
        }
    }
}

enum WebDAVSyncError: Error {
    case invalidServerAddress
    case insecureServerAddress
    case missingCredentials
    case invalidRemotePath
    case unexpectedResponse
    case httpStatus(Int)
    case incompatibleConfiguration
    case invalidConfiguration

    func message(language: WidgetLanguage) -> String {
        switch self {
        case .invalidServerAddress:
            return language.text("请输入有效的WebDAV服务器地址", "Enter a valid WebDAV server address")
        case .insecureServerAddress:
            return language.text("WebDAV地址必须使用HTTPS", "The WebDAV address must use HTTPS")
        case .missingCredentials:
            return language.text("请输入WebDAV账户和密码", "Enter the WebDAV username and password")
        case .invalidRemotePath:
            return language.text("远程目录或配置名无效", "The remote directory or profile name is invalid")
        case .unexpectedResponse:
            return language.text("WebDAV服务器返回了无法识别的响应", "The WebDAV server returned an unexpected response")
        case let .httpStatus(status):
            return language.text("WebDAV请求失败（HTTP\(status)）", "WebDAV request failed (HTTP \(status))")
        case .incompatibleConfiguration:
            return language.text("云端配置版本不受支持", "The remote configuration version is not supported")
        case .invalidConfiguration:
            return language.text("云端配置内容无效", "The remote configuration is invalid")
        }
    }
}

@MainActor
final class WebDAVSyncStore: ObservableObject {
    private enum DefaultsKey {
        static let serverAddress = "codexU.webDAV.serverAddress"
        static let username = "codexU.webDAV.username"
        static let remoteDirectory = "codexU.webDAV.remoteDirectory"
        static let profileName = "codexU.webDAV.profileName"
        static let automaticSyncEnabled = "codexU.webDAV.automaticSyncEnabled"
        static let lastSyncAt = "codexU.webDAV.lastSyncAt"
    }

    @Published var serverAddress: String
    @Published var username: String
    @Published var password: String
    @Published var remoteDirectory: String
    @Published var profileName: String
    @Published var automaticSyncEnabled: Bool
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var phase: WebDAVSyncPhase = .idle

    private let settings: AppSettings
    private let usageStore: UsageStore
    private let defaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    private var automaticUploadTask: Task<Void, Never>?
    private var isApplyingRemoteConfiguration = false
    private var savedConnectionConfiguration: WebDAVConnectionConfiguration
    private var savedPassword: String

    init(settings: AppSettings, usageStore: UsageStore, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.usageStore = usageStore
        self.defaults = defaults

        let stored = Self.loadConnectionConfiguration(defaults: defaults)
        serverAddress = stored.serverAddress
        username = stored.username
        remoteDirectory = stored.remoteDirectory
        profileName = stored.profileName
        automaticSyncEnabled = stored.automaticSyncEnabled
        lastSyncAt = defaults.object(forKey: DefaultsKey.lastSyncAt) as? Date
        let storedPassword = WebDAVPasswordStore.load() ?? ""
        password = storedPassword
        savedConnectionConfiguration = stored
        savedPassword = storedPassword

        observeLocalConfiguration()
    }

    deinit {
        automaticUploadTask?.cancel()
    }

    var connectionConfiguration: WebDAVConnectionConfiguration {
        WebDAVConnectionConfiguration(
            serverAddress: serverAddress,
            username: username,
            remoteDirectory: remoteDirectory,
            profileName: profileName,
            automaticSyncEnabled: automaticSyncEnabled
        )
    }

    func saveConnectionConfiguration() {
        do {
            try WebDAVPasswordStore.save(password)
            let configuration = connectionConfiguration
            defaults.set(configuration.serverAddress.trimmingCharacters(in: .whitespacesAndNewlines), forKey: DefaultsKey.serverAddress)
            defaults.set(configuration.username.trimmingCharacters(in: .whitespacesAndNewlines), forKey: DefaultsKey.username)
            defaults.set(configuration.remoteDirectory.trimmingCharacters(in: .whitespacesAndNewlines), forKey: DefaultsKey.remoteDirectory)
            defaults.set(configuration.profileName.trimmingCharacters(in: .whitespacesAndNewlines), forKey: DefaultsKey.profileName)
            defaults.set(configuration.automaticSyncEnabled, forKey: DefaultsKey.automaticSyncEnabled)
            savedConnectionConfiguration = configuration
            savedPassword = password
            phase = .success("WebDAV配置已保存", "WebDAV settings saved")
        } catch {
            phase = .failure("密码无法保存到钥匙串", "The password could not be saved to Keychain")
        }
    }

    func testConnection() {
        perform {
            let client = try self.makeClient()
            try await client.testConnection()
            self.phase = .success("连接成功", "Connection successful")
        }
    }

    func uploadConfiguration(isAutomatic: Bool = false) {
        perform {
            let client = try self.makeClient()
            let configuration = self.settings.syncedConfiguration(
                statisticsTimeZone: self.usageStore.statisticsPreference
            )
            let envelope = WebDAVConfigurationEnvelope(
                schemaVersion: 1,
                exportedAt: Date(),
                configuration: configuration
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            try await client.upload(encoder.encode(envelope))
            self.recordSuccessfulSync()
            self.phase = .success(
                isAutomatic ? "配置已自动上传" : "配置已上传到WebDAV",
                isAutomatic ? "Settings uploaded automatically" : "Settings uploaded to WebDAV"
            )
        }
    }

    func downloadConfiguration() {
        perform {
            let client = try self.makeClient()
            let data = try await client.download()
            guard data.count <= 1_000_000 else {
                throw WebDAVSyncError.invalidConfiguration
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let envelope = try decoder.decode(WebDAVConfigurationEnvelope.self, from: data)
            guard envelope.schemaVersion == 1 else {
                throw WebDAVSyncError.incompatibleConfiguration
            }
            try self.backUpLocalConfiguration()
            self.isApplyingRemoteConfiguration = true
            defer { self.isApplyingRemoteConfiguration = false }
            guard self.settings.applySyncedConfiguration(envelope.configuration) else {
                throw WebDAVSyncError.invalidConfiguration
            }
            self.usageStore.updateStatisticsTimeZone(envelope.configuration.statisticsTimeZone)
            self.recordSuccessfulSync()
            self.phase = .success("已应用云端配置，本地旧配置已备份", "Remote settings applied; previous local settings were backed up")
        }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !phase.isWorking else { return }
        phase = .working
        Task { @MainActor in
            do {
                try await operation()
            } catch let error as WebDAVSyncError {
                phase = .failure(error.message(language: .zh), error.message(language: .en))
            } catch {
                phase = .failure("WebDAV操作失败，请检查网络和服务器配置", "WebDAV operation failed; check the network and server settings")
            }
        }
    }

    private func makeClient() throws -> WebDAVClient {
        try WebDAVClient(
            configuration: connectionConfiguration,
            password: password
        )
    }

    private func observeLocalConfiguration() {
        let settingsChanges: [AnyPublisher<Void, Never>] = [
            settings.$language.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$themeMode.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$visibleRuntimeScopes.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$statusItemPreferences.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$keepMainWindowOnTop.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$keepRunningWhenMainWindowClosed.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$automaticUpdateChecksEnabled.dropFirst().map { _ in () }.eraseToAnyPublisher()
        ]

        Publishers.MergeMany(settingsChanges)
            .sink { [weak self] _ in
                self?.scheduleAutomaticUpload()
            }
            .store(in: &cancellables)

        usageStore.$statisticsPreference
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleAutomaticUpload()
            }
            .store(in: &cancellables)
    }

    private func scheduleAutomaticUpload() {
        guard automaticSyncEnabled,
              !isApplyingRemoteConfiguration,
              connectionConfiguration == savedConnectionConfiguration,
              password == savedPassword,
              !serverAddress.isEmpty,
              !username.isEmpty,
              !password.isEmpty
        else { return }

        automaticUploadTask?.cancel()
        automaticUploadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, let self else { return }
            if self.phase.isWorking {
                self.scheduleAutomaticUpload()
                return
            }
            self.uploadConfiguration(isAutomatic: true)
        }
    }

    private func recordSuccessfulSync() {
        let now = Date()
        lastSyncAt = now
        defaults.set(now, forKey: DefaultsKey.lastSyncAt)
    }

    private func backUpLocalConfiguration() throws {
        let configuration = settings.syncedConfiguration(
            statisticsTimeZone: usageStore.statisticsPreference
        )
        let envelope = WebDAVConfigurationEnvelope(
            schemaVersion: 1,
            exportedAt: Date(),
            configuration: configuration
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)

        let fileManager = FileManager.default
        let baseDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let backupDirectory = baseDirectory
            .appendingPathComponent("codexU", isDirectory: true)
            .appendingPathComponent("Configuration Backups", isDirectory: true)
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backupURL = backupDirectory.appendingPathComponent("codexu-config-\(formatter.string(from: Date())).json")
        try data.write(to: backupURL, options: .atomic)
    }

    private static func loadConnectionConfiguration(defaults: UserDefaults) -> WebDAVConnectionConfiguration {
        let fallback = WebDAVConnectionConfiguration.default
        return WebDAVConnectionConfiguration(
            serverAddress: defaults.string(forKey: DefaultsKey.serverAddress) ?? fallback.serverAddress,
            username: defaults.string(forKey: DefaultsKey.username) ?? fallback.username,
            remoteDirectory: defaults.string(forKey: DefaultsKey.remoteDirectory) ?? fallback.remoteDirectory,
            profileName: defaults.string(forKey: DefaultsKey.profileName) ?? fallback.profileName,
            automaticSyncEnabled: defaults.bool(forKey: DefaultsKey.automaticSyncEnabled)
        )
    }
}

private struct WebDAVClient {
    private let baseURL: URL
    private let directoryComponents: [String]
    private let authorizationHeader: String
    private let session = URLSession(
        configuration: .ephemeral,
        delegate: WebDAVRedirectBlocker(),
        delegateQueue: nil
    )

    init(configuration: WebDAVConnectionConfiguration, password: String) throws {
        let address = configuration.serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: address),
              url.host != nil,
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil
        else {
            throw WebDAVSyncError.invalidServerAddress
        }
        guard url.scheme?.lowercased() == "https" else {
            throw WebDAVSyncError.insecureServerAddress
        }
        let username = configuration.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty, !password.isEmpty else {
            throw WebDAVSyncError.missingCredentials
        }

        let rawRemoteComponents = configuration.remoteDirectory
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        let remoteComponents = rawRemoteComponents.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let profile = configuration.profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remoteComponents.isEmpty,
              remoteComponents.allSatisfy({ !$0.isEmpty }),
              !profile.isEmpty,
              !profile.contains("/"),
              (remoteComponents + [profile]).allSatisfy({ $0 != "." && $0 != ".." })
        else {
            throw WebDAVSyncError.invalidRemotePath
        }

        baseURL = url.appendingPathComponent("", isDirectory: true)
        directoryComponents = remoteComponents + [profile]
        let credentials = Data("\(username):\(password)".utf8).base64EncodedString()
        authorizationHeader = "Basic \(credentials)"
    }

    func testConnection() async throws {
        var request = request(url: baseURL, method: "OPTIONS")
        request.timeoutInterval = 20
        let (_, response) = try await session.data(for: request)
        try validate(response, acceptedStatusCodes: 200..<300)
    }

    func upload(_ data: Data) async throws {
        try await createRemoteDirectories()
        var request = request(url: configurationFileURL, method: "PUT")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let (_, response) = try await session.data(for: request)
        try validate(response, acceptedStatusCodes: 200..<300)
    }

    func download() async throws -> Data {
        let request = request(url: configurationFileURL, method: "GET")
        let (data, response) = try await session.data(for: request)
        try validate(response, acceptedStatusCodes: 200..<300)
        return data
    }

    private var configurationFileURL: URL {
        directoryComponents.reduce(baseURL) { partial, component in
            partial.appendingPathComponent(component, isDirectory: true)
        }.appendingPathComponent("codexu-config.json", isDirectory: false)
    }

    private func createRemoteDirectories() async throws {
        var currentURL = baseURL
        for component in directoryComponents {
            currentURL.appendPathComponent(component, isDirectory: true)
            let request = request(url: currentURL, method: "MKCOL")
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw WebDAVSyncError.unexpectedResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) || httpResponse.statusCode == 405 else {
                throw WebDAVSyncError.httpStatus(httpResponse.statusCode)
            }
        }
    }

    private func request(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("codexU WebDAV Sync", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func validate(_ response: URLResponse, acceptedStatusCodes: Range<Int>) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebDAVSyncError.unexpectedResponse
        }
        guard acceptedStatusCodes.contains(httpResponse.statusCode) else {
            throw WebDAVSyncError.httpStatus(httpResponse.statusCode)
        }
    }
}

private final class WebDAVRedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

enum WebDAVSyncSelfTest {
    static func run() -> Bool {
        var failures: [String] = []
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { failures.append(message) }
        }

        expect(
            webDAVKeychainService.hasPrefix("com.guomeiqing.codexu"),
            "Keychain service must use the app bundle identifier prefix"
        )

        let configuration = SyncedCodexUConfiguration(
            language: .zh,
            themeMode: .dark,
            visibleRuntimeScopes: [.codex, .claudeCode],
            statisticsTimeZone: StatisticsTimeZonePreference(
                selection: .fixed,
                fixedIdentifier: "Asia/Shanghai"
            ),
            statusItem: SyncedStatusItemConfiguration(.default),
            keepMainWindowOnTop: true,
            keepRunningWhenMainWindowClosed: true,
            automaticUpdateChecksEnabled: false
        )
        let envelope = WebDAVConfigurationEnvelope(
            schemaVersion: 1,
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
            configuration: configuration
        )

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(envelope)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(WebDAVConfigurationEnvelope.self, from: data)
            expect(decoded.schemaVersion == 1, "schema version round trip")
            expect(decoded.configuration == configuration, "configuration round trip")

            let json = String(decoding: data, as: UTF8.self).lowercased()
            for forbiddenKey in ["password", "username", "serveraddress", "globalshortcut", "state_5.sqlite", "thread", "skill"] {
                expect(!json.contains(forbiddenKey), "payload must not contain \(forbiddenKey)")
            }
        } catch {
            failures.append("configuration encoding failed")
        }

        do {
            _ = try WebDAVClient(
                configuration: WebDAVConnectionConfiguration(
                    serverAddress: "http://dav.example.com/",
                    username: "user",
                    remoteDirectory: "codexu-sync",
                    profileName: "default",
                    automaticSyncEnabled: false
                ),
                password: "secret"
            )
            failures.append("HTTP server should be rejected")
        } catch WebDAVSyncError.insecureServerAddress {
            // Expected.
        } catch {
            failures.append("HTTP server rejected with the wrong error")
        }

        do {
            _ = try WebDAVClient(
                configuration: WebDAVConnectionConfiguration(
                    serverAddress: "https://dav.example.com/",
                    username: "user",
                    remoteDirectory: "../private",
                    profileName: "default",
                    automaticSyncEnabled: false
                ),
                password: "secret"
            )
            failures.append("path traversal should be rejected")
        } catch WebDAVSyncError.invalidRemotePath {
            // Expected.
        } catch {
            failures.append("path traversal rejected with the wrong error")
        }

        if failures.isEmpty {
            print("WebDAV sync self-test passed")
            return true
        }
        for failure in failures {
            print("WebDAV sync self-test failed: \(failure)")
        }
        return false
    }
}

private let webDAVKeychainService = "com.guomeiqing.codexu.webdav"

private enum WebDAVPasswordStore {
    private static let service = webDAVKeychainService
    private static let account = "default"

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ password: String) throws {
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        if password.isEmpty {
            SecItemDelete(lookup as CFDictionary)
            return
        }

        let data = Data(password.utf8)
        let updateStatus = SecItemUpdate(
            lookup as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(updateStatus))
        }

        var insert = lookup
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        guard insertStatus == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(insertStatus))
        }
    }
}
