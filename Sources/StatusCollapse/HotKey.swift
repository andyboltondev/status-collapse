import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A key plus modifiers. Modifiers are Carbon flags, which is what registering a hotkey takes.
struct HotKeyCombo: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    /// The key as it should be shown, e.g. "C" or "Space".
    var label: String

    /// ⌃⌥S: the left hand can press all three keys, leaving the right on the mouse. Window
    /// managers (Rectangle, Magnet) use ⌃⌥ with arrows and a handful of other letters, but not S.
    /// Registration can't reveal clashes with other apps, so it is rebindable.
    static let standard = HotKeyCombo(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(controlKey | optionKey), label: "S")

    /// Earlier standards (⌃⌥C clashes with Rectangle, ⌃⌥⌘B was a short-lived draft); a saved copy
    /// of one is replaced by the current standard.
    static let retired = [
        HotKeyCombo(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(controlKey | optionKey), label: "C"),
        HotKeyCombo(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(controlKey | optionKey | cmdKey), label: "B"),
    ]

    var display: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + label
    }

    var plist: [String: Any] { ["keyCode": Int(keyCode), "modifiers": Int(modifiers), "label": label] }

    init(keyCode: UInt32, modifiers: UInt32, label: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.label = label
    }

    init?(plist: Any?) {
        guard let dict = plist as? [String: Any], let key = dict["keyCode"] as? Int,
              let mods = dict["modifiers"] as? Int, let label = dict["label"] as? String,
              key >= 0, mods >= 0 else { return nil }
        self.init(keyCode: UInt32(key), modifiers: UInt32(mods), label: label)
    }

    /// The combo for a key press, or nil if it has no ⌃, ⌥ or ⌘, which would make the key
    /// unusable for typing.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.control, .option, .command]).isEmpty else { return nil }
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        let label = Self.names[Int(event.keyCode)] ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
        guard !label.isEmpty else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: mods, label: label)
    }

    private static let names: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}

/// Registers the one global hotkey. Carbon hotkeys need no Accessibility or Input Monitoring
/// permission, and the system only delivers this key combination.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var action: () -> Void = {}
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    /// Registers `combo`, replacing any earlier one; nil just unregisters. Returns false if the
    /// system refused it, usually because another app or macOS already owns the combination.
    @discardableResult
    func register(_ combo: HotKeyCombo?) -> Bool {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        guard let combo else { return true }

        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                // Delivered on the main thread.
                MainActor.assumeIsolated { HotKeyCenter.shared.action() }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x5343_4F4C), id: 1) // 'SCOL'
        return RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &hotKey) == noErr
    }
}

// MARK: - Recorder

/// A button that shows a shortcut and records a new one when clicked. Esc cancels.
struct HotKeyRecorder: NSViewRepresentable {
    let combo: HotKeyCombo
    let prompt: String
    let recordingChanged: (Bool) -> Void
    let recorded: (HotKeyCombo) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.combo = combo
        button.prompt = prompt
        button.recordingChanged = recordingChanged
        button.recorded = recorded
        button.refresh()
    }

    final class RecorderButton: NSButton {
        var combo = HotKeyCombo.standard
        var prompt = ""
        var recordingChanged: (Bool) -> Void = { _ in }
        var recorded: (HotKeyCombo) -> Void = { _ in }
        private var isRecording = false

        override var acceptsFirstResponder: Bool { true }
        override var intrinsicContentSize: NSSize {
            var size = super.intrinsicContentSize
            size.width = max(size.width, 130)
            return size
        }

        override init(frame: NSRect) {
            super.init(frame: frame)
            target = self
            action = #selector(begin)
        }

        required init?(coder: NSCoder) { fatalError() }

        func refresh() { title = isRecording ? prompt : combo.display }

        @objc private func begin() {
            guard !isRecording else { return end() }
            isRecording = true
            window?.makeFirstResponder(self)
            recordingChanged(true)
            refresh()
        }

        private func end() {
            guard isRecording else { return }
            isRecording = false
            recordingChanged(false)
            refresh()
        }

        override func resignFirstResponder() -> Bool {
            end()
            return super.resignFirstResponder()
        }

        override func keyDown(with event: NSEvent) {
            guard isRecording else { return super.keyDown(with: event) }
            if event.keyCode == UInt16(kVK_Escape) { return end() }
            guard let new = HotKeyCombo(event: event) else { return NSSound.beep() }
            end()
            recorded(new)
        }

        /// ⌘ combinations reach the menu bar first unless claimed here.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard isRecording else { return super.performKeyEquivalent(with: event) }
            keyDown(with: event)
            return true
        }
    }
}
