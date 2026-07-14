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

        if failures.isEmpty {
            print("CPA quota self-test passed")
            return true
        }

        failures.forEach { print("CPA quota self-test failed: \($0)") }
        return false
    }
}
