import Foundation

/// Đọc rate_limits mà Codex CLI ghi vào ~/.codex/sessions/YYYY/MM/DD/*.jsonl
enum CodexProvider {
    static let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions")

    static func fetch() -> ProviderUsage {
        var usage = ProviderUsage(id: "codex", name: "ChatGPT Codex")
        let files = recentFiles()
        usage.status = FileScan.status(lastWrite: files.first?.1)

        // File mới nhất có thể chưa có event rate_limits -> lùi dần.
        for (url, _) in files.prefix(10) {
            if let limits = lastRateLimits(in: url) {
                usage.session = window(limits["primary"])
                usage.weekly = window(limits["secondary"])
                return usage
            }
        }
        usage.error = files.isEmpty ? "Chưa có session Codex nào" : "Không tìm thấy dữ liệu rate limit"
        return usage
    }

    /// File .jsonl trong các thư mục ngày gần nhất, mới nhất trước.
    private static func recentFiles() -> [(URL, Date)] {
        let fm = FileManager.default
        func subdirs(_ u: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.hasDirectoryPath }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
        }
        var dayDirs: [URL] = []
        outer: for y in subdirs(root) {
            for m in subdirs(y) {
                for d in subdirs(m) {
                    dayDirs.append(d)
                    if dayDirs.count >= 7 { break outer }
                }
            }
        }
        return dayDirs.flatMap { FileScan.jsonlFiles(in: $0) }.sorted { $0.1 > $1.1 }
    }

    private static func lastRateLimits(in url: URL) -> [String: Any]? {
        guard let text = FileScan.tail(url) else { return nil }
        for line in text.split(separator: "\n").reversed() where line.contains("\"rate_limits\"") {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any],
                  let limits = payload["rate_limits"] as? [String: Any] else { continue }
            return limits
        }
        return nil
    }

    private static func window(_ raw: Any?) -> UsageWindow? {
        guard let w = raw as? [String: Any], let pct = w["used_percent"] as? Double else { return nil }
        let reset = (w["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
        // Cửa sổ đã reset kể từ lần ghi cuối -> usage về 0.
        if let r = reset, r < Date() { return UsageWindow(percent: 0, resetsAt: nil) }
        return UsageWindow(percent: pct, resetsAt: reset)
    }
}
