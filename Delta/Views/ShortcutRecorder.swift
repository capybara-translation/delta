// Delta/Views/ShortcutRecorder.swift
import SwiftUI
import Carbon

/// A push-button that records a key combination: click to start, then press the
/// desired keys. Escape (or losing focus) cancels. A combination without
/// Command/Control/Option is rejected with a beep (recording continues).
///
/// While recording, the live global hotkey must be paused so it does not intercept
/// the very keys being typed (a Carbon hotkey swallows its combo system-wide).
/// `onRecordingStart` fires when recording begins, `onCancel` when it ends without
/// a capture; the caller pauses/resumes the hotkey accordingly. On a successful
/// capture the caller applies the new binding (which re-registers), so `onCancel`
/// is deliberately NOT fired in that case.
final class RecorderButton: NSButton {
    var onCapture: ((UInt32, UInt32) -> Void)?
    var onRecordingStart: (() -> Void)?
    var onCancel: (() -> Void)?
    var shortcutTitle: String = "" {
        didSet { if !recording { title = shortcutTitle } }
    }

    private var recording = false {
        didSet { title = recording ? "Type shortcut…" : shortcutTitle }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setButtonType(.momentaryPushIn)
        bezelStyle = .rounded
        target = self
        action = #selector(startRecording)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { isEnabled }

    @objc private func startRecording() {
        guard isEnabled, !recording else { return }
        recording = true
        onRecordingStart?()   // pause the live hotkey while recording
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }

        if event.keyCode == UInt16(kVK_Escape) {
            cancelRecording()
            return
        }

        let carbon = KeyCodeFormatter.carbonFlags(
            from: event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        )
        guard carbon & UInt32(cmdKey | controlKey | optionKey) != 0 else {
            NSSound.beep()   // require a real modifier; keep recording
            return
        }

        // Capture: the caller applies the new binding (which re-registers the
        // hotkey), so end recording WITHOUT firing onCancel.
        recording = false
        onCapture?(UInt32(event.keyCode), carbon)
        window?.makeFirstResponder(nil)
    }

    override func resignFirstResponder() -> Bool {
        // Focus lost while still recording (e.g. clicked elsewhere): treat as cancel.
        if recording { cancelRecording() }
        return super.resignFirstResponder()
    }

    /// End recording without capturing: restore the previously live hotkey.
    private func cancelRecording() {
        guard recording else { return }
        recording = false
        onCancel?()
        if window?.firstResponder === self { window?.makeFirstResponder(nil) }
    }
}

/// SwiftUI wrapper around RecorderButton.
struct ShortcutRecorder: NSViewRepresentable {
    let displayString: String
    let isEnabled: Bool
    let onCapture: (UInt32, UInt32) -> Void
    var onRecordingStart: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        configure(button)
        return button
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        configure(nsView)
    }

    private func configure(_ button: RecorderButton) {
        button.shortcutTitle = displayString
        button.isEnabled = isEnabled
        button.onCapture = onCapture
        button.onRecordingStart = onRecordingStart
        button.onCancel = onCancel
    }
}
