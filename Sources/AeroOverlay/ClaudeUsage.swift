import Foundation

struct ClaudeUsageInfo {
    let fiveHourPercent: Int?
    let sevenDayPercent: Int?
    let sevenDaySonnetPercent: Int?
    let extraUsedCredits: Double?
    let extraMonthlyLimit: Double?
    let cachedAt: Date?
}

final class ClaudeUsage {
    private static let cachePath: String = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/state/aerooverlay-claude-usage.json")
            .path
    }()

    /// Returns cached data immediately. Use fetchAsync for background refresh.
    static func fetch() -> ClaudeUsageInfo? {
        return loadCache()
    }

    /// Fetches fresh data from the API in the background and calls completion on main thread.
    static func fetchAsync(completion: @escaping (ClaudeUsageInfo?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let token = getOAuthToken() else {
                DispatchQueue.main.async { completion(loadCache()) }
                return
            }
            let result = fetchUsageFromAPI(token: token)
            if let result = result {
                saveCache(result)
            }
            DispatchQueue.main.async { completion(result ?? loadCache()) }
        }
    }

    private static func saveCache(_ info: ClaudeUsageInfo) {
        var dict: [String: Any] = [:]
        if let v = info.fiveHourPercent { dict["fiveHour"] = v }
        if let v = info.sevenDayPercent { dict["sevenDay"] = v }
        if let v = info.sevenDaySonnetPercent { dict["sevenDaySonnet"] = v }
        if let v = info.extraUsedCredits { dict["extraUsed"] = v }
        if let v = info.extraMonthlyLimit { dict["extraLimit"] = v }
        dict["ts"] = Date().timeIntervalSince1970
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            try? data.write(to: URL(fileURLWithPath: cachePath))
        }
    }

    private static func loadCache() -> ClaudeUsageInfo? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: cachePath)),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let cachedAt: Date? = (dict["ts"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }
        return ClaudeUsageInfo(
            fiveHourPercent: dict["fiveHour"] as? Int,
            sevenDayPercent: dict["sevenDay"] as? Int,
            sevenDaySonnetPercent: dict["sevenDaySonnet"] as? Int,
            extraUsedCredits: dict["extraUsed"] as? Double,
            extraMonthlyLimit: dict["extraLimit"] as? Double,
            cachedAt: cachedAt
        )
    }

    private static func getOAuthToken() -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let jsonStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let jsonData = jsonStr.data(using: .utf8),
                  let creds = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let oauth = creds["claudeAiOauth"] as? [String: Any],
                  let accessToken = oauth["accessToken"] as? String else { return nil }
            return accessToken
        } catch {
            return nil
        }
    }

    private static func fetchUsageFromAPI(token: String) -> ClaudeUsageInfo? {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.0.32", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 3

        var result: ClaudeUsageInfo?
        let semaphore = DispatchSemaphore(value: 0)

        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { semaphore.signal() }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let parsed = parseUsage(json) else { return }
            result = parsed
        }
        task.resume()
        semaphore.wait()
        return result
    }

    private static func parseUsage(_ json: [String: Any]) -> ClaudeUsageInfo? {
        // Don't parse error responses
        if json["error"] != nil { return nil }
        var fiveHour: Int?
        var sevenDay: Int?
        var sevenDaySonnet: Int?
        var extraUsed: Double?
        var extraLimit: Double?

        if let fh = json["five_hour"] as? [String: Any],
           let util = fh["utilization"] as? Double {
            fiveHour = Int(util)
        }
        if let sd = json["seven_day"] as? [String: Any],
           let util = sd["utilization"] as? Double {
            sevenDay = Int(util)
        }
        if let sds = json["seven_day_sonnet"] as? [String: Any],
           let util = sds["utilization"] as? Double {
            sevenDaySonnet = Int(util)
        }
        if let extra = json["extra_usage"] as? [String: Any] {
            extraUsed = extra["used_credits"] as? Double
            extraLimit = extra["monthly_limit"] as? Double
        }

        return ClaudeUsageInfo(
            fiveHourPercent: fiveHour,
            sevenDayPercent: sevenDay,
            sevenDaySonnetPercent: sevenDaySonnet,
            extraUsedCredits: extraUsed,
            extraMonthlyLimit: extraLimit,
            cachedAt: nil
        )
    }
}
