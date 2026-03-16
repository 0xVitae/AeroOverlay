import AppKit

final class HotkeyRecorderView: NSView {
    private let label = NSTextField(labelWithString: "")
    private var isRecording = false
    var onHotkeySet: ((UInt16, NSEvent.ModifierFlags) -> Void)?
    var onHotkeyClear: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        updateAppearance()

        label.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
        ])

        updateLabel()
    }

    private func updateAppearance() {
        if isRecording {
            layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.15).cgColor
            layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.5).cgColor
        } else {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        }
    }

    func updateLabel() {
        if isRecording {
            label.stringValue = "Press shortcut..."
            label.textColor = .systemBlue
        } else {
            label.stringValue = SettingsStore.shared.hotkeyDisplayString
            label.textColor = .labelColor
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        updateAppearance()
        updateLabel()
        window?.makeFirstResponder(self)
    }

    private func stopRecording() {
        isRecording = false
        updateAppearance()
        updateLabel()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        let keyCode = event.keyCode

        // Escape cancels recording
        if keyCode == 53 {
            stopRecording()
            return
        }

        // Delete/Backspace clears the hotkey
        if keyCode == 51 || keyCode == 117 {
            onHotkeyClear?()
            stopRecording()
            return
        }

        // Require at least one modifier for a valid hotkey
        let mods = event.modifierFlags.intersection([.control, .option, .shift, .command])
        if mods.isEmpty {
            return
        }

        onHotkeySet?(keyCode, mods)
        stopRecording()
    }

    override func flagsChanged(with event: NSEvent) {
        // Don't process raw modifier presses as hotkeys
        if isRecording { return }
        super.flagsChanged(with: event)
    }

    override func resignFirstResponder() -> Bool {
        if isRecording { stopRecording() }
        return super.resignFirstResponder()
    }
}
