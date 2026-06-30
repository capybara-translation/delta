// Delta/Views/ShortcutRecorder.swift
import SwiftUI
import Carbon

/// A push-button that records a key combination: click to start, then press the
/// desired keys. Escape cancels. A combination without Command/Control/Option is
/// rejected with a beep (recording continues).
final class RecorderButton: NSButton {
    var onCapture: ((UInt32, UInt32) -> Void)?
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
        guard isEnabled else { return }
        recording = true
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }

        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }

        let carbon = KeyCodeFormatter.carbonFlags(
            from: event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        )
        guard carbon & UInt32(cmdKey | controlKey | optionKey) != 0 else {
            NSSound.beep()   // require a real modifier; keep recording
            return
        }

        onCapture?(UInt32(event.keyCode), carbon)
        stopRecording()
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        return super.resignFirstResponder()
    }

    private func stopRecording() {
        recording = false
        window?.makeFirstResponder(nil)
    }
}

/// SwiftUI wrapper around RecorderButton.
struct ShortcutRecorder: NSViewRepresentable {
    let displayString: String
    let isEnabled: Bool
    let onCapture: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.shortcutTitle = displayString
        button.isEnabled = isEnabled
        button.onCapture = onCapture
        return button
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        nsView.shortcutTitle = displayString
        nsView.isEnabled = isEnabled
        nsView.onCapture = onCapture
    }
}
