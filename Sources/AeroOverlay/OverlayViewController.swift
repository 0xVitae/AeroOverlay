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
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(outerStack)

        // Title
        let title = NSTextField(labelWithString: "Workspaces")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.textColor = .white
        outerStack.addArrangedSubview(title)

        for row in gridRows {
            let visibleInRow = row.filter { visibleNames.contains($0) }
            if visibleInRow.isEmpty { continue }

            let rowContainer = NSView()
            rowContainer.translatesAutoresizingMaskIntoConstraints = false
            var xOffset: CGFloat = 0
            var cells: [WorkspaceCell] = []
            for wsName in visibleInRow {
                let ws = wsMap[wsName] ?? WorkspaceInfo(name: wsName, windows: [], isFocused: false, monitorName: nil)
                let cell = WorkspaceCell(workspace: ws)
                cell.onClick = { [weak self] name in
                    self?.onSelectWorkspace?(name)
                }
                cell.translatesAutoresizingMaskIntoConstraints = false
                rowContainer.addSubview(cell)
                NSLayoutConstraint.activate([
                    cell.leadingAnchor.constraint(equalTo: rowContainer.leadingAnchor, constant: xOffset),
                    cell.topAnchor.constraint(equalTo: rowContainer.topAnchor),
                    cell.widthAnchor.constraint(equalToConstant: 130),
                    cell.heightAnchor.constraint(greaterThanOrEqualToConstant: 90),
                ])
                cells.append(cell)
                xOffset += 140 // 130 + 10 spacing
            }

            // Container sized to fit content
            let totalWidth = max(0, xOffset - 10)
            rowContainer.widthAnchor.constraint(equalToConstant: totalWidth).isActive = true
            // Height matches tallest cell
            if let lastCell = cells.last {
                rowContainer.bottomAnchor.constraint(greaterThanOrEqualTo: lastCell.bottomAnchor).isActive = true
            }
            for cell in cells {
                rowContainer.bottomAnchor.constraint(greaterThanOrEqualTo: cell.bottomAnchor).isActive = true
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
            outerStack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20),
            outerStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            outerStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            outerStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
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
