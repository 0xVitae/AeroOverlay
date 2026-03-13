import AppKit

final class OverlayViewController: NSViewController {
    private let client = AeroSpaceClient()
    var onSelectWorkspace: ((String) -> Void)?
    private var visibleGrid: [[WorkspaceCell]] = [] // 2D grid of visible cells
    private var selRow = 0
    private var selCol = 0

    // Keyboard-matching grid layout
    private let gridRows: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9"],
        ["q", "w", "e", "r", "t", "y"],
        ["a", "s", "d", "f"],
        ["o"],
    ]

    override func loadView() {
        let bg = NSVisualEffectView()
        bg.material = .hudWindow
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 16
        bg.layer?.masksToBounds = true
        self.view = bg
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reload()
    }

    func reload() {
        // Clear existing subviews
        for sub in view.subviews where sub !== view { sub.removeFromSuperview() }
        visibleGrid = []
        selRow = 0
        selCol = 0

        let allWorkspaces = client.fetchAll()
        let wsMap = Dictionary(uniqueKeysWithValues: allWorkspaces.map { ($0.name, $0) })
        let activeNames = Set(allWorkspaces.filter { !$0.windows.isEmpty }.map { $0.name })
        let notifiedWorkspaces = OverlayNotifications.pending()

        // Find the next inactive workspace in grid order
        let allNamesInOrder = gridRows.flatMap { $0 }
        let nextInactive = allNamesInOrder.first { !activeNames.contains($0) }

        // Visible set: active workspaces + one next inactive
        var visibleNames = activeNames
        if let next = nextInactive {
            visibleNames.insert(next)
        }

        let outerStack = NSStackView()
        outerStack.orientation = .vertical
        outerStack.alignment = .leading
        outerStack.spacing = 10
        outerStack.distribution = .fill
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(outerStack)

        // Header row: title on left, stats on right
        let stats = SystemStats.fetch()

        let headerContainer = NSView()
        headerContainer.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Workspaces")
        let titleFont = NSFont.systemFont(ofSize: 20, weight: .light)
        title.font = titleFont
        title.attributedStringValue = NSAttributedString(string: "Workspaces", attributes: [
            .font: titleFont,
            .foregroundColor: NSColor.white,
            .kern: 3.0,
        ])
        title.textColor = .white
        title.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.addSubview(title)

        // Right-side stats
        var statParts: [String] = []
        statParts.append("CPU \(Int(stats.cpuUsage))%")
        statParts.append(String(format: "RAM %.1f/%.0fGB", stats.memUsedGB, stats.memTotalGB))
        if let batt = stats.batteryPercent {
            let icon = stats.batteryCharging ? "⚡" : ""
            statParts.append("\(icon)\(batt)%")
        }

        let statsLabel = NSTextField(labelWithString: statParts.joined(separator: "  ·  "))
        statsLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        statsLabel.textColor = .secondaryLabelColor
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.addSubview(statsLabel)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
            title.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            statsLabel.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
            statsLabel.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            statsLabel.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 20),
            headerContainer.heightAnchor.constraint(equalToConstant: 28),
        ])

        outerStack.addArrangedSubview(headerContainer)

        for row in gridRows {
            let visibleInRow = row.filter { visibleNames.contains($0) }
            if visibleInRow.isEmpty { continue }

            let rowContainer = NSView()
            rowContainer.translatesAutoresizingMaskIntoConstraints = false
            var xOffset: CGFloat = 0
            var cells: [WorkspaceCell] = []
            for wsName in visibleInRow {
                let ws = wsMap[wsName] ?? WorkspaceInfo(name: wsName, windows: [], isFocused: false, monitorName: nil)
                let cell = WorkspaceCell(
                    workspace: ws,
                    hasNotification: notifiedWorkspaces.contains(wsName),
                    notifiedWindowIDs: OverlayNotifications.notifiedWindowIDs(workspace: wsName)
                )
                cell.onClick = { [weak self] name in
                    self?.onSelectWorkspace?(name)
                }
                cell.translatesAutoresizingMaskIntoConstraints = false
                cell.setContentCompressionResistancePriority(.init(1), for: .horizontal)
                rowContainer.addSubview(cell)
                let widthConstraint = cell.widthAnchor.constraint(equalToConstant: 150)
                widthConstraint.priority = .required
                NSLayoutConstraint.activate([
                    cell.leadingAnchor.constraint(equalTo: rowContainer.leadingAnchor, constant: xOffset),
                    cell.topAnchor.constraint(equalTo: rowContainer.topAnchor),
                    widthConstraint,
                    cell.heightAnchor.constraint(greaterThanOrEqualToConstant: 90),
                ])
                cells.append(cell)
                xOffset += 160 // 150 + 10 spacing
            }

            // Container sized to fit content
            let totalWidth = max(0, xOffset - 10)
            rowContainer.widthAnchor.constraint(equalToConstant: totalWidth).isActive = true
            // Pin height to tallest cell (equalTo, not greaterThan)
            for cell in cells {
                let bottom = cell.bottomAnchor.constraint(lessThanOrEqualTo: rowContainer.bottomAnchor)
                bottom.priority = .required
                bottom.isActive = true
                let bottomPin = rowContainer.bottomAnchor.constraint(equalTo: cell.bottomAnchor)
                bottomPin.priority = .defaultHigh
                bottomPin.isActive = true
            }

            // Prevent row from stretching vertically
            rowContainer.setContentHuggingPriority(.required, for: .vertical)
            rowContainer.setContentCompressionResistancePriority(.required, for: .vertical)

            visibleGrid.append(cells)
            outerStack.addArrangedSubview(rowContainer)
        }

        // Spacer to absorb extra vertical space
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.init(1), for: .vertical)
        outerStack.addArrangedSubview(spacer)

        // Footer
        let footerContainer = NSView()
        footerContainer.translatesAutoresizingMaskIntoConstraints = false

        // Left: focused workspace info
        let focusedWs = allWorkspaces.first { $0.isFocused }
        let focusedText = focusedWs.map { "Focused: \($0.name.uppercased())" } ?? ""
        let focusedLabel = NSTextField(labelWithString: focusedText)
        focusedLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        focusedLabel.textColor = .secondaryLabelColor
        focusedLabel.translatesAutoresizingMaskIntoConstraints = false
        footerContainer.addSubview(focusedLabel)

        // Right side: time + Claude usage bar
        let rightStack = NSStackView()
        rightStack.orientation = .horizontal
        rightStack.spacing = 14
        rightStack.alignment = .centerY
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        footerContainer.addSubview(rightStack)

        // Time
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d · h:mm a"
        let timeLabel = NSTextField(labelWithString: formatter.string(from: Date()))
        timeLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        timeLabel.textColor = .tertiaryLabelColor
        rightStack.addArrangedSubview(timeLabel)

        // Claude Code segmented usage bar (always shown, 0% if fetch fails)
        let pct = ClaudeUsage.fetch()?.sevenDayPercent ?? 0

        let ccBar = NSStackView()
        ccBar.orientation = .horizontal
        ccBar.spacing = 6
        ccBar.alignment = .centerY

        let ccLabel = NSTextField(labelWithString: "Claude Code")
        ccLabel.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        ccLabel.textColor = .secondaryLabelColor
        ccBar.addArrangedSubview(ccLabel)

        let totalBlocks = 10
        let filledBlocks = max(Int((Double(pct) / 100.0) * Double(totalBlocks) + 0.5), pct > 0 ? 1 : 0)
        let fillColor: NSColor = pct >= 90 ? .systemRed : .systemOrange

        let blocksRow = NSStackView()
        blocksRow.orientation = .horizontal
        blocksRow.spacing = 2
        blocksRow.alignment = .centerY

        for i in 0..<totalBlocks {
            let block = NSView()
            block.wantsLayer = true
            block.layer?.cornerRadius = 2
            if i < filledBlocks {
                block.layer?.backgroundColor = fillColor.cgColor
            } else {
                block.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
            }
            block.translatesAutoresizingMaskIntoConstraints = false
            block.widthAnchor.constraint(equalToConstant: 10).isActive = true
            block.heightAnchor.constraint(equalToConstant: 12).isActive = true
            blocksRow.addArrangedSubview(block)
        }

        ccBar.addArrangedSubview(blocksRow)

        let pctLabel = NSTextField(labelWithString: "\(pct)% of 7D")
        pctLabel.font = .monospacedSystemFont(ofSize: 10, weight: .bold)
        pctLabel.textColor = fillColor
        ccBar.addArrangedSubview(pctLabel)

        rightStack.addArrangedSubview(ccBar)

        NSLayoutConstraint.activate([
            focusedLabel.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor),
            focusedLabel.centerYAnchor.constraint(equalTo: footerContainer.centerYAnchor),
            rightStack.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor),
            rightStack.centerYAnchor.constraint(equalTo: footerContainer.centerYAnchor),
            footerContainer.heightAnchor.constraint(equalToConstant: 24),
        ])

        footerContainer.setContentHuggingPriority(.required, for: .vertical)
        outerStack.addArrangedSubview(footerContainer)

        // Default selection to the focused workspace
        var foundFocused = false
        for (r, row) in visibleGrid.enumerated() {
            for (c, cell) in row.enumerated() {
                if cell.isFocusedWorkspace {
                    selRow = r
                    selCol = c
                    foundFocused = true
                    break
                }
            }
            if foundFocused { break }
        }
        updateSelection()

        NSLayoutConstraint.activate([
            outerStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            outerStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            outerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            outerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            // Header and footer stretch to full width
            headerContainer.trailingAnchor.constraint(equalTo: outerStack.trailingAnchor),
            footerContainer.trailingAnchor.constraint(equalTo: outerStack.trailingAnchor),
        ])
    }

    // MARK: - Keyboard Navigation

    func handleKeyDown(_ event: NSEvent) {
        guard !visibleGrid.isEmpty else { return }
        switch event.keyCode {
        case 126: // Up arrow
            moveSelection(dRow: -1, dCol: 0)
        case 125: // Down arrow
            moveSelection(dRow: 1, dCol: 0)
        case 123: // Left arrow
            moveSelection(dRow: 0, dCol: -1)
        case 124: // Right arrow
            moveSelection(dRow: 0, dCol: 1)
        case 36: // Return
            confirmSelection()
        default:
            break
        }
    }

    private func moveSelection(dRow: Int, dCol: Int) {
        let newRow = selRow + dRow
        let newCol = selCol + dCol

        if dRow != 0 {
            // Vertical movement
            let targetRow = max(0, min(newRow, visibleGrid.count - 1))
            if targetRow != selRow {
                selRow = targetRow
                // Clamp column to new row's bounds
                selCol = min(selCol, visibleGrid[selRow].count - 1)
                updateSelection()
            }
        } else {
            // Horizontal movement
            let row = visibleGrid[selRow]
            let targetCol = max(0, min(newCol, row.count - 1))
            if targetCol != selCol {
                selCol = targetCol
                updateSelection()
            }
        }
    }

    private func updateSelection() {
        for (r, row) in visibleGrid.enumerated() {
            for (c, cell) in row.enumerated() {
                cell.setSelected(r == selRow && c == selCol)
            }
        }
    }

    private func confirmSelection() {
        guard selRow < visibleGrid.count, selCol < visibleGrid[selRow].count else { return }
        let cell = visibleGrid[selRow][selCol]
        onSelectWorkspace?(cell.workspaceName)
    }
}
