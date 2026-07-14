import Foundation

enum CPAQuotaSelfTest {
    static func run() -> Bool {
        var failures: [String] = []

        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() {
                failures.append(message)
            }
        }

        let local = CPAConfiguration(
            isEnabled: true,
            baseURL: "http://127.0.0.1:8317/",
            managementKey: "secret"
        )
        expect(
            (try? local.validatedBaseURL().absoluteString) == "http://127.0.0.1:8317",
            "loopback HTTP URL should be accepted and normalized"
        )

        let managementPath = CPAConfiguration(
            isEnabled: true,
            baseURL: "https://cpa.example.com/v0/management",
            managementKey: "secret"
        )
        expect(
            (try? managementPath.validatedBaseURL().absoluteString) == "https://cpa.example.com",
            "management API suffix should be normalized to the CPA root"
        )

        let insecureRemote = CPAConfiguration(
            isEnabled: true,
            baseURL: "http://cpa.example.com",
            managementKey: "secret"
        )
        do {
            _ = try insecureRemote.validatedBaseURL()
            failures.append("remote HTTP URL should be rejected")
        } catch {
            expect(error as? CPAConfigurationError == .insecureRemoteURL, "remote HTTP should report an insecure URL")
        }

        let missingKey = CPAConfiguration(
            isEnabled: true,
            baseURL: "https://cpa.example.com",
            managementKey: ""
        )
        do {
            try missingKey.validate()
            failures.append("empty management key should be rejected")
        } catch {
            expect(error as? CPAConfigurationError == .missingManagementKey, "empty key should report a missing management key")
        }

        let authPayload = Data("""
        {
          "files": [
            {
              "provider": "codex",
              "auth_index": "auth-1",
              "email": "alice@example.com",
              "id_token": {
                "chatgpt_account_id": "account-1",
                "plan_type": "plus"
              }
            },
            {
              "type": "codex",
              "auth_index": "auth-disabled",
              "disabled": true
            },
            {
              "provider": "claude",
              "auth_index": "auth-2"
            }
          ]
        }
        """.utf8)
        do {
            let auths = try CPAQuotaReader.parseAuthRecords(authPayload)
            expect(auths.count == 1, "only enabled Codex credentials should be returned")
            expect(auths.first?.displayName == "a***@example.com", "email should be masked before entering the snapshot")
            expect(auths.first?.planType == "plus", "plan type should be read from id_token claims")
        } catch {
            failures.append("auth-files payload should parse")
        }

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let quotaBody = """
        {
          "plan_type": "pro",
          "rate_limit": {
            "primary_window": {
              "used_percent": 25,
              "limit_window_seconds": 18000,
              "reset_after_seconds": 600
            },
            "secondary_window": {
              "used_percent": 60,
              "limit_window_seconds": 604800,
              "reset_at": 1800604800
            }
          }
        }
        """
        do {
            let parsed = try CPAQuotaReader.parseQuotaBody(quotaBody, now: now)
            expect(parsed.isAuthoritative, "standard wham quota payload should be authoritative")
            expect(parsed.fiveHourQuota?.usedPercent == 25, "primary 5-hour quota should parse")
            expect(parsed.fiveHourQuota?.windowDurationMins == 300, "5-hour duration should be classified by seconds")
            expect(parsed.fiveHourQuota?.resetsAt == now.addingTimeInterval(600), "relative reset should use the refresh time")
            expect(parsed.sevenDayQuota?.usedPercent == 60, "secondary 7-day quota should parse")
            expect(parsed.planType == "pro", "quota payload plan should override auth-file fallback")
        } catch {
            failures.append("standard wham quota payload should parse")
        }

        let monthlyQuotaBody = """
        {
          "plan_type": "team",
          "rate_limit": {
            "primary_window": {
              "used_percent": 72,
              "limit_window_seconds": 2592000,
              "reset_after_seconds": 864000
            }
          }
        }
        """
        do {
            let parsed = try CPAQuotaReader.parseQuotaBody(monthlyQuotaBody, now: now)
            expect(parsed.isAuthoritative, "a monthly-only wham payload should be authoritative")
            expect(parsed.fiveHourQuota == nil && parsed.sevenDayQuota == nil, "monthly quota must not be mislabeled as 5h or 7d")
            expect(parsed.monthlyQuota?.usedPercent == 72, "30-day quota should parse as monthly")
            expect(parsed.monthlyQuota?.windowDurationMins == 43_200, "30-day duration should be preserved")
            expect(parsed.monthlyQuota?.resetsAt == now.addingTimeInterval(864_000), "monthly reset should use the response value")
        } catch {
            failures.append("monthly-only wham quota payload should parse")
        }

        let additionalMonthlyBody = """
        {
          "rate_limit": {
            "primary_window": {"used_percent": 20, "limit_window_seconds": 18000},
            "secondary_window": {"used_percent": 40, "limit_window_seconds": 604800}
          },
          "additional_rate_limits": [
            {
              "limit_name": "monthly-codex",
              "rate_limit": {
                "primary_window": {"used_percent": 65, "limit_window_seconds": 2678400}
              }
            }
          ]
        }
        """
        do {
            let parsed = try CPAQuotaReader.parseQuotaBody(additionalMonthlyBody, now: now)
            expect(parsed.isAuthoritative, "additional monthly quota should keep the payload authoritative")
            expect(parsed.fiveHourQuota?.usedPercent == 20, "standard 5h quota should survive alongside monthly quota")
            expect(parsed.sevenDayQuota?.usedPercent == 40, "standard 7d quota should survive alongside monthly quota")
            expect(parsed.monthlyQuota?.usedPercent == 65, "31-day additional quota should parse as monthly")
        } catch {
            failures.append("additional monthly quota payload should parse")
        }

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [CPAQuotaMockURLProtocol.self]
        let reader = CPAQuotaReader(
            session: URLSession(configuration: sessionConfiguration),
            timeout: 2,
            maximumConcurrentAccountRequests: 2
        )
        CPAQuotaMockURLProtocol.handler = { request in
            guard request.value(forHTTPHeaderField: "X-Management-Key") == "secret" else {
                return (401, Data("{\"error\":\"unauthorized\"}".utf8))
            }
            if request.url?.path == "/v0/management/auth-files" {
                return (200, Data("""
                {
                  "files": [
                    {"provider":"codex","auth_index":"healthy","label":"Healthy"},
                    {"provider":"codex","auth_index":"lowest","label":"Lowest"},
                    {"provider":"codex","auth_index":"monthly","label":"Monthly"}
                  ]
                }
                """.utf8))
            }
            guard request.url?.path == "/v0/management/api-call",
                  let requestBody = CPAQuotaMockURLProtocol.bodyData(for: request),
                  let payload = try? JSONSerialization.jsonObject(with: requestBody) as? [String: Any],
                  let authIndex = payload["auth_index"] as? String
            else {
                return (400, Data("{\"error\":\"bad request\"}".utf8))
            }
            let isMonthly = authIndex == "monthly"
            let used = authIndex == "lowest" ? 90 : 20
            let primaryWindow: [String: Any] = isMonthly
                ? [
                    "used_percent": 95,
                    "limit_window_seconds": 2_592_000,
                    "reset_after_seconds": 86_400
                ]
                : [
                    "used_percent": used,
                    "limit_window_seconds": 18_000,
                    "reset_after_seconds": 300
                ]
            var rateLimit: [String: Any] = ["primary_window": primaryWindow]
            if !isMonthly {
                rateLimit["secondary_window"] = [
                    "used_percent": authIndex == "lowest" ? 50 : 30,
                    "limit_window_seconds": 604_800,
                    "reset_after_seconds": 600
                ]
            }
            let quotaObject: [String: Any] = [
                "plan_type": "plus",
                "rate_limit": rateLimit
            ]
            let quotaData = try! JSONSerialization.data(withJSONObject: quotaObject)
            let envelope: [String: Any] = [
                "status_code": 200,
                "header": [:],
                "body": String(data: quotaData, encoding: .utf8)!
            ]
            return (200, try! JSONSerialization.data(withJSONObject: envelope))
        }
        let pool = reader.load(
            configuration: CPAConfiguration(
                isEnabled: true,
                baseURL: "https://cpa.example.com",
                managementKey: "secret"
            ),
            now: now
        )
        expect(pool.accounts.count == 3, "management API should return every Codex account")
        expect(pool.accounts.allSatisfy { $0.status == .available }, "mock account quotas should be available")
        expect(pool.representative?.displayName == "Monthly", "a low monthly-only account should drive the conservative pool signal")
        expect(pool.representative?.monthlyQuota?.remainingPercent == 5, "representative quota should retain its monthly window")
        let monthlyStatusPresentation = StatusItemPresentationBuilder().build(
            source: StatusItemSourceSnapshot(
                runtime: .codex,
                fiveHourRemainingPercent: nil,
                fiveHourResetsAt: nil,
                sevenDayRemainingPercent: nil,
                sevenDayResetsAt: nil,
                monthlyRemainingPercent: 5,
                monthlyResetsAt: now.addingTimeInterval(86_400),
                todayTokens: nil
            ),
            preferences: .default,
            language: .zh,
            now: now
        )
        expect(
            monthlyStatusPresentation.quotaMetrics.map(\.metric) == [.monthlyQuota],
            "monthly-only quota should replace unavailable configured 5h/7d metrics in the menu bar"
        )
        expect(
            monthlyStatusPresentation.quotaMetrics.first?.label == "30d",
            "monthly menu bar quota should use an unambiguous compact label"
        )
        expect(!monthlyStatusPresentation.showsNoActiveQuota, "monthly-only quota must not be shown as unlimited")
        CPAQuotaMockURLProtocol.handler = nil

        if failures.isEmpty {
            print("CPA quota self-test passed")
            return true
        }

        failures.forEach { print("CPA quota self-test failed: \($0)") }
        return false
    }
}

private final class CPAQuotaMockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "cpa.example.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    static func bodyData(for request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4_096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count < 0 { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
