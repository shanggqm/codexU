import Foundation
import Security

enum CPAConfigurationError: Error, Equatable {
    case missingBaseURL
    case missingManagementKey
    case invalidBaseURL
    case insecureRemoteURL
}

struct CPAConfiguration: Equatable {
    let isEnabled: Bool
    let baseURL: String
    let managementKey: String

    static let defaultBaseURL = "http://127.0.0.1:8317"

    func validatedBaseURL() throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CPAConfigurationError.missingBaseURL }
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              !host.isEmpty,
              (scheme == "http" || scheme == "https"),
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil
        else {
            throw CPAConfigurationError.invalidBaseURL
        }

        if scheme == "http" && !Self.isLoopbackHost(host) {
            throw CPAConfigurationError.insecureRemoteURL
        }

        var path = components.path
        if path.hasSuffix("/management.html") {
            path.removeLast("/management.html".count)
        } else if path.hasSuffix("/v0/management") {
            path.removeLast("/v0/management".count)
        }
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        components.path = path == "/" ? "" : path

        guard let url = components.url else {
            throw CPAConfigurationError.invalidBaseURL
        }
        return url
    }

    func validate() throws {
        _ = try validatedBaseURL()
        guard !managementKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CPAConfigurationError.missingManagementKey
        }
    }

    private static func isLoopbackHost(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}

enum CPAConfigurationStore {
    static let enabledKey = "codexU.cpa.enabled"
    static let baseURLKey = "codexU.cpa.baseURL"

    static func load(defaults: UserDefaults = .standard) -> CPAConfiguration {
        CPAConfiguration(
            isEnabled: defaults.bool(forKey: enabledKey),
            baseURL: defaults.string(forKey: baseURLKey) ?? CPAConfiguration.defaultBaseURL,
            managementKey: (try? CPAKeychainStore.loadManagementKey()) ?? ""
        )
    }
}

enum CPAKeychainStore {
    private static let service = "com.shanggqm.codexU.cpa"
    private static let account = "management-key"

    static func loadManagementKey() throws -> String {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return ""
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw CPAKeychainError(status: status)
        }
        guard let key = String(data: data, encoding: .utf8) else {
            throw CPAKeychainError(status: errSecDecode)
        }
        return key
    }

    static func saveManagementKey(_ key: String) throws {
        let data = Data(key.utf8)
        if data.isEmpty {
            let status = SecItemDelete(baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw CPAKeychainError(status: status)
            }
            return
        }

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw CPAKeychainError(status: updateStatus)
        }

        var addQuery = baseQuery
        attributes.forEach { addQuery[$0.key] = $0.value }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CPAKeychainError(status: addStatus)
        }
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

struct CPAKeychainError: Error {
    let status: OSStatus
}

enum CPAQuotaAccountStatus: String, Equatable {
    case available
    case unavailable
}

struct CPAQuotaAccount: Identifiable, Equatable {
    let id: String
    let displayName: String
    let planType: String?
    let status: CPAQuotaAccountStatus
    let fiveHourQuota: RateWindow?
    let sevenDayQuota: RateWindow?
    let monthlyQuota: RateWindow?
    let message: String?

    var lowestRemainingPercent: Double? {
        [
            fiveHourQuota?.remainingPercent,
            sevenDayQuota?.remainingPercent,
            monthlyQuota?.remainingPercent
        ]
            .compactMap { $0 }
            .min()
    }
}
