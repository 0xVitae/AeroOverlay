import AppKit

final class WorkspaceCell: NSView {
    private let workspace: WorkspaceInfo
    private let label = NSTextField(labelWithString: "")
    private let windowStack = NSStackView()
    var onClick: ((String) -> Void)?
    private(set) var isSelected = false
    var isFocusedWorkspace: Bool { workspace.isFocused }
    var workspaceName: String { workspace.name }
    private let hasNotification: Bool

    init(workspace: WorkspaceInfo, hasNotification: Bool = false) {
        self.workspace = workspace
        self.hasNotification = hasNotification
        super.init(frame: .zero)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 10

        if hasNotification {
            layer?.borderColor = NSColor.systemOrange.cgColor
            layer?.borderWidth = 2
            layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.08).cgColor
        } else if workspace.isFocused {
            layer?.borderColor = NSColor.systemBlue.cgColor
            layer?.borderWidth = 2.5
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        } else if workspace.windows.isEmpty {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.03).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.06).cgColor
            layer?.borderWidth = 1
        } else {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
            layer?.borderWidth = 1
        }

        // Workspace label
        label.stringValue = workspace.name.uppercased()
        label.font = .systemFont(ofSize: 16, weight: workspace.isFocused ? .bold : .semibold)
        label.textColor = workspace.isFocused ? .white : (workspace.windows.isEmpty ? .tertiaryLabelColor : .secondaryLabelColor)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        // "TODO" badge inline on the top border
        if hasNotification {
            let badge = NSTextField(labelWithString: "TODO")
            badge.font = .systemFont(ofSize: 8, weight: .bold)
            badge.textColor = .white
            badge.wantsLayer = true
            badge.layer?.backgroundColor = NSColor.systemOrange.cgColor
            badge.layer?.cornerRadius = 3
            badge.alignment = .center
            badge.translatesAutoresizingMaskIntoConstraints = false
            // Padding via custom cell or just use the label directly
            addSubview(badge)
            NSLayoutConstraint.activate([
                badge.centerXAnchor.constraint(equalTo: trailingAnchor, constant: -20),
                badge.centerYAnchor.constraint(equalTo: topAnchor),
            ])
        }

        // Window list
        windowStack.orientation = .vertical
        windowStack.alignment = .leading
        windowStack.spacing = 3
        windowStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(windowStack)

        for win in workspace.windows.prefix(5) {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 4
            row.alignment = .centerY

            // App icon
            if let icon = WindowCapture.appIcon(for: win.appName) {
                let iconView = NSImageView(image: icon)
                iconView.translatesAutoresizingMaskIntoConstraints = false
                iconView.widthAnchor.constraint(equalToConstant: 14).isActive = true
                iconView.heightAnchor.constraint(equalToConstant: 14).isActive = true
                row.addArrangedSubview(iconView)
            }

            // Orange dot next to terminal-type apps when workspace has a TODO
            if hasNotification && Self.isTerminalApp(win.appName) {
                let dot = NSView()
                dot.wantsLayer = true
                dot.layer?.cornerRadius = 3
                dot.layer?.backgroundColor = NSColor.systemOrange.cgColor
                dot.translatesAutoresizingMaskIntoConstraints = false
                dot.widthAnchor.constraint(equalToConstant: 6).isActive = true
                dot.heightAnchor.constraint(equalToConstant: 6).isActive = true
                row.addArrangedSubview(dot)
            }

            let titleLabel = NSTextField(labelWithString: truncate(win.windowTitle, max: 28))
            titleLabel.font = .systemFont(ofSize: 10)
            titleLabel.textColor = workspace.isFocused ? .labelColor : .secondaryLabelColor
            titleLabel.lineBreakMode = .byTruncatingTail
            row.addArrangedSubview(titleLabel)

            windowStack.addArrangedSubview(row)
        }

        if workspace.windows.count > 5 {
            let moreLabel = NSTextField(labelWithString: "+\(workspace.windows.count - 5) more")
            moreLabel.font = .systemFont(ofSize: 9)
            moreLabel.textColor = .tertiaryLabelColor
            windowStack.addArrangedSubview(moreLabel)
        }

        // Pin bottom to define intrinsic height
        let bottomAnchorView = workspace.windows.isEmpty ? label : windowStack
        let bottomPin = bottomAnchorView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        bottomPin.priority = .defaultHigh // Allow min height to win if content is tiny

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            windowStack.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 6),
            windowStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            windowStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            bottomPin,
        ])

        setContentHuggingPriority(.required, for: .vertical)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?(workspace.name)
    }

    // Hover effect
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            self.animator().layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        let bgColor: NSColor
        if hasNotification {
            bgColor = NSColor.systemOrange.withAlphaComponent(0.08)
        } else {
            let alpha: CGFloat = workspace.isFocused ? 0.12 : (workspace.windows.isEmpty ? 0.03 : 0.07)
            bgColor = NSColor.white.withAlphaComponent(alpha)
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            self.animator().layer?.backgroundColor = bgColor.cgColor
        }
    }

    func setSelected(_ selected: Bool) {
        isSelected = selected
        if selected {
            layer?.borderColor = hasNotification ? NSColor.systemOrange.cgColor : NSColor.white.cgColor
            layer?.borderWidth = 2.5
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        } else if hasNotification {
            layer?.borderColor = NSColor.systemOrange.cgColor
            layer?.borderWidth = 2
            layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.08).cgColor
        } else if workspace.isFocused {
            layer?.borderColor = NSColor.systemBlue.cgColor
            layer?.borderWidth = 2.5
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        } else if workspace.windows.isEmpty {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.03).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.06).cgColor
            layer?.borderWidth = 1
        } else {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
            layer?.borderWidth = 1
        }
    }

    private static let terminalAppNames: Set<String> = [
        "Terminal", "iTerm2", "Alacritty", "kitty", "WezTerm", "Hyper",
        "Cursor", "Code", "Visual Studio Code", "Ghostty",
    ]

    private static func isTerminalApp(_ appName: String) -> Bool {
        terminalAppNames.contains(appName)
    }

    private func truncate(_ s: String, max: Int) -> String {
        s.count > max ? String(s.prefix(max)) + "…" : s
    }
}
