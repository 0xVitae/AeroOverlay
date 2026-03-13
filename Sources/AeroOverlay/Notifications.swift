import Foundation

struct NotificationEntry {
    let workspace: String
    let windowID: Int
}

final class OverlayNotifications {
    private static let filePath: String = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/state/aerooverlay-notifications")
            .path
    }()

    /// Returns all pending notification entries (workspace + window ID).
    static func pendingEntries() -> [NotificationEntry] {
        guard let contents = try? String(contentsOfFile: filePath, encoding: .utf8) else { return [] }
        return contents.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: ":", maxSplits: 1)
            let workspace = String(parts[0])
            guard !workspace.isEmpty else { return nil }
            let windowID = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
            return NotificationEntry(workspace: workspace, windowID: windowID)
        }
    }

    /// Returns the set of workspace names that have pending notifications.
    static func pending() -> Set<String> {
        Set(pendingEntries().map { $0.workspace })
    }

    /// Returns the set of window IDs with pending notifications for a given workspace.
    static func notifiedWindowIDs(workspace: String) -> Set<Int> {
        Set(pendingEntries().filter { $0.workspace == workspace }.map { $0.windowID })
    }

    /// Clears the notification for a specific workspace.
    static func clear(workspace: String) {
        guard let contents = try? String(contentsOfFile: filePath, encoding: .utf8) else { return }
        let remaining = contents.split(separator: "\n").map(String.init).filter {
            !$0.isEmpty && !$0.hasPrefix("\(workspace):") && $0 != workspace
        }
        if remaining.isEmpty {
            try? FileManager.default.removeItem(atPath: filePath)
        } else {
            try? remaining.joined(separator: "\n").write(toFile: filePath, atomically: true, encoding: .utf8)
        }
    }
}
