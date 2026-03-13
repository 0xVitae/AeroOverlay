import AppKit

final class OverlayViewController: NSViewController {
    private let client = AeroSpaceClient()
    var onSelectWorkspace: ((String) -> Void)?
    private var visibleGrid: [[WorkspaceCell]] = [] // 2D grid of visible cells
    private var selRow = 0
    private var selCol = 0
    private var cacheLabel: NSTextField?

    // Keyboard-matching grid layout
    private let gridRows: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9"],
        ["q", "w", "e", "r", "t", "y", "o"],
        ["a", "s", "d", "f"],
    ]

    override func loadView() {
        let bg = NSVisualEffectView()
        bg.material = .hudWindow
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.maskImage = Self.roundedCornerMask(radius: 16)
        self.view = bg
    }

    /// Creates a mask image for NSVisualEffectView that produces true rounded corners
    /// without the square window backing showing through.
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
        WorkspaceCell.buildTerminalCwdMap(allWorkspaces: allWorkspaces)
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
            var visibleInRow = row.filter { visibleNames.contains($0) }
            // Always show first key of each row as blank if row is empty
            if visibleInRow.isEmpty {
                visibleInRow = []
                let slot = (name: row[0], blank: true)
                let rowContainer = NSView()
                rowContainer.translatesAutoresizingMaskIntoConstraints = false
                var cells: [WorkspaceCell] = []
                let ws = WorkspaceInfo(name: slot.name, windows: [], isFocused: false, monitorName: nil)
                let cell = WorkspaceCell(workspace: ws, isBlank: true)
                cell.onClick = { [weak self] name in self?.onSelectWorkspace?(name) }
                cell.translatesAutoresizingMaskIntoConstraints = false
                cell.setContentCompressionResistancePriority(.init(1), for: .horizontal)
                rowContainer.addSubview(cell)
                let widthConstraint = cell.widthAnchor.constraint(equalToConstant: 150)
                widthConstraint.priority = .required
                NSLayoutConstraint.activate([
                    cell.leadingAnchor.constraint(equalTo: rowContainer.leadingAnchor),
                    cell.topAnchor.constraint(equalTo: rowContainer.topAnchor),
                    widthConstraint,
                    cell.heightAnchor.constraint(equalToConstant: 90),
                    cell.bottomAnchor.constraint(equalTo: rowContainer.bottomAnchor),
                ])
                cells.append(cell)
                rowContainer.widthAnchor.constraint(equalToConstant: 150).isActive = true
                rowContainer.setContentHuggingPriority(.required, for: .vertical)
                rowContainer.setContentCompressionResistancePriority(.required, for: .vertical)
                visibleGrid.append(cells)
                outerStack.addArrangedSubview(rowContainer)
                continue
            }

            // Build slot list: visible workspaces with one blank between non-adjacent ones
            var slotKeys: [(name: String, blank: Bool)] = []
            for (i, wsName) in visibleInRow.enumerated() {
                if i > 0 {
                    let prevIdx = row.firstIndex(of: visibleInRow[i - 1])!
                    let curIdx = row.firstIndex(of: wsName)!
                    if curIdx - prevIdx > 1 {
                        // Add one blank: the next key after the previous visible
                        let blankKey = row[prevIdx + 1]
                        slotKeys.append((name: blankKey, blank: true))
                    }
                }
                slotKeys.append((name: wsName, blank: false))
            }

            let rowContainer = NSView()
            rowContainer.translatesAutoresizingMaskIntoConstraints = false
            var xOffset: CGFloat = 0
            var cells: [WorkspaceCell] = []
            for slot in slotKeys {
                let wsName = slot.name
                let isVisible = !slot.blank
                let ws = isVisible
                    ? (wsMap[wsName] ?? WorkspaceInfo(name: wsName, windows: [], isFocused: false, monitorName: nil))
                    : WorkspaceInfo(name: wsName, windows: [], isFocused: false, monitorName: nil)
                let cell = WorkspaceCell(
                    workspace: ws,
                    hasNotification: notifiedWorkspaces.contains(wsName),
                    notifiedWindowIDs: OverlayNotifications.notifiedWindowIDs(workspace: wsName),
                    isBlank: !isVisible
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
            // Pin height to tallest cell; blank cells match row height
            for cell in cells {
                let bottom = cell.bottomAnchor.constraint(lessThanOrEqualTo: rowContainer.bottomAnchor)
                bottom.priority = .required
                bottom.isActive = true
                if cell.isBlank {
                    // Force blank cells to fill the row height
                    cell.bottomAnchor.constraint(equalTo: rowContainer.bottomAnchor).isActive = true
                } else {
                    let bottomPin = rowContainer.bottomAnchor.constraint(equalTo: cell.bottomAnchor)
                    bottomPin.priority = .defaultHigh
                    bottomPin.isActive = true
                }
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
        let usageInfo = ClaudeUsage.fetch()
        let pct = usageInfo?.sevenDayPercent ?? 0

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

        if let cachedAt = usageInfo?.cachedAt {
            let ago = RelativeDateTimeFormatter()
            ago.unitsStyle = .abbreviated
            let cacheLabel = NSTextField(labelWithString: ago.localizedString(for: cachedAt, relativeTo: Date()))
            cacheLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            cacheLabel.textColor = .tertiaryLabelColor
            cacheLabel.isHidden = true
            ccBar.addArrangedSubview(cacheLabel)

            let click = NSClickGestureRecognizer(target: self, action: #selector(toggleCacheLabel))
            pctLabel.addGestureRecognizer(click)
            self.cacheLabel = cacheLabel
        }

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
                // Skip blank cells
                if visibleGrid[selRow][selCol].isBlank {
                    if let next = nearestNonBlank(row: selRow, from: selCol) {
                        selCol = next
                    }
                }
                updateSelection()
            }
        } else {
            // Horizontal movement
            let row = visibleGrid[selRow]
            var targetCol = max(0, min(newCol, row.count - 1))
            // Skip over blank cells in the direction of movement
            while targetCol >= 0 && targetCol < row.count && row[targetCol].isBlank {
                targetCol += dCol
            }
            targetCol = max(0, min(targetCol, row.count - 1))
            if targetCol != selCol && !row[targetCol].isBlank {
                selCol = targetCol
                updateSelection()
            }
        }
    }

    private func nearestNonBlank(row: Int, from col: Int) -> Int? {
        let cells = visibleGrid[row]
        // Search outward from col
        for offset in 0..<cells.count {
            let left = col - offset
            let right = col + offset
            if left >= 0 && !cells[left].isBlank { return left }
            if right < cells.count && !cells[right].isBlank { return right }
        }
        return nil
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
        guard !cell.isBlank else { return }
        onSelectWorkspace?(cell.workspaceName)
    }

    @objc private func toggleCacheLabel() {
        guard let label = cacheLabel else { return }
        label.isHidden.toggle()
    }

}
