import AppKit

final class SettingsViewController: NSViewController {
    private let settings = SettingsStore.shared
    private var hotkeyRecorder: HotkeyRecorderView!
    private var intervalRow: NSStackView!

    override func loadView() {
        let bg = NSVisualEffectView()
        bg.material = .hudWindow
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.maskImage = Self.roundedCornerMask(radius: 12)
        self.view = bg
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    private func buildUI() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20),
        ])

        // Header
        let header = NSTextField(labelWithString: "SETTINGS")
        header.font = NSFont.systemFont(ofSize: 16, weight: .light)
        header.attributedStringValue = NSAttributedString(string: "SETTINGS", attributes: [
            .font: NSFont.systemFont(ofSize: 16, weight: .light),
            .foregroundColor: NSColor.white,
            .kern: 3.0,
        ])
        stack.addArrangedSubview(header)

        // Divider
        stack.addArrangedSubview(makeDivider())

        // --- Activation Section ---
        stack.addArrangedSubview(makeSectionLabel("Activation"))

        // Hotkey recorder
        let hotkeyRow = NSStackView()
        hotkeyRow.orientation = .horizontal
        hotkeyRow.spacing = 12
        hotkeyRow.alignment = .centerY

        let hotkeyLabel = NSTextField(labelWithString: "Hotkey")
        hotkeyLabel.font = .systemFont(ofSize: 13)
        hotkeyLabel.textColor = .secondaryLabelColor
        hotkeyLabel.widthAnchor.constraint(equalToConstant: 120).isActive = true
        hotkeyRow.addArrangedSubview(hotkeyLabel)

        hotkeyRecorder = HotkeyRecorderView()
        hotkeyRecorder.translatesAutoresizingMaskIntoConstraints = false
        hotkeyRecorder.widthAnchor.constraint(equalToConstant: 200).isActive = true
        hotkeyRecorder.heightAnchor.constraint(equalToConstant: 28).isActive = true
        hotkeyRecorder.onHotkeySet = { [weak self] keyCode, mods in
            self?.settings.hotkeyKeyCode = keyCode
            self?.settings.hotkeyModifiers = mods
            self?.hotkeyRecorder.updateLabel()
            self?.updateIntervalVisibility()
        }
        hotkeyRecorder.onHotkeyClear = { [weak self] in
            self?.settings.clearHotkey()
            self?.hotkeyRecorder.updateLabel()
            self?.updateIntervalVisibility()
        }
        hotkeyRow.addArrangedSubview(hotkeyRecorder)

        let defaultBtn = NSButton(title: "Default", target: self, action: #selector(resetHotkeyToDefault))
        defaultBtn.bezelStyle = .rounded
        defaultBtn.setButtonType(.momentaryPushIn)
        defaultBtn.font = .systemFont(ofSize: 11)
        hotkeyRow.addArrangedSubview(defaultBtn)

        stack.addArrangedSubview(hotkeyRow)

        let hotkeyHint = NSTextField(labelWithString: "Click to record. Backspace to clear. Escape to cancel.")
        hotkeyHint.font = .systemFont(ofSize: 10)
        hotkeyHint.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(hotkeyHint)

        // Double-tap interval
        intervalRow = NSStackView()
        intervalRow.orientation = .horizontal
        intervalRow.spacing = 12
        intervalRow.alignment = .centerY

        let intervalTitle = NSTextField(labelWithString: "Double-tap Speed")
        intervalTitle.font = .systemFont(ofSize: 13)
        intervalTitle.textColor = .secondaryLabelColor
        intervalTitle.widthAnchor.constraint(equalToConstant: 120).isActive = true
        intervalRow.addArrangedSubview(intervalTitle)

        let intervalField = NSTextField(string: "\(Int(settings.doubleTapInterval * 1000))")
        intervalField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        intervalField.textColor = .labelColor
        intervalField.backgroundColor = NSColor.white.withAlphaComponent(0.08)
        intervalField.isBordered = true
        intervalField.isEditable = true
        intervalField.alignment = .center
        intervalField.target = self
        intervalField.action = #selector(intervalFieldChanged(_:))
        intervalField.widthAnchor.constraint(equalToConstant: 50).isActive = true
        intervalRow.addArrangedSubview(intervalField)

        let msLabel = NSTextField(labelWithString: "ms")
        msLabel.font = .systemFont(ofSize: 12)
        msLabel.textColor = .tertiaryLabelColor
        intervalRow.addArrangedSubview(msLabel)

        stack.addArrangedSubview(intervalRow)
        updateIntervalVisibility()

        // Divider
        stack.addArrangedSubview(makeDivider())

        // --- Display Section ---
        stack.addArrangedSubview(makeSectionLabel("Display"))

        stack.addArrangedSubview(makeToggleRow("System Stats", isOn: settings.showSystemStats) { [weak self] val in
            self?.settings.showSystemStats = val
        })

        stack.addArrangedSubview(makeToggleRow("Claude Usage", isOn: settings.showClaudeUsage) { [weak self] val in
            self?.settings.showClaudeUsage = val
        })

        // Divider
        stack.addArrangedSubview(makeDivider())

        // --- Advanced Section ---
        stack.addArrangedSubview(makeSectionLabel("Advanced"))

        let pathRow = NSStackView()
        pathRow.orientation = .horizontal
        pathRow.spacing = 12
        pathRow.alignment = .centerY

        let pathLabel = NSTextField(labelWithString: "AeroSpace Path")
        pathLabel.font = .systemFont(ofSize: 13)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.widthAnchor.constraint(equalToConstant: 120).isActive = true
        pathRow.addArrangedSubview(pathLabel)

        let pathField = NSTextField(string: settings.aerospacePath)
        pathField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        pathField.textColor = .labelColor
        pathField.backgroundColor = NSColor.white.withAlphaComponent(0.08)
        pathField.isBordered = true
        pathField.isEditable = true
        pathField.target = self
        pathField.action = #selector(pathFieldChanged(_:))
        pathField.widthAnchor.constraint(equalToConstant: 200).isActive = true
        pathRow.addArrangedSubview(pathField)

        stack.addArrangedSubview(pathRow)

        // Esc hint at bottom
        let escHint = NSTextField(labelWithString: "Press Esc to close")
        escHint.font = .systemFont(ofSize: 10)
        escHint.textColor = .tertiaryLabelColor
        escHint.alignment = .center
        escHint.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(escHint)
        escHint.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func updateIntervalVisibility() {
        intervalRow?.isHidden = settings.hotkeyKeyCode != nil
    }

    @objc private func resetHotkeyToDefault() {
        settings.clearHotkey()
        hotkeyRecorder.updateLabel()
        updateIntervalVisibility()
    }

    @objc private func intervalFieldChanged(_ sender: NSTextField) {
        let ms = max(100, min(1000, Int(sender.stringValue) ?? 250))
        settings.doubleTapInterval = Double(ms) / 1000.0
        sender.stringValue = "\(ms)"
    }

    @objc private func pathFieldChanged(_ sender: NSTextField) {
        settings.aerospacePath = sender.stringValue
    }

    private func makeSectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        label.attributedStringValue = NSAttributedString(string: title.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.tertiaryLabelColor,
            .kern: 1.5,
        ])
        return label
    }

    private func makeDivider() -> NSView {
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        divider.widthAnchor.constraint(equalToConstant: 340).isActive = true
        return divider
    }

    private func makeToggleRow(_ title: String, isOn: Bool, onChange: @escaping (Bool) -> Void) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.widthAnchor.constraint(equalToConstant: 120).isActive = true
        row.addArrangedSubview(label)

        let toggle = NSSwitch()
        toggle.state = isOn ? .on : .off
        let handler = ToggleHandler(onChange: onChange)
        toggle.target = handler
        toggle.action = #selector(ToggleHandler.toggled(_:))
        // Prevent handler from being deallocated
        objc_setAssociatedObject(toggle, "handler", handler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        row.addArrangedSubview(toggle)

        return row
    }

    private static func roundedCornerMask(radius: CGFloat) -> NSImage {
        let edgeLen = 2.0 * radius + 1.0
        let image = NSImage(size: NSSize(width: edgeLen, height: edgeLen), flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            NSColor.black.set()
            path.fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

private class ToggleHandler: NSObject {
    let onChange: (Bool) -> Void
    init(onChange: @escaping (Bool) -> Void) { self.onChange = onChange; super.init() }
    @objc func toggled(_ sender: NSSwitch) { onChange(sender.state == .on) }
}
