import AppKit

private extension NSBezierPath {
    var cgPathRef: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo: path.move(to: points[0])
            case .lineTo: path.addLine(to: points[0])
            case .curveTo: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath: path.closeSubpath()
            case .cubicCurveTo: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo: path.addQuadCurve(to: points[1], control: points[0])
            @unknown default: break
            }
        }
        return path
    }
}

final class WorkspaceCell: NSView {
    private let workspace: WorkspaceInfo
    private let label = NSTextField(labelWithString: "")
    private let windowStack = NSStackView()
    var onClick: ((String) -> Void)?
    private(set) var isSelected = false
    var isFocusedWorkspace: Bool { workspace.isFocused }
    var workspaceName: String { workspace.name }
    private let hasNotification: Bool
    private let notifiedWindowIDs: Set<Int>
    private var gradientBorderLayer: CAGradientLayer?
    private var focusBorderLayer: CAGradientLayer?
    private var selectionBorderLayer: CAGradientLayer?
    private var badgeView: NSTextField?

    init(workspace: WorkspaceInfo, hasNotification: Bool = false, notifiedWindowIDs: Set<Int> = []) {
        self.workspace = workspace
        self.hasNotification = hasNotification
        self.notifiedWindowIDs = notifiedWindowIDs
        super.init(frame: .zero)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = false

        if hasNotification {
            layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.06).cgColor
            // Gradient border added in layout
        } else if workspace.isFocused {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
            // Gradient border added in layout
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
        let isExternal = workspace.monitorName != nil && workspace.monitorName != NSScreen.main?.localizedName

        label.stringValue = workspace.name.uppercased()
        label.font = .systemFont(ofSize: 16, weight: workspace.isFocused ? .bold : .semibold)
        label.textColor = workspace.isFocused ? .white : (workspace.windows.isEmpty ? .tertiaryLabelColor : .secondaryLabelColor)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        // External monitor icon positioned to the right of the label
        if isExternal {
            if let symbolImage = NSImage(systemSymbolName: "display", accessibilityDescription: "External monitor") {
                let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
                let icon = NSImageView(image: symbolImage.withSymbolConfiguration(config) ?? symbolImage)
                icon.contentTintColor = .tertiaryLabelColor
                icon.translatesAutoresizingMaskIntoConstraints = false
                addSubview(icon)
                NSLayoutConstraint.activate([
                    icon.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 3),
                    icon.centerYAnchor.constraint(equalTo: label.centerYAnchor),
                ])
            }
        }

        // "TODO" badge inline on the top border
        if hasNotification {
            let badge = NSTextField(labelWithString: "  TODO  ")
            badge.font = .systemFont(ofSize: 8, weight: .bold)
            badge.textColor = .white
            badge.wantsLayer = true
            badge.layer?.backgroundColor = NSColor.systemOrange.cgColor
            badge.layer?.cornerRadius = 3
            badge.layer?.masksToBounds = true
            badge.alignment = .center
            badge.setContentCompressionResistancePriority(.required, for: .horizontal)
            badge.setContentHuggingPriority(.required, for: .horizontal)
            badge.translatesAutoresizingMaskIntoConstraints = false
            addSubview(badge, positioned: .above, relativeTo: nil)
            badge.layer?.zPosition = 999
            badgeView = badge
            NSLayoutConstraint.activate([
                badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
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

            // Orange dot next to the specific terminal window that triggered the notification
            if notifiedWindowIDs.contains(win.windowID) {
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
        let bottomAnchorView: NSView = workspace.windows.isEmpty ? label : windowStack
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

        if hasNotification {
            gradientBorderLayer = makeGradientBorder(color: .systemOrange)
        }
        if workspace.isFocused && !hasNotification {
            focusBorderLayer = makeGradientBorder(color: .systemBlue, lineWidth: 2.5)
        }
        setupSelectionBorder()
    }

    private func setupSelectionBorder() {
        let gradient = CAGradientLayer()
        gradient.colors = [
            NSColor.white.cgColor,
            NSColor.white.withAlphaComponent(0.4).cgColor,
            NSColor.white.withAlphaComponent(0.0).cgColor,
        ]
        gradient.locations = [0.0, 0.5, 1.0]
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)

        let shape = CAShapeLayer()
        shape.lineWidth = 2.5
        shape.fillColor = nil
        shape.strokeColor = NSColor.white.cgColor

        gradient.mask = shape
        gradient.isHidden = true
        layer?.addSublayer(gradient)
        selectionBorderLayer = gradient
    }

    private func makeGradientBorder(color: NSColor, lineWidth: CGFloat = 2) -> CAGradientLayer {
        let gradient = CAGradientLayer()
        gradient.colors = [
            color.cgColor,
            color.withAlphaComponent(0.3).cgColor,
            color.withAlphaComponent(0.0).cgColor,
        ]
        gradient.locations = [0.0, 0.5, 1.0]
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)

        let shape = CAShapeLayer()
        shape.lineWidth = lineWidth
        shape.fillColor = nil
        shape.strokeColor = NSColor.white.cgColor

        gradient.mask = shape
        layer?.addSublayer(gradient)
        return gradient
    }

    override func layout() {
        super.layout()
        let borderPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10).cgPathRef
        if let gradient = gradientBorderLayer {
            gradient.frame = bounds
            (gradient.mask as? CAShapeLayer)?.path = borderPath
        }
        if let focus = focusBorderLayer {
            focus.frame = bounds
            (focus.mask as? CAShapeLayer)?.path = borderPath
        }
        if let sel = selectionBorderLayer {
            sel.frame = bounds
            (sel.mask as? CAShapeLayer)?.path = borderPath
        }
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
            bgColor = NSColor.systemOrange.withAlphaComponent(0.06)
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
            gradientBorderLayer?.isHidden = hasNotification ? false : true
            focusBorderLayer?.isHidden = true
            selectionBorderLayer?.isHidden = false
            layer?.borderColor = nil
            layer?.borderWidth = 0
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        } else if hasNotification {
            selectionBorderLayer?.isHidden = true
            focusBorderLayer?.isHidden = true
            layer?.borderColor = nil
            layer?.borderWidth = 0
            layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.06).cgColor
            gradientBorderLayer?.isHidden = false
        } else if workspace.isFocused {
            selectionBorderLayer?.isHidden = true
            focusBorderLayer?.isHidden = false
            layer?.borderColor = nil
            layer?.borderWidth = 0
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        } else if workspace.windows.isEmpty {
            selectionBorderLayer?.isHidden = true
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.03).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.06).cgColor
            layer?.borderWidth = 1
        } else {
            selectionBorderLayer?.isHidden = true
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
