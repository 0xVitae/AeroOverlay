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

            let displayTitle = formatWindowTitle(appName: win.appName, title: win.windowTitle, windowID: win.windowID)
            let titleLabel = NSTextField(labelWithString: truncate(displayTitle, max: 28))
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
        "Terminal", "iTerm2", "Alacritty", "kitty", "WezTerm", "Hyper", "Ghostty",
    ]

    private static func isTerminalApp(_ appName: String) -> Bool {
        terminalAppNames.contains(appName)
    }

    /// Map of windowID → cwd, built once per reload using sorted window-id / shell-pid matching.
    private static var windowCwdMap: [Int: String] = [:]

    /// Call before creating cells to build the windowID→cwd map for all terminal windows.
    static func buildTerminalCwdMap(allWorkspaces: [WorkspaceInfo]) {
        windowCwdMap.removeAll()

        // Group terminal windows by app name, sorted by window-id (creation order)
        var termWindowsByApp: [String: [Int]] = [:]
        for ws in allWorkspaces {
            for win in ws.windows {
                if isTerminalApp(win.appName) {
                    termWindowsByApp[win.appName, default: []].append(win.windowID)
                }
            }
        }

        for (appName, windowIDs) in termWindowsByApp {
            let sortedWindowIDs = windowIDs.sorted() // ascending = older first
            let cwds = fetchAllShellCwds(for: appName) // sorted by PID = older first
            log("buildTerminalCwdMap: \(appName) windows=\(sortedWindowIDs) cwds=\(cwds)")
            for (i, wid) in sortedWindowIDs.enumerated() {
                if i < cwds.count {
                    windowCwdMap[wid] = cwds[i]
                }
            }
        }
        log("buildTerminalCwdMap: final map=\(windowCwdMap)")
    }

    /// Find PIDs for a terminal app by matching against `ps` output.
    private static func findAppPids(_ appName: String) -> [Int] {
        guard let psOutput = runShell("/bin/ps", ["-eo", "pid,comm"]) else { return [] }
        return psOutput.split(separator: "\n").compactMap { line -> Int? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", maxSplits: 1)
            guard parts.count == 2, let pid = Int(parts[0]) else { return nil }
            let comm = String(parts[1])
            if comm.localizedCaseInsensitiveContains(appName),
               (comm.contains(".app/Contents/MacOS/") || comm.hasSuffix("/\(appName.lowercased())")) {
                return pid
            }
            return nil
        }
    }

    /// Walk the process tree to find all shell cwds under a terminal app, sorted by PID.
    private static func fetchAllShellCwds(for appName: String) -> [String] {
        let matchedPids = findAppPids(appName)
        // Collect (shellPid, cwd) pairs so we can sort by PID
        var pidCwdPairs: [(pid: Int, cwd: String)] = []

        for termPid in matchedPids {
            guard let childOut = runShell("/usr/bin/pgrep", ["-P", "\(termPid)"]) else { continue }
            let childPids = childOut.split(separator: "\n").compactMap { Int(String($0).trimmingCharacters(in: .whitespaces)) }

            for childPid in childPids {
                guard let shellOut = runShell("/usr/bin/pgrep", ["-P", "\(childPid)"]) else { continue }
                let shellPids = shellOut.split(separator: "\n").compactMap { Int(String($0).trimmingCharacters(in: .whitespaces)) }

                for shellPid in shellPids {
                    if let cwd = getCwdForPid(shellPid), cwd != "/" {
                        pidCwdPairs.append((pid: shellPid, cwd: cwd))
                    }
                }
            }
        }

        // Sort by PID (creation order) to match window-id sort order
        return pidCwdPairs.sorted { $0.pid < $1.pid }.map { $0.cwd }
    }

    private static func getCwdForPid(_ pid: Int) -> String? {
        let info = UnsafeMutablePointer<proc_vnodepathinfo>.allocate(capacity: 1)
        defer { info.deallocate() }
        let size = proc_pidinfo(pid_t(pid), PROC_PIDVNODEPATHINFO, 0, info, Int32(MemoryLayout<proc_vnodepathinfo>.size))
        guard size == MemoryLayout<proc_vnodepathinfo>.size else { return nil }
        return withUnsafePointer(to: &info.pointee.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
    }

    private static func runShell(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private func truncate(_ s: String, max: Int) -> String {
        s.count > max ? String(s.prefix(max)) + "…" : s
    }

    private func formatWindowTitle(appName: String, title: String, windowID: Int) -> String {
        // For Cursor/VS Code: extract folder name after "—" separator
        if appName.contains("Cursor") || (appName.contains("Code") && !Self.isTerminalApp(appName)) {
            let parts = title.split(separator: "—", maxSplits: 1, omittingEmptySubsequences: true)
            if parts.count == 2 {
                return String(parts[1]).trimmingCharacters(in: .whitespaces)
            }
        }

        // For terminal apps: look up cwd from the pre-built windowID map
        if Self.isTerminalApp(appName) {
            if let cwd = Self.windowCwdMap[windowID] {
                let components = cwd.split(separator: "/", omittingEmptySubsequences: true)
                if let folderName = components.last {
                    if title.contains("Claude Code") {
                        return "✳ CC - \(folderName)"
                    }
                    return String(folderName)
                }
            }
        }

        return title
    }

    private static func log(_ message: String) {
        let logPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".aerooverlay-debug.log").path
        let ts = DateFormatter()
        ts.dateFormat = "HH:mm:ss"
        let line = "[\(ts.string(from: Date()))] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let fh = FileHandle(forWritingAtPath: logPath) {
                    fh.seekToEndOfFile()
                    fh.write(data)
                    fh.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: logPath, contents: data)
            }
        }
    }

}
