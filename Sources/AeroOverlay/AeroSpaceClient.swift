import Foundation

struct WindowInfo {
    let appName: String
    let windowID: Int
    let windowTitle: String
}

struct WorkspaceInfo {
    let name: String
    let windows: [WindowInfo]
    let isFocused: Bool
    let monitorName: String?
}

struct MonitorInfo {
    let id: Int
    let name: String
}

final class AeroSpaceClient {
    private var aerospacePath: String { SettingsStore.shared.aerospacePath }

    func fetchAll() -> [WorkspaceInfo] {
        // Run initial queries in parallel
        var workspaces: [String] = []
        var focused: String?
        var monitors: [MonitorInfo] = []

        let group1 = DispatchGroup()

        group1.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            workspaces = self.listWorkspaces()
            group1.leave()
        }
        group1.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            focused = self.focusedWorkspace()
            group1.leave()
        }
        group1.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            monitors = self.listMonitors()
            group1.leave()
        }
        group1.wait()

        // Run per-workspace window queries and monitor map in parallel
        let monitorWorkspaces = buildMonitorWorkspaceMap(monitors: monitors)
        var windowsMap: [String: [WindowInfo]] = [:]
        let lock = NSLock()
        let group2 = DispatchGroup()

        for ws in workspaces {
            group2.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let windows = self.listWindows(workspace: ws)
                lock.lock()
                windowsMap[ws] = windows
                lock.unlock()
                group2.leave()
            }
        }
        group2.wait()

        return workspaces.map { ws in
            WorkspaceInfo(
                name: ws,
                windows: windowsMap[ws] ?? [],
                isFocused: ws == focused,
                monitorName: monitorWorkspaces[ws]
            )
        }
    }

    func switchWorkspace(_ name: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: aerospacePath)
        process.arguments = ["workspace", name]
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: - Private

    private func listWorkspaces() -> [String] {
        guard let json = runJSON(["list-workspaces", "--all", "--json"]) as? [[String: Any]] else { return [] }
        return json.compactMap { $0["workspace"] as? String }
    }

    private func focusedWorkspace() -> String? {
        guard let json = runJSON(["list-workspaces", "--focused", "--json"]) as? [[String: Any]],
              let first = json.first else { return nil }
        return first["workspace"] as? String
    }

    private func listWindows(workspace: String) -> [WindowInfo] {
        guard let json = runJSON(["list-windows", "--workspace", workspace, "--json"]) as? [[String: Any]] else { return [] }
        return json.compactMap { dict in
            guard let app = dict["app-name"] as? String,
                  let wid = dict["window-id"] as? Int,
                  let title = dict["window-title"] as? String else { return nil }
            return WindowInfo(appName: app, windowID: wid, windowTitle: title)
        }
    }

    private func listMonitors() -> [MonitorInfo] {
        guard let json = runJSON(["list-monitors", "--json"]) as? [[String: Any]] else { return [] }
        return json.compactMap { dict in
            guard let id = dict["monitor-id"] as? Int,
                  let name = dict["monitor-name"] as? String else { return nil }
            return MonitorInfo(id: id, name: name)
        }
    }

    private func buildMonitorWorkspaceMap(monitors: [MonitorInfo]) -> [String: String] {
        var map: [String: String] = [:]
        for monitor in monitors {
            if let json = runJSON(["list-workspaces", "--monitor", "\(monitor.id)", "--json"]) as? [[String: Any]] {
                for ws in json {
                    if let name = ws["workspace"] as? String {
                        map[name] = monitor.name
                    }
                }
            }
        }
        return map
    }

    private func runJSON(_ arguments: [String]) -> Any? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: aerospacePath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            return nil
        }
    }
}
