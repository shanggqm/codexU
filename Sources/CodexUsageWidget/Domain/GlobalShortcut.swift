import Carbon.HIToolbox
import Cocoa
import CoreFoundation

struct GlobalShortcut: Hashable {
    static let `default` = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_U),
        carbonModifiers: UInt32(cmdKey),
        keyLabel: "U"
    )

    static let keyCodeStorageKey = "codexU.globalShortcut.keyCode"
    static let modifiersStorageKey = "codexU.globalShortcut.modifiers"
    static let keyLabelStorageKey = "codexU.globalShortcut.keyLabel"
    static let enabledStorageKey = "codexU.globalShortcut.enabled"

    let keyCode: UInt32
    let carbonModifiers: UInt32
    let keyLabel: String

    var displayName: String {
        var result = ""
        if carbonModifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + keyLabel
    }

    func matchesRegistration(of other: GlobalShortcut) -> Bool {
        keyCode == other.keyCode && carbonModifiers == other.carbonModifiers
    }

    var validationError: GlobalShortcutValidationError? {
        if self == .default { return nil }

        let modifierCount = [cmdKey, controlKey, optionKey, shiftKey]
            .filter { carbonModifiers & UInt32($0) != 0 }
            .count
        guard modifierCount >= 2 else { return .tooFewModifiers }
        guard carbonModifiers & UInt32(cmdKey | controlKey) != 0 else {
            return .requiresCommandOrControl
        }
        guard !Self.isReservedSystemShortcut(
            keyCode: keyCode,
            modifiers: carbonModifiers
        ) else { return .reservedSystemShortcut }
        guard Self.supportedKeyCodes.contains(keyCode) else { return .unsupportedKey }
        return nil
    }

    static func load(defaults: UserDefaults = .standard) -> GlobalShortcut? {
        if let enabledValue = defaults.object(forKey: enabledStorageKey) {
            guard let enabledNumber = enabledValue as? NSNumber,
                  CFGetTypeID(enabledNumber) == CFBooleanGetTypeID()
            else { return repairToDefault(defaults: defaults) }
            if !enabledNumber.boolValue { return nil }
        }
        guard let keyCode = storedUInt32(forKey: keyCodeStorageKey, defaults: defaults),
              let modifiers = storedUInt32(forKey: modifiersStorageKey, defaults: defaults),
              let keyLabel = defaults.string(forKey: keyLabelStorageKey),
              isValidStoredLabel(keyLabel)
        else { return repairToDefault(defaults: defaults) }

        let allowedModifiers = UInt32(cmdKey | controlKey | optionKey | shiftKey)
        guard modifiers != 0, modifiers & ~allowedModifiers == 0 else {
            return repairToDefault(defaults: defaults)
        }

        let shortcut = GlobalShortcut(
            keyCode: keyCode,
            carbonModifiers: modifiers,
            keyLabel: keyLabel
        )
        guard shortcut.validationError == nil else {
            return repairToDefault(defaults: defaults)
        }
        return shortcut
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: Self.enabledStorageKey)
        defaults.set(Int(keyCode), forKey: Self.keyCodeStorageKey)
        defaults.set(Int(carbonModifiers), forKey: Self.modifiersStorageKey)
        defaults.set(keyLabel, forKey: Self.keyLabelStorageKey)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.set(false, forKey: enabledStorageKey)
        defaults.removeObject(forKey: keyCodeStorageKey)
        defaults.removeObject(forKey: modifiersStorageKey)
        defaults.removeObject(forKey: keyLabelStorageKey)
    }

    private static func storedUInt32(
        forKey key: String,
        defaults: UserDefaults
    ) -> UInt32? {
        guard let number = defaults.object(forKey: key) as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else { return nil }
        let value = number.doubleValue
        guard value.isFinite,
              value.rounded(.towardZero) == value,
              value >= 0,
              value <= Double(UInt32.max)
        else { return nil }
        return UInt32(value)
    }

    private static func isValidStoredLabel(_ label: String) -> Bool {
        !label.isEmpty
            && label.count <= 12
            && label.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0)
            }
    }

    private static func repairToDefault(defaults: UserDefaults) -> GlobalShortcut {
        GlobalShortcut.default.save(defaults: defaults)
        return .default
    }

    static func from(event: NSEvent) -> GlobalShortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        guard modifiers != 0 else { return nil }

        let keyCode = UInt32(event.keyCode)
        let label = specialKeyLabels[keyCode]
            ?? event.charactersIgnoringModifiers?.uppercased()
        guard let label, !label.isEmpty else { return nil }
        return GlobalShortcut(keyCode: keyCode, carbonModifiers: modifiers, keyLabel: label)
    }

    private static let supportedKeyCodes: Set<UInt32> = Set([
        kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E,
        kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H, kVK_ANSI_I, kVK_ANSI_J,
        kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N, kVK_ANSI_O,
        kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T,
        kVK_ANSI_U, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X, kVK_ANSI_Y,
        kVK_ANSI_Z, kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3,
        kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8,
        kVK_ANSI_9, kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow,
        kVK_DownArrow, kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5,
        kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12
    ].map(UInt32.init))

    private struct ReservedShortcutMask {
        let keyCode: UInt32
        let requiredModifiers: UInt32
    }

    private static func isReservedSystemShortcut(
        keyCode: UInt32,
        modifiers: UInt32
    ) -> Bool {
        let voiceOverModifiers = UInt32(controlKey | optionKey)
        if modifiers & voiceOverModifiers == voiceOverModifiers {
            return true
        }

        return reservedSystemShortcutMasks.contains {
            $0.keyCode == keyCode
                && modifiers & $0.requiredModifiers == $0.requiredModifiers
        }
    }

    private static let reservedSystemShortcutMasks: [ReservedShortcutMask] = [
        ReservedShortcutMask(keyCode: UInt32(kVK_Escape), requiredModifiers: UInt32(cmdKey | optionKey)),
        ReservedShortcutMask(keyCode: UInt32(kVK_ANSI_Q), requiredModifiers: UInt32(cmdKey | controlKey)),
        ReservedShortcutMask(keyCode: UInt32(kVK_ANSI_Q), requiredModifiers: UInt32(cmdKey | shiftKey)),
        ReservedShortcutMask(keyCode: UInt32(kVK_ANSI_D), requiredModifiers: UInt32(cmdKey | optionKey)),
        ReservedShortcutMask(keyCode: UInt32(kVK_ANSI_F), requiredModifiers: UInt32(cmdKey | controlKey)),
        ReservedShortcutMask(keyCode: UInt32(kVK_ANSI_H), requiredModifiers: UInt32(cmdKey | optionKey)),
        ReservedShortcutMask(keyCode: UInt32(kVK_ANSI_M), requiredModifiers: UInt32(cmdKey | optionKey)),
        ReservedShortcutMask(keyCode: UInt32(kVK_ANSI_W), requiredModifiers: UInt32(cmdKey | optionKey)),
        ReservedShortcutMask(keyCode: UInt32(kVK_ANSI_3), requiredModifiers: UInt32(cmdKey | shiftKey)),
        ReservedShortcutMask(keyCode: UInt32(kVK_ANSI_4), requiredModifiers: UInt32(cmdKey | shiftKey)),
        ReservedShortcutMask(keyCode: UInt32(kVK_ANSI_5), requiredModifiers: UInt32(cmdKey | shiftKey)),
        ReservedShortcutMask(keyCode: UInt32(kVK_F5), requiredModifiers: UInt32(cmdKey | optionKey))
    ]

    private static let specialKeyLabels: [UInt32: String] = [
        UInt32(kVK_Return): "↩",
        UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Delete): "⌫",
        UInt32(kVK_ForwardDelete): "⌦",
        UInt32(kVK_Escape): "⎋",
        UInt32(kVK_Home): "↖",
        UInt32(kVK_End): "↘",
        UInt32(kVK_PageUp): "⇞",
        UInt32(kVK_PageDown): "⇟",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12"
    ]
}

enum GlobalShortcutValidationError: Equatable {
    case tooFewModifiers
    case requiresCommandOrControl
    case unsupportedKey
    case reservedSystemShortcut

    func message(language: WidgetLanguage) -> String {
        switch self {
        case .tooFewModifiers:
            return language.text(
                "自定义快捷键至少需要两个修饰键。",
                "Custom shortcuts require at least two modifier keys."
            )
        case .requiresCommandOrControl:
            return language.text(
                "快捷键必须包含 Command 或 Control。",
                "The shortcut must include Command or Control."
            )
        case .unsupportedKey:
            return language.text(
                "请选择字母、数字、方向键或 F1–F12。",
                "Choose a letter, number, arrow key, or F1–F12."
            )
        case .reservedSystemShortcut:
            return language.text(
                "该组合由 macOS 保留，请选择其他快捷键。",
                "This combination is reserved by macOS. Choose another shortcut."
            )
        }
    }
}

enum GlobalShortcutRegistrationFailure: Error, Equatable {
    case occupied
    case failed
}

enum GlobalShortcutRegistrationTransaction {
    static func replace<Reference>(
        current: Reference?,
        registerCandidate: () -> Result<Reference, GlobalShortcutRegistrationFailure>,
        unregister: (Reference) -> Result<Void, GlobalShortcutRegistrationFailure>,
        rollbackCandidate: (Reference) -> Void
    ) -> Result<Reference, GlobalShortcutRegistrationFailure> {
        switch registerCandidate() {
        case .failure(let error):
            return .failure(error)
        case .success(let candidate):
            if let current {
                switch unregister(current) {
                case .success:
                    break
                case .failure(let error):
                    rollbackCandidate(candidate)
                    return .failure(error)
                }
            }
            return .success(candidate)
        }
    }
}

enum GlobalShortcutError: Equatable {
    case invalid(GlobalShortcutValidationError)
    case occupied
    case registrationFailed
    case unregistrationFailed
    case savedShortcutUnavailableUsingDefault
    case noShortcutAvailable

    func message(language: WidgetLanguage) -> String {
        switch self {
        case .invalid(let error):
            return error.message(language: language)
        case .occupied:
            return language.text(
                "该快捷键已被其他应用独占，请选择其他组合。",
                "This shortcut is exclusively used by another app. Choose another combination."
            )
        case .registrationFailed:
            return language.text(
                "系统无法注册该快捷键，请选择其他组合。",
                "The system could not register this shortcut. Choose another combination."
            )
        case .unregistrationFailed:
            return language.text(
                "系统无法停用当前快捷键，原设置已保留。",
                "The system could not disable the current shortcut. The previous setting was kept."
            )
        case .savedShortcutUnavailableUsingDefault:
            return language.text(
                "保存的快捷键本次不可用，暂时使用默认快捷键；保存的选择未更改。",
                "The saved shortcut is unavailable for this launch, so the default is active temporarily. Your saved choice was not changed."
            )
        case .noShortcutAvailable:
            return language.text(
                "快捷键注册失败，本次启动没有可用的全局快捷键；保存的选择未更改。",
                "Shortcut registration failed. No global shortcut is active for this launch, and your saved choice was not changed."
            )
        }
    }
}
