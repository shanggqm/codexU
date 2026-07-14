import Foundation

struct CPAQuotaPoolResult: Equatable {
    let accounts: [CPAQuotaAccount]
    let representative: CPAQuotaAccount?
    let messages: [String]

    var quotaReadSucceeded: Bool {
        representative != nil
    }

    var sourceLabel: String {
        let availableCount = accounts.filter { $0.status == .available }.count
        if accounts.isEmpty {
            return "CLIProxyAPI"
        }
        return "CLIProxyAPI · lowest account · \(availableCount)/\(accounts.count)"
    }
}

struct CPAAuthRecord: Equatable {
    let authIndex: String
    let displayName: String
    let planType: String?
    let chatGPTAccountID: String?
}

private struct CPAQuotaPayload: Equatable {
    let fiveHourQuota: RateWindow?
    let sevenDayQuota: RateWindow?
    let planType: String?
    let isAuthoritative: Bool
}

final class CPAQuotaReader {
    private enum ReaderError: Error {
        case invalidResponse
        case requestFailed
        case timedOut
        case httpStatus(Int)
        case malformedPayload
        case upstreamStatus(Int)
    }

    private struct APICallEnvelope {
        let statusCode: Int
        let body: String
    }

    private let session: URLSession
    private let timeout: TimeInterval
    private let maximumConcurrentAccountRequests: Int

    init(
        session: URLSession = CPAQuotaReader.makeSession(),
        timeout: TimeInterval = 12,
        maximumConcurrentAccountRequests: Int = 4
    ) {
        self.session = session
        self.timeout = timeout
        self.maximumConcurrentAccountRequests = maximumConcurrentAccountRequests
    }

    func load(configuration: CPAConfiguration, now: Date = Date()) -> CPAQuotaPoolResult {
        do {
            try configuration.validate()
            let baseURL = try configuration.validatedBaseURL()
            let authRecords = try fetchAuthRecords(baseURL: baseURL, managementKey: configuration.managementKey)
            guard !authRecords.isEmpty else {
                return CPAQuotaPoolResult(
                    accounts: [],
                    representative: nil,
                    messages: ["CPA 未返回可用的 Codex 账号"]
                )
            }

            let accounts = fetchAccounts(
                authRecords,
                baseURL: baseURL,
                managementKey: configuration.managementKey,
                now: now
            )
            let representative = accounts
                .filter { $0.status == .available && $0.lowestRemainingPercent != nil }
                .min { lhs, rhs in
                    let lhsRemaining = lhs.lowestRemainingPercent ?? 101
                    let rhsRemaining = rhs.lowestRemainingPercent ?? 101
                    if lhsRemaining == rhsRemaining {
                        return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
                    }
                    return lhsRemaining < rhsRemaining
                }
            let failureCount = accounts.filter { $0.status == .unavailable }.count
            var messages: [String] = []
            if failureCount > 0 {
                messages.append("CPA 有 \(failureCount) 个 Codex 账号额度暂不可用")
            }
            if representative == nil {
                messages.append("CPA Codex 账号额度均不可用")
            }
            return CPAQuotaPoolResult(
                accounts: accounts,
                representative: representative,
                messages: messages
            )
        } catch let error as CPAConfigurationError {
            return CPAQuotaPoolResult(accounts: [], representative: nil, messages: [Self.message(for: error)])
        } catch let error as ReaderError {
            return CPAQuotaPoolResult(accounts: [], representative: nil, messages: [Self.message(for: error)])
        } catch {
            return CPAQuotaPoolResult(accounts: [], representative: nil, messages: ["CPA 额度读取失败"])
        }
    }

    static func parseAuthRecords(_ data: Data) throws -> [CPAAuthRecord] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = object["files"] as? [[String: Any]]
        else {
            throw ReaderError.malformedPayload
        }

        var result: [CPAAuthRecord] = []
        for (index, file) in files.enumerated() {
            let provider = stringValue(file["provider"]) ?? stringValue(file["type"])
            guard provider?.lowercased() == "codex",
                  boolValue(file["disabled"]) != true,
                  let authIndex = stringValue(file["auth_index"]),
                  !authIndex.isEmpty
            else { continue }

            let idToken = file["id_token"] as? [String: Any]
            let email = stringValue(file["email"])
            let label = stringValue(file["label"])
            let planType = stringValue(idToken?["plan_type"])
                ?? stringValue(file["account_type"])
                ?? stringValue(file["account"])
            let displayName = maskedAccountName(
                email: email,
                label: label,
                fallbackIndex: index + 1
            )
            result.append(
                CPAAuthRecord(
                    authIndex: authIndex,
                    displayName: displayName,
                    planType: planType,
                    chatGPTAccountID: stringValue(idToken?["chatgpt_account_id"])
                )
            )
        }
        return result
    }

    static func parseQuotaBody(
        _ body: String,
        now: Date,
        fallbackPlanType: String? = nil
    ) throws -> (fiveHour: RateWindow?, sevenDay: RateWindow?, planType: String?, authoritative: Bool) {
        guard let data = body.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ReaderError.malformedPayload
        }
        let rateLimit = dictionaryValue(root, keys: ["rate_limit", "rateLimit"])
        guard let rateLimit else {
            throw ReaderError.malformedPayload
        }

        let primaryValue = value(rateLimit, keys: ["primary_window", "primaryWindow"])
        let secondaryValue = value(rateLimit, keys: ["secondary_window", "secondaryWindow"])
        let limitReached = boolValue(value(rateLimit, keys: ["limit_reached", "limitReached"])) == true
        let allowed = boolValue(rateLimit["allowed"])
        let exhaustedHint = limitReached || allowed == false
        let primary = parseWindow(
            primaryValue,
            fallbackDurationMins: 300,
            now: now,
            exhaustedHint: exhaustedHint
        )
        let secondary = parseWindow(
            secondaryValue,
            fallbackDurationMins: 10_080,
            now: now,
            exhaustedHint: exhaustedHint
        )
        let normalized = CodexRateLimitNormalizer.normalize([primary, secondary])
        let hasWindowFields = rateLimit.keys.contains("primary_window")
            || rateLimit.keys.contains("primaryWindow")
            || rateLimit.keys.contains("secondary_window")
            || rateLimit.keys.contains("secondaryWindow")
        let hasMalformedWindow = [
            (primaryValue, primary),
            (secondaryValue, secondary)
        ].contains { raw, parsed in
            guard let raw, !(raw is NSNull) else { return false }
            return parsed == nil
        }
        let authoritative = CodexRateLimitNormalizer.isAuthoritative(
            hasWindowFields: hasWindowFields,
            hasMalformedWindow: hasMalformedWindow,
            normalized: normalized
        )
        let accountPlan = dictionaryValue(root, keys: ["account_plan", "accountPlan"])
        let planType = stringValue(value(root, keys: ["plan_type", "planType"]))
            ?? stringValue(value(accountPlan ?? [:], keys: ["plan_type", "planType"]))
            ?? fallbackPlanType
        return (normalized.fiveHour, normalized.sevenDay, planType, authoritative)
    }

    private func fetchAuthRecords(baseURL: URL, managementKey: String) throws -> [CPAAuthRecord] {
        let url = managementURL(baseURL: baseURL, path: "auth-files")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyManagementHeaders(to: &request, managementKey: managementKey)
        let data = try perform(request)
        return try Self.parseAuthRecords(data)
    }

    private func fetchAccounts(
        _ records: [CPAAuthRecord],
        baseURL: URL,
        managementKey: String,
        now: Date
    ) -> [CPAQuotaAccount] {
        let queue = OperationQueue()
        queue.name = "codexU.cpa-quota"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = maximumConcurrentAccountRequests
        let lock = NSLock()
        var results = Array<CPAQuotaAccount?>(repeating: nil, count: records.count)

        for (index, record) in records.enumerated() {
            queue.addOperation { [self] in
                let account: CPAQuotaAccount
                do {
                    let payload = try fetchQuota(
                        record: record,
                        baseURL: baseURL,
                        managementKey: managementKey,
                        now: now
                    )
                    guard payload.isAuthoritative,
                          payload.fiveHourQuota != nil || payload.sevenDayQuota != nil
                    else {
                        throw ReaderError.malformedPayload
                    }
                    account = CPAQuotaAccount(
                        id: record.authIndex,
                        displayName: record.displayName,
                        planType: payload.planType,
                        status: .available,
                        fiveHourQuota: payload.fiveHourQuota,
                        sevenDayQuota: payload.sevenDayQuota,
                        message: nil
                    )
                } catch let error as ReaderError {
                    account = unavailableAccount(record: record, message: Self.message(for: error))
                } catch {
                    account = unavailableAccount(record: record, message: "额度读取失败")
                }
                lock.lock()
                results[index] = account
                lock.unlock()
            }
        }
        queue.waitUntilAllOperationsAreFinished()
        return results.compactMap { $0 }
    }

    private func fetchQuota(
        record: CPAAuthRecord,
        baseURL: URL,
        managementKey: String,
        now: Date
    ) throws -> CPAQuotaPayload {
        let url = managementURL(baseURL: baseURL, path: "api-call")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyManagementHeaders(to: &request, managementKey: managementKey)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var upstreamHeaders = [
            "Authorization": "Bearer $TOKEN$",
            "Content-Type": "application/json",
            "User-Agent": "codex_cli_rs/0.76.0 (macOS; codexU)"
        ]
        if let accountID = record.chatGPTAccountID, !accountID.isEmpty {
            upstreamHeaders["Chatgpt-Account-Id"] = accountID
        }
        let body: [String: Any] = [
            "auth_index": record.authIndex,
            "method": "GET",
            "url": "https://chatgpt.com/backend-api/wham/usage",
            "header": upstreamHeaders
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let responseData = try perform(request)
        let envelope = try Self.parseAPICallEnvelope(responseData)
        let parsed = try Self.parseQuotaBody(
            envelope.body,
            now: now,
            fallbackPlanType: record.planType
        )
        if !(200..<300).contains(envelope.statusCode), !parsed.authoritative {
            throw ReaderError.upstreamStatus(envelope.statusCode)
        }
        return CPAQuotaPayload(
            fiveHourQuota: parsed.fiveHour,
            sevenDayQuota: parsed.sevenDay,
            planType: parsed.planType,
            isAuthoritative: parsed.authoritative
        )
    }

    private func perform(_ request: URLRequest) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var responseData: Data?
        var response: URLResponse?
        var responseError: Error?
        let task = session.dataTask(with: request) { data, urlResponse, error in
            lock.lock()
            responseData = data
            response = urlResponse
            responseError = error
            lock.unlock()
            semaphore.signal()
        }
        task.resume()
        guard semaphore.wait(timeout: .now() + timeout + 1) == .success else {
            task.cancel()
            throw ReaderError.timedOut
        }
        lock.lock()
        let finalData = responseData
        let finalResponse = response
        let finalError = responseError
        lock.unlock()
        if finalError != nil {
            throw ReaderError.requestFailed
        }
        guard let http = finalResponse as? HTTPURLResponse, let finalData else {
            throw ReaderError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ReaderError.httpStatus(http.statusCode)
        }
        return finalData
    }

    private static func parseAPICallEnvelope(_ data: Data) throws -> APICallEnvelope {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let statusCode = intValue(value(object, keys: ["status_code", "statusCode"])),
              let body = stringValue(object["body"])
        else {
            throw ReaderError.malformedPayload
        }
        return APICallEnvelope(statusCode: statusCode, body: body)
    }

    private func managementURL(baseURL: URL, path: String) -> URL {
        baseURL
            .appendingPathComponent("v0", isDirectory: true)
            .appendingPathComponent("management", isDirectory: true)
            .appendingPathComponent(path, isDirectory: false)
    }

    private func applyManagementHeaders(to request: inout URLRequest, managementKey: String) {
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue(managementKey, forHTTPHeaderField: "X-Management-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codexU/CPA-quota", forHTTPHeaderField: "User-Agent")
    }

    private func unavailableAccount(record: CPAAuthRecord, message: String) -> CPAQuotaAccount {
        CPAQuotaAccount(
            id: record.authIndex,
            displayName: record.displayName,
            planType: record.planType,
            status: .unavailable,
            fiveHourQuota: nil,
            sevenDayQuota: nil,
            message: message
        )
    }

    private static func parseWindow(
        _ rawValue: Any?,
        fallbackDurationMins: Int,
        now: Date,
        exhaustedHint: Bool
    ) -> RateWindow? {
        guard let object = rawValue as? [String: Any] else { return nil }
        var usedPercent = doubleValue(value(object, keys: ["used_percent", "usedPercent"]))
        let resetsAt = resetDate(from: object, now: now)
        if usedPercent == nil, exhaustedHint, resetsAt != nil {
            usedPercent = 100
        }
        guard let usedPercent else { return nil }
        let durationSeconds = intValue(value(object, keys: ["limit_window_seconds", "limitWindowSeconds"]))
        let durationMins = durationSeconds.map { max(1, $0 / 60) } ?? fallbackDurationMins
        return RateWindow(
            usedPercent: max(0, min(100, usedPercent)),
            windowDurationMins: durationMins,
            resetsAt: resetsAt
        )
    }

    private static func resetDate(from object: [String: Any], now: Date) -> Date? {
        if let timestamp = doubleValue(value(object, keys: ["reset_at", "resetAt"])), timestamp > 0 {
            let seconds = timestamp > 10_000_000_000 ? timestamp / 1_000 : timestamp
            return Date(timeIntervalSince1970: seconds)
        }
        if let seconds = doubleValue(value(object, keys: ["reset_after_seconds", "resetAfterSeconds"])), seconds >= 0 {
            return now.addingTimeInterval(seconds)
        }
        return nil
    }

    private static func maskedAccountName(email: String?, label: String?, fallbackIndex: Int) -> String {
        if let email, let atIndex = email.firstIndex(of: "@") {
            let local = email[..<atIndex]
            let domain = email[email.index(after: atIndex)...]
            let prefix = local.first.map(String.init) ?? "*"
            return "\(prefix)***@\(domain)"
        }
        if let label = label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            return String(label.prefix(48))
        }
        return "CPA 账号 \(fallbackIndex)"
    }

    private static func dictionaryValue(_ object: [String: Any], keys: [String]) -> [String: Any]? {
        value(object, keys: keys) as? [String: Any]
    }

    private static func value(_ object: [String: Any], keys: [String]) -> Any? {
        keys.compactMap { object[$0] }.first
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String { return Bool(string) }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func message(for error: CPAConfigurationError) -> String {
        switch error {
        case .missingBaseURL:
            return "CPA 地址未填写"
        case .missingManagementKey:
            return "CPA 管理 Key 未填写"
        case .invalidBaseURL:
            return "CPA 地址格式无效"
        case .insecureRemoteURL:
            return "远程 CPA 必须使用 HTTPS"
        }
    }

    private static func message(for error: ReaderError) -> String {
        switch error {
        case .timedOut:
            return "CPA 额度请求超时"
        case .httpStatus(let status):
            if status == 401 || status == 403 {
                return "CPA 管理 Key 无效或远程管理未开放"
            }
            return "CPA 管理接口暂不可用（HTTP \(status)）"
        case .upstreamStatus(let status):
            return "CPA 上游额度接口暂不可用（HTTP \(status)）"
        case .malformedPayload:
            return "CPA 返回了无法识别的额度格式"
        case .invalidResponse, .requestFailed:
            return "CPA 额度连接失败"
        }
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }
}
