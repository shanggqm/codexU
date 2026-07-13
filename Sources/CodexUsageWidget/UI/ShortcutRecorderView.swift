import Cocoa
import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorderView: NSViewRepresentable {
    let shortcut: GlobalShortcut?
    let language: WidgetLanguage
    let onRecord: (GlobalShortcut) -> Bool
    let onClear: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderControl {
        let control = ShortcutRecorderControl()
        control.onRecord = onRecord
        control.onClear = onClear
        control.language = language
        control.shortcut = shortcut
        return control
    }

    func updateNSView(_ control: ShortcutRecorderControl, context: Context) {
        control.onRecord = onRecord
        control.onClear = onClear
        control.language = language
        control.shortcut = shortcut
        control.refresh()
    }
}

final class ShortcutRecorderControl: NSButton {
    var shortcut: GlobalShortcut?
    var language: WidgetLanguage = .automatic
    var onRecord: ((GlobalShortcut) -> Bool)?
    var onClear: (() -> Void)?
    private var isRecording = false
    private var keyDownMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(beginRecording)
        focusRingType = .default
        updateTitle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        removeKeyDownMonitor()
    }

    override var acceptsFirstResponder: Bool { true }

    @objc private func beginRecording() {
        guard let window, window.makeFirstResponder(self) else {
            NSSound.beep()
            return
        }
        isRecording = true
        installKeyDownMonitor()
        updateTitle()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        handleRecordingKeyDown(event)
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign { cancelRecording() }
        return didResign
    }

    private func handleRecordingKeyDown(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasShortcutModifier = flags.contains(.command)
            || flags.contains(.option)
            || flags.contains(.shift)
            || flags.contains(.control)

        if event.keyCode == UInt16(kVK_Delete), !hasShortcutModifier {
            onClear?()
            finishRecording()
            return
        }
        if event.keyCode == UInt16(kVK_Escape), !hasShortcutModifier {
            finishRecording()
            return
        }
        guard let candidate = GlobalShortcut.from(event: event) else {
            NSSound.beep()
            return
        }
        guard onRecord?(candidate) == true else {
            NSSound.beep()
            return
        }
        finishRecording()
    }

    private func installKeyDownMonitor() {
        removeKeyDownMonitor()
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  self.isRecording,
                  self.window?.isKeyWindow == true,
                  self.window?.firstResponder === self
            else { return event }
            self.handleRecordingKeyDown(event)
            return nil
        }
    }

    private func removeKeyDownMonitor() {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
    }

    private func finishRecording() {
        isRecording = false
        removeKeyDownMonitor()
        updateTitle()
    }

    private func cancelRecording() {
        guard isRecording || keyDownMonitor != nil else { return }
        isRecording = false
        removeKeyDownMonitor()
        updateTitle()
    }

    private func updateTitle() {
        title = isRecording
            ? language.text("请按新快捷键", "Press shortcut")
            : shortcut?.displayName ?? language.text("未设置", "Not set")
        let help = language.text(
            "激活后录制新快捷键；录制时按退格键清空，按 Esc 取消。",
            "Activate to record a new shortcut. While recording, press Backspace to clear or Escape to cancel."
        )
        toolTip = help
        setAccessibilityLabel(language.text("主窗口快捷键", "Main window shortcut"))
        setAccessibilityValue(title)
        setAccessibilityHelp(help)
    }

    func refresh() {
        updateTitle()
    }
}
