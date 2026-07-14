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
            expect(parsed.authoritative, "standard wham quota payload should be authoritative")
            expect(parsed.fiveHour?.usedPercent == 25, "primary 5-hour quota should parse")
            expect(parsed.fiveHour?.windowDurationMins == 300, "5-hour duration should be classified by seconds")
            expect(parsed.fiveHour?.resetsAt == now.addingTimeInterval(600), "relative reset should use the refresh time")
            expect(parsed.sevenDay?.usedPercent == 60, "secondary 7-day quota should parse")
            expect(parsed.planType == "pro", "quota payload plan should override auth-file fallback")
        } catch {
            failures.append("standard wham quota payload should parse")
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
                    {"provider":"codex","auth_index":"lowest","label":"Lowest"}
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
            let used = authIndex == "lowest" ? 90 : 20
            let quotaObject: [String: Any] = [
                "plan_type": "plus",
                "rate_limit": [
                    "primary_window": [
                        "used_percent": used,
                        "limit_window_seconds": 18_000,
                        "reset_after_seconds": 300
                    ],
                    "secondary_window": [
                        "used_percent": authIndex == "lowest" ? 50 : 30,
                        "limit_window_seconds": 604_800,
                        "reset_after_seconds": 600
                    ]
                ]
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
        expect(pool.accounts.count == 2, "management API should return both Codex accounts")
        expect(pool.accounts.allSatisfy { $0.status == .available }, "mock account quotas should be available")
        expect(pool.representative?.displayName == "Lowest", "the lowest remaining account should drive the main quota")
        expect(pool.representative?.fiveHourQuota?.remainingPercent == 10, "representative quota should keep the selected account windows")
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
