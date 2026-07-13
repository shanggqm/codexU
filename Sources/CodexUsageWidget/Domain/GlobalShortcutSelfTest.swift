import Carbon.HIToolbox
import Cocoa
import Foundation

enum GlobalShortcutSelfTest {
    private static let signature: OSType = 0x43535455 // CSTU
    private static let oldShortcut = GlobalShortcut(
        keyCode: UInt32(kVK_F11),
        carbonModifiers: UInt32(cmdKey | shiftKey),
        keyLabel: "F11"
    )
    private static let occupiedShortcut = GlobalShortcut(
        keyCode: UInt32(kVK_F12),
        carbonModifiers: UInt32(cmdKey | shiftKey),
        keyLabel: "F12"
    )

    static func run() -> Bool {
        _ = NSApplication.shared
        var failures: [String] = []
        checkValidationRules(failures: &failures)
        checkPersistence(failures: &failures)
        checkSettingsMutations(failures: &failures)
        checkInvalidStoredValues(failures: &failures)
        checkReplacementTransaction(failures: &failures)
        checkExclusiveConflictPreservesOldRegistration(failures: &failures)

        if failures.isEmpty {
            print("global shortcut self-test passed")
            return true
        }
        for failure in failures {
            print("global shortcut self-test failed: \(failure)")
        }
        return false
    }

    static func holdExclusiveShortcut(readyFile: String) -> Never {
        _ = NSApplication.shared
        var hotKeyRef: EventHotKeyRef?
        let status = registerExclusive(
            occupiedShortcut,
            id: 100,
            reference: &hotKeyRef
        )
        guard status == noErr, hotKeyRef != nil else {
            try? "error:\(status)".write(
                toFile: readyFile,
                atomically: true,
                encoding: .utf8
            )
            exit(2)
        }
        try? "ready".write(toFile: readyFile, atomically: true, encoding: .utf8)
        RunLoop.current.run(until: Date().addingTimeInterval(15))
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        exit(0)
    }

    private static func checkValidationRules(failures: inout [String]) {
        let cases: [(String, GlobalShortcut, GlobalShortcutValidationError?)] = [
            ("default command+U", .default, nil),
            ("shift+A", shortcut(kVK_ANSI_A, shiftKey, "A"), .tooFewModifiers),
            ("option+A", shortcut(kVK_ANSI_A, optionKey, "A"), .tooFewModifiers),
            ("command+Q", shortcut(kVK_ANSI_Q, cmdKey, "Q"), .tooFewModifiers),
            ("option+shift+A", shortcut(kVK_ANSI_A, optionKey | shiftKey, "A"), .requiresCommandOrControl),
            ("command+option+escape", shortcut(kVK_Escape, cmdKey | optionKey, "⎋"), .reservedSystemShortcut),
            ("command+control+Q", shortcut(kVK_ANSI_Q, cmdKey | controlKey, "Q"), .reservedSystemShortcut),
            ("command+shift+Q", shortcut(kVK_ANSI_Q, cmdKey | shiftKey, "Q"), .reservedSystemShortcut),
            ("command+option+shift+Q", shortcut(kVK_ANSI_Q, cmdKey | optionKey | shiftKey, "Q"), .reservedSystemShortcut),
            ("command+option+D", shortcut(kVK_ANSI_D, cmdKey | optionKey, "D"), .reservedSystemShortcut),
            ("command+control+F", shortcut(kVK_ANSI_F, cmdKey | controlKey, "F"), .reservedSystemShortcut),
            ("command+option+H", shortcut(kVK_ANSI_H, cmdKey | optionKey, "H"), .reservedSystemShortcut),
            ("command+shift+3", shortcut(kVK_ANSI_3, cmdKey | shiftKey, "3"), .reservedSystemShortcut),
            ("command+shift+4", shortcut(kVK_ANSI_4, cmdKey | shiftKey, "4"), .reservedSystemShortcut),
            ("command+shift+5", shortcut(kVK_ANSI_5, cmdKey | shiftKey, "5"), .reservedSystemShortcut),
            ("control+command+shift+3", shortcut(kVK_ANSI_3, controlKey | cmdKey | shiftKey, "3"), .reservedSystemShortcut),
            ("command+option+F5", shortcut(kVK_F5, cmdKey | optionKey, "F5"), .reservedSystemShortcut),
            ("control+option+right", shortcut(kVK_RightArrow, controlKey | optionKey, "→"), .reservedSystemShortcut),
            ("control+option+command+K", shortcut(kVK_ANSI_K, controlKey | optionKey | cmdKey, "K"), .reservedSystemShortcut),
            ("command+shift+U", shortcut(kVK_ANSI_U, cmdKey | shiftKey, "U"), nil),
            ("control+shift+K", shortcut(kVK_ANSI_K, controlKey | shiftKey, "K"), nil),
            ("control+option+F8", shortcut(kVK_F8, controlKey | optionKey, "F8"), .reservedSystemShortcut),
            ("command+shift+comma", shortcut(kVK_ANSI_Comma, cmdKey | shiftKey, ","), .unsupportedKey)
        ]

        for (name, shortcut, expected) in cases where shortcut.validationError != expected {
            failures.append("\(name) expected \(String(describing: expected)), got \(String(describing: shortcut.validationError))")
        }
    }

    private static func checkPersistence(failures: inout [String]) {
        withDefaults { defaults in
            let shortcut = self.shortcut(kVK_ANSI_K, cmdKey | shiftKey, "K")
            shortcut.save(defaults: defaults)
            if GlobalShortcut.load(defaults: defaults) != shortcut {
                failures.append("saved shortcut did not round-trip")
            }

            GlobalShortcut.clear(defaults: defaults)
            if GlobalShortcut.load(defaults: defaults) != nil {
                failures.append("cleared shortcut did not remain disabled")
            }
        }
    }

    private static func checkSettingsMutations(failures: inout [String]) {
        withDefaults { defaults in
            let custom = self.shortcut(kVK_ANSI_K, cmdKey | shiftKey, "K")
            custom.save(defaults: defaults)
            let settings = AppSettings(defaults: defaults)
            settings.globalShortcutRegistration = { _ in .success(()) }
            settings.globalShortcutUnregistration = { .success(()) }
            settings.resetGlobalShortcut()
            if settings.globalShortcut != .default
                || GlobalShortcut.load(defaults: defaults) != .default {
                failures.append("reset did not restore and persist the default shortcut")
            }

            settings.clearGlobalShortcut()
            if settings.globalShortcut != nil
                || GlobalShortcut.load(defaults: defaults) != nil {
                failures.append("settings clear did not persist the disabled state")
            }
        }

        withDefaults { defaults in
            let oldShortcut = self.shortcut(kVK_ANSI_K, cmdKey | shiftKey, "K")
            let candidate = self.shortcut(kVK_ANSI_L, cmdKey | shiftKey, "L")
            oldShortcut.save(defaults: defaults)
            let settings = AppSettings(defaults: defaults)
            settings.globalShortcutRegistration = { _ in .failure(.occupied) }
            if settings.requestGlobalShortcut(candidate)
                || settings.globalShortcut != oldShortcut
                || GlobalShortcut.load(defaults: defaults) != oldShortcut
                || settings.globalShortcutError != .occupied {
                failures.append("registration failure did not retain the old stored shortcut")
            }

            if !settings.requestGlobalShortcut(oldShortcut)
                || settings.globalShortcutError != nil
                || GlobalShortcut.load(defaults: defaults) != oldShortcut {
                failures.append("reselecting the active shortcut did not clear the error")
            }
        }

        withDefaults { defaults in
            let oldShortcut = self.shortcut(kVK_ANSI_K, cmdKey | shiftKey, "K")
            oldShortcut.save(defaults: defaults)
            let settings = AppSettings(defaults: defaults)
            settings.globalShortcutUnregistration = { .failure(.failed) }
            settings.clearGlobalShortcut()
            if settings.globalShortcut != oldShortcut
                || GlobalShortcut.load(defaults: defaults) != oldShortcut
                || settings.globalShortcutError != .unregistrationFailed {
                failures.append("unregistration failure did not retain the old shortcut")
            }
        }

        withDefaults { defaults in
            let custom = self.shortcut(kVK_ANSI_K, cmdKey | shiftKey, "K")
            custom.save(defaults: defaults)
            let settings = AppSettings(defaults: defaults)
            settings.handleInitialGlobalShortcutFailure(defaultRegistered: true)
            if settings.globalShortcut != .default
                || settings.globalShortcutError != .savedShortcutUnavailableUsingDefault
                || GlobalShortcut.load(defaults: defaults) != custom {
                failures.append("startup fallback overwrote the saved shortcut")
            }
        }

        withDefaults { defaults in
            let custom = self.shortcut(kVK_ANSI_K, cmdKey | shiftKey, "K")
            custom.save(defaults: defaults)
            let settings = AppSettings(defaults: defaults)
            settings.handleInitialGlobalShortcutFailure(defaultRegistered: false)
            if settings.globalShortcut != nil
                || settings.globalShortcutError != .noShortcutAvailable
                || GlobalShortcut.load(defaults: defaults) != custom {
                failures.append("startup failure without fallback overwrote the saved shortcut")
            }
        }
    }

    private static func checkInvalidStoredValues(failures: inout [String]) {
        let invalidCases: [(String, (UserDefaults) -> Void)] = [
            ("negative key code", { defaults in
                seed(defaults, keyCode: -1, modifiers: cmdKey | shiftKey, label: "K")
            }),
            ("overflow key code", { defaults in
                defaults.set(true, forKey: GlobalShortcut.enabledStorageKey)
                defaults.set(Double(UInt32.max) + 1, forKey: GlobalShortcut.keyCodeStorageKey)
                defaults.set(cmdKey | shiftKey, forKey: GlobalShortcut.modifiersStorageKey)
                defaults.set("K", forKey: GlobalShortcut.keyLabelStorageKey)
            }),
            ("unknown modifier bit", { defaults in
                seed(
                    defaults,
                    keyCode: kVK_ANSI_K,
                    modifiers: Int(UInt32(cmdKey | shiftKey) | (1 << 31)),
                    label: "K"
                )
            }),
            ("unsupported key", { defaults in
                seed(defaults, keyCode: kVK_Return, modifiers: cmdKey | shiftKey, label: "↩")
            }),
            ("control character label", { defaults in
                seed(defaults, keyCode: kVK_ANSI_K, modifiers: cmdKey | shiftKey, label: "K\n")
            }),
            ("non-boolean enabled flag", { defaults in
                defaults.set("yes", forKey: GlobalShortcut.enabledStorageKey)
            })
        ]

        for (name, mutation) in invalidCases {
            withDefaults { defaults in
                mutation(defaults)
                if GlobalShortcut.load(defaults: defaults) != .default
                    || defaults.integer(forKey: GlobalShortcut.keyCodeStorageKey) != Int(kVK_ANSI_U)
                    || defaults.integer(forKey: GlobalShortcut.modifiersStorageKey) != cmdKey {
                    failures.append("\(name) did not repair to the default shortcut")
                }
            }
        }
    }

    private static func checkExclusiveConflictPreservesOldRegistration(
        failures: inout [String]
    ) {
        guard let executableURL = Bundle.main.executableURL else {
            failures.append("could not locate self-test executable")
            return
        }

        let readyFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexu-hotkey-self-test-\(UUID().uuidString)")
        let helper = Process()
        helper.executableURL = executableURL
        helper.arguments = ["--hold-exclusive-hotkey", readyFile.path]

        do {
            try helper.run()
        } catch {
            failures.append("could not launch conflict helper: \(error)")
            return
        }

        defer {
            if helper.isRunning { helper.terminate() }
            try? FileManager.default.removeItem(at: readyFile)
        }

        let deadline = Date().addingTimeInterval(3)
        while !FileManager.default.fileExists(atPath: readyFile.path), Date() < deadline {
            if !helper.isRunning { break }
            Thread.sleep(forTimeInterval: 0.02)
        }
        guard FileManager.default.fileExists(atPath: readyFile.path) else {
            failures.append("conflict helper did not acquire the exclusive shortcut")
            return
        }
        let helperState = (try? String(contentsOf: readyFile, encoding: .utf8)) ?? ""
        guard helperState == "ready" else {
            failures.append("conflict helper registration failed: \(helperState)")
            return
        }

        var oldRef: EventHotKeyRef?
        let oldStatus = registerExclusive(oldShortcut, id: 1, reference: &oldRef)
        guard oldStatus == noErr, let oldRef else {
            failures.append("could not register the old shortcut, status=\(oldStatus)")
            return
        }

        var candidateRef: EventHotKeyRef?
        let candidateStatus = registerExclusive(
            occupiedShortcut,
            id: 2,
            reference: &candidateRef
        )
        if candidateStatus != eventHotKeyExistsErr {
            failures.append("exclusive conflict returned \(candidateStatus), expected \(eventHotKeyExistsErr)")
        }
        if let candidateRef {
            UnregisterEventHotKey(candidateRef)
            failures.append("exclusive conflict unexpectedly returned a candidate reference")
        }
        if UnregisterEventHotKey(oldRef) != noErr {
            failures.append("old shortcut was not retained after candidate conflict")
        }
    }

    private static func checkReplacementTransaction(failures: inout [String]) {
        var unregistered: [Int] = []
        var rolledBack: [Int] = []
        let failed: Result<Int, GlobalShortcutRegistrationFailure> =
            GlobalShortcutRegistrationTransaction.replace(
                current: 1,
                registerCandidate: { .failure(.occupied) },
                unregister: {
                    unregistered.append($0)
                    return .success(())
                },
                rollbackCandidate: { rolledBack.append($0) }
            )
        guard failed == .failure(.occupied), unregistered.isEmpty, rolledBack.isEmpty else {
            failures.append("failed replacement unregistered the old shortcut")
            return
        }

        let succeeded: Result<Int, GlobalShortcutRegistrationFailure> =
            GlobalShortcutRegistrationTransaction.replace(
                current: 1,
                registerCandidate: { .success(2) },
                unregister: {
                    unregistered.append($0)
                    return .success(())
                },
                rollbackCandidate: { rolledBack.append($0) }
            )
        if succeeded != .success(2) || unregistered != [1] || !rolledBack.isEmpty {
            failures.append("successful replacement did not swap registrations transactionally")
        }

        let unregisterFailed: Result<Int, GlobalShortcutRegistrationFailure> =
            GlobalShortcutRegistrationTransaction.replace(
                current: 3,
                registerCandidate: { .success(4) },
                unregister: { _ in .failure(.failed) },
                rollbackCandidate: { rolledBack.append($0) }
            )
        if unregisterFailed != .failure(.failed) || rolledBack != [4] {
            failures.append("old unregistration failure did not roll back the candidate")
        }
    }

    private static func shortcut(
        _ keyCode: Int,
        _ modifiers: Int,
        _ label: String
    ) -> GlobalShortcut {
        GlobalShortcut(
            keyCode: UInt32(keyCode),
            carbonModifiers: UInt32(modifiers),
            keyLabel: label
        )
    }

    private static func seed(
        _ defaults: UserDefaults,
        keyCode: Int,
        modifiers: Int,
        label: String
    ) {
        defaults.set(true, forKey: GlobalShortcut.enabledStorageKey)
        defaults.set(keyCode, forKey: GlobalShortcut.keyCodeStorageKey)
        defaults.set(modifiers, forKey: GlobalShortcut.modifiersStorageKey)
        defaults.set(label, forKey: GlobalShortcut.keyLabelStorageKey)
    }

    private static func withDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "codexU.global-shortcut-self-test.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults)
    }

    private static func registerExclusive(
        _ shortcut: GlobalShortcut,
        id: UInt32,
        reference: inout EventHotKeyRef?
    ) -> OSStatus {
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        return RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            UInt32(kEventHotKeyExclusive),
            &reference
        )
    }
}
