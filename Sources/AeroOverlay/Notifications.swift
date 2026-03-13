import Foundation

final class OverlayNotifications {
    private static let filePath: String = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/state/aerooverlay-notifications")
            .path
    }()

    /// Returns the set of workspace names that have pending notifications.
    static func pending() -> Set<String> {
        guard let contents = try? String(contentsOfFile: filePath, encoding: .utf8) else { return [] }
        let names = contents.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        return Set(names)
    }

    /// Clears the notification for a specific workspace.
    static func clear(workspace: String) {
        guard let contents = try? String(contentsOfFile: filePath, encoding: .utf8) else { return }
        let remaining = contents.split(separator: "\n").map(String.init).filter { $0 != workspace && !$0.isEmpty }
        if remaining.isEmpty {
            try? FileManager.default.removeItem(atPath: filePath)
        } else {
            try? remaining.joined(separator: "\n").write(toFile: filePath, atomically: true, encoding: .utf8)
        }
    }
}
